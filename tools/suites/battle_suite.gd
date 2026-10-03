extends RefCounted
## battle_suite.gd —— 战斗系统冒烟测试
##
## 由 tools/smoke_battle.gd 在第一帧之后动态 load()。
##
## 覆盖四层：
##   1. 配置层：第一章 10 关 / 14 只怪 / Boss 特性 / 环境效果 / 战力反解是否自洽；
##   2. 战场几何：18 个格子的落点、排间距、纵深方向、全部落在可视区内；
##   3. 战斗内核：ATB 顺序、伤害公式、克制、减伤、治疗、怒气大招、胜负、确定性；
##   4. 战斗界面：场景骨架、单位与名牌节点数、血条随血量、按钮交互、结算入账。
##
## 之所以把「配置自洽」也放进来：关卡的 power_scale 是脚本反解出来的，
## 一旦有人手改建议战力而忘了重跑脚本，数值就会悄悄跑偏 —— 这里钉死。

var passed := 0
var failed := 0

const CORE_PATH := "res://scripts/battle_core.gd"
const SCENE_PATH := "res://scenes/battle.tscn"
const SAVE_PATH := "user://save.json"
const SEED := 20260927

var _tree: SceneTree
var _scene: Node
var _core_script: Script
var _save_backup := ""
var _had_save := false


func run(tree: SceneTree) -> Dictionary:
	_tree = tree
	print("\n========== 卡牌大冒险 · 战斗系统冒烟 ==========")

	_backup_save()
	SaveDB.reset_profile()
	StaminaSys.fill()
	BattleCtx.reset()

	_core_script = load(CORE_PATH)
	if _core_script == null:
		_ok("BattleCore 脚本可加载", false)
		print("\n---------- 结果：通过 %d / 失败 %d ----------" % [passed, failed])
		_restore_save()
		return {"passed": passed, "failed": failed}

	_check_config()
	_check_monsters()
	_check_geometry()
	_check_combat_math()
	_check_synergy_open()
	_check_battle_flow()
	_check_determinism()
	_check_scene()
	_check_interact()

	print("\n---------- 结果：通过 %d / 失败 %d ----------" % [passed, failed])
	_restore_save()
	return {"passed": passed, "failed": failed}


func _backup_save() -> void:
	_had_save = FileAccess.file_exists(SAVE_PATH)
	if not _had_save:
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f != null:
		_save_backup = f.get_as_text()
		f.close()


func _restore_save() -> void:
	if not _had_save:
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(_save_backup)
		f.close()
		print("[smoke] 已还原测试前的存档")


func _ok(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  [PASS] %s%s" % [label, ("  " + detail) if detail != "" else ""])
	else:
		failed += 1
		print("  [FAIL] %s%s" % [label, ("  " + detail) if detail != "" else ""])


func _eq(label: String, got, want) -> void:
	_ok(label, got == want, "got=%s want=%s" % [str(got), str(want)])


# ---------------------------------------------------------------- 配置层

func _check_config() -> void:
	print("\n· 全章节关卡表（一+二+三章聚合）")
	var list: Array = GameDB.chapter_stages()
	_eq("关卡数", list.size(), 30)
	_eq("章节标题", GameDB.chapter_title(), "云上浮岛 · 初始之痕")

	var ids: Array = []
	var nos: Array = []
	for raw in list:
		var s: Dictionary = raw
		ids.append(int(s.get("id", 0)))
		nos.append(int(s.get("no", 0)))
	# chapter_stages() 跨章聚合：第一章 1001-1010 + 第二章 2001-2010 + 第三章 3001-3010（各自序号 1-10）
	_eq("关卡编号", ids, [1001, 1002, 1003, 1004, 1005, 1006, 1007, 1008, 1009, 1010,
		2001, 2002, 2003, 2004, 2005, 2006, 2007, 2008, 2009, 2010,
		3001, 3002, 3003, 3004, 3005, 3006, 3007, 3008, 3009, 3010])
	_eq("章节内序号", nos, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10,
		1, 2, 3, 4, 5, 6, 7, 8, 9, 10])

	var kinds: Dictionary = {}
	for raw in GameDB.adventure().get("stage_kinds", []):
		if raw is Dictionary:
			kinds[str(raw.get("id", ""))] = true
	for raw in list:
		var s: Dictionary = raw
		var sid := int(s.get("id", 0))
		_ok("#%d 类型合法" % sid, kinds.has(str(s.get("kind", ""))), str(s.get("kind", "")))
		_ok("#%d 有机制说明" % sid, str(s.get("mechanic", "")) != "")
		_ok("#%d 有 theme" % sid, not (s.get("theme", {}) as Dictionary).is_empty())
		_ok("#%d 有 bg 字段（留空=用 theme 程序化铺）" % sid, s.has("bg"))

	# 体力：以关卡自身为准，引导关免费、高难支线最贵
	_eq("1001 引导关免费", GameDB.stage_stamina(1001), 0)
	_eq("1003 精英 8 点", GameDB.stage_stamina(1003), 8)
	_eq("1008 高难支线 10 点", GameDB.stage_stamina(1008), 10)
	_eq("1010 Boss 8 点", GameDB.stage_stamina(1010), 8)
	_eq("1005 事件节点不耗体力", GameDB.stage_stamina(1005), 0)

	# 战力反解自洽：敌方实际总战力 ≈ 建议战力 × difficulty
	for raw in list:
		var s: Dictionary = raw
		var sid := int(s.get("id", 0))
		var enemies: Array = s.get("enemies", [])
		if enemies.is_empty():
			_ok("#%d 非战斗节点无敌人阵容" % sid, not GameDB.stage_is_battle(sid))
			continue
		_ok("#%d 是战斗节点" % sid, GameDB.stage_is_battle(sid))
		var core: RefCounted = _core_script.new()
		core.setup(sid, [], {"seed": SEED})
		var want := float(s.get("recommend_power", 0)) * float(s.get("difficulty", 0.85))
		var got := float(core.team_power("enemy"))
		# 环境效果（1004 风暴气场给风属性 +20% 攻速）是在反解之后叠加的，
		# 所以带环境的关卡实测值会高出几个百分点 —— 这不是偏差，是设计。
		var tol := 0.02 if (s.get("env", {}) as Dictionary).is_empty() else 0.05
		_ok("#%d 敌方战力与建议战力对得上" % sid, absf(got - want) / maxf(1.0, want) < tol,
			"敌方 %d vs 目标 %.0f (%.1f%%)" % [int(got), want, (got - want) / want * 100.0])
		_ok("#%d 敌人槽位合法" % sid, _slots_valid(enemies))

	# 章节最终 Boss 的特性必须原样落进配置
	var boss: Dictionary = GameDB.monster("stone_warden")
	_ok("巨石守卫标记为 Boss", bool(boss.get("boss", false)))
	var traits: Array = boss.get("traits", [])
	_eq("Boss 有两条特性", traits.size(), 2)
	var armor := _trait(traits, "granite_armor")
	_ok("花岗岩护甲 物理减伤 30%", is_equal_approx(float(armor.get("phys_reduction", 0.0)), 0.30),
		str(armor.get("phys_reduction")))
	_ok("花岗岩护甲 开局护盾 20% 最大生命", is_equal_approx(float(armor.get("shield_pct", 0.0)), 0.20),
		str(armor.get("shield_pct")))
	var quake := _trait(traits, "quake_slam")
	_ok("裂地震击 200% 前排物理", is_equal_approx(float(quake.get("mult", 0.0)), 2.0),
		str(quake.get("mult")))
	_ok("裂地震击 50% 眩晕", is_equal_approx(float(quake.get("stun_chance", 0.0)), 0.5),
		str(quake.get("stun_chance")))
	_ok("裂地震击 打前排全体", str(quake.get("target", "")) == "front_row")

	var s1010: Dictionary = GameDB.chapter_stage(1010)
	var has_boss := false
	for raw in s1010.get("enemies", []):
		if str((raw as Dictionary).get("mob", "")) == "stone_warden":
			has_boss = true
	_ok("1010 阵容里有巨石守卫", has_boss)

	# 环境效果
	var env: Dictionary = GameDB.chapter_stage(1004).get("env", {})
	_eq("1004 环境效果名", str(env.get("name", "")), "风暴气场")
	_eq("1004 环境作用元素", str(env.get("element", "")), "wind")
	_ok("1004 环境倍率为加速", float(env.get("mult", 1.0)) > 1.0, str(env.get("mult")))

	# 非战斗节点
	_eq("1005 交互选项数", GameDB.chapter_stage(1005).get("options", []).size(), 3)
	_ok("1007 是休息节点", str(GameDB.chapter_stage(1007).get("kind", "")) == "rest")


func _slots_valid(enemies: Array) -> bool:
	var seen: Array = []
	for raw in enemies:
		var e: Dictionary = raw
		var slot := int(e.get("slot", 0))
		if slot < 1 or slot > 9 or slot in seen:
			return false
		seen.append(slot)
	return true


func _trait(traits: Array, id: String) -> Dictionary:
	for raw in traits:
		if str((raw as Dictionary).get("id", "")) == id:
			return raw
	return {}


func _check_monsters() -> void:
	print("\n· 怪物表")
	var order: Array = GameDB.monster_order()
	_eq("怪物数量", order.size(), 44)
	for key in order:
		var m: Dictionary = GameDB.monster(str(key))
		_ok("怪物 %s 有名有元素" % str(key),
			str(m.get("name", "")) != "" and GameDB.element(str(m.get("element", ""))) != {})
		_ok("怪物 %s 图标已导入" % str(key), ResourceLoader.exists(str(m.get("icon", ""))),
			str(m.get("icon", "")))
		var base: Dictionary = m.get("base", {})
		var ok_stats := true
		for k in ["hp", "atk", "def", "mres", "crit", "spd"]:
			if not base.has(k) or float(base[k]) <= 0.0:
				ok_stats = false
		_ok("怪物 %s 面板字段齐全" % str(key), ok_stats)
		_ok("怪物 %s 有行动定义" % str(key), not (m.get("action", {}) as Dictionary).is_empty())

	_ok("软泥怪是引导关的杂兵", float(GameDB.monster("slime").base.hp) < 600.0)
	_ok("巨石守卫是全场最高血量",
		float(GameDB.monster("stone_warden").base.hp) > float(GameDB.monster("ruin_guard").base.hp) * 3.0)


# ---------------------------------------------------------------- 战场几何

func _check_geometry() -> void:
	print("\n· 战场几何")
	var b: Dictionary = GameDB.battle_cfg()
	var rect: Array = b.get("screen_rect", [])
	_eq("可视区字段完整", rect.size(), 4)
	var core: RefCounted = _core_script.new()
	var all: Array = []
	for side in ["enemy", "player"]:
		var cells: Array = []
		for slot in range(1, 10):
			var p: Vector2 = core.cell_pos(side, slot)
			all.append(p)
			cells.append(p)
			_ok("%s slot%d 落在战场可视区内" % [side, slot],
				p.x > float(rect[0]) and p.x < float(rect[2]) \
				and p.y > float(rect[1]) and p.y < float(rect[3]),
				"(%.0f,%.0f)" % [p.x, p.y])
		# 同侧 9 格两两不重合
		var dup := 0
		for i in cells.size():
			for j in range(i + 1, cells.size()):
				if (cells[i] as Vector2).distance_to(cells[j]) < 1.0:
					dup += 1
		_eq("%s 侧 9 格互不重合" % side, dup, 0)

	# 纵深方向：敌方后排在上（y 更小），我方后排在下（y 更大）
	var e_back: Vector2 = core.cell_pos("enemy", 8)
	var e_front: Vector2 = core.cell_pos("enemy", 2)
	_ok("敌方后排比前排高", e_back.y < e_front.y, "back=%.0f front=%.0f" % [e_back.y, e_front.y])
	var p_back: Vector2 = core.cell_pos("player", 8)
	var p_front: Vector2 = core.cell_pos("player", 2)
	_ok("我方后排比前排低", p_back.y > p_front.y, "back=%.0f front=%.0f" % [p_back.y, p_front.y])

	# 两侧前排在中线附近正对（同一列 x 相同）
	_ok("两侧前排同列对齐", absf(e_front.x - p_front.x) < 1.0,
		"%.0f vs %.0f" % [e_front.x, p_front.x])
	# 我方后排必须让开底部行动顺序条
	var strip_y := 996.0
	_ok("我方后排让开底部行动顺序条", p_back.y < strip_y, "%.0f < %.0f" % [p_back.y, strip_y])
	# 敌方后排的名牌（头顶上方）必须让开顶部信息条
	var token: Dictionary = b.get("token", {})
	var plate_top := e_back.y - float(token.get("monster_h", 120)) - 6.0 \
		- float(token.get("block_h", 42))
	_ok("敌方后排名牌让开顶部信息条", plate_top > 108.0, "名牌顶 %.0f" % plate_top)

	# 排间距与配置一致
	var gap := absf(float((e_front - e_back).y)) / 2.0
	_eq("敌方排间距 = row_step.y", int(round(gap)), int(absf(float(b.row_step[1]))))


# ---------------------------------------------------------------- 战斗数学

func _check_combat_math() -> void:
	print("\n· 战斗数学")
	var core: RefCounted = _core_script.new()
	core.setup(1010, _core_script.player_entries(), {"seed": SEED})

	# 元素克制
	_ok("火克风", GameDB.is_counter("fire", "wind"))
	_ok("风克地", GameDB.is_counter("wind", "earth"))
	_ok("地不克火", not GameDB.is_counter("earth", "fire"))
	_ok("克制倍率 125%", is_equal_approx(GameDB.damage_multiplier("fire", "wind"), 1.25))
	_ok("克制加暴击", GameDB.crit_bonus("fire", "wind") > 0.0)

	# 开局护盾 = 20% 最大生命
	var boss: Dictionary = core.boss_unit()
	_ok("场上有 Boss", not boss.is_empty())
	if not boss.is_empty():
		_eq("Boss 开局护盾 = 20% 最大生命",
			int(boss.shield), int(round(float(boss.max_hp) * 0.20)))
		_ok("Boss 物理减伤 30%", is_equal_approx(core._phys_reduction(boss), 0.30),
			str(core._phys_reduction(boss)))

	# 物理减伤的实际效果：同一攻击者打「带护甲的 Boss」与「剥掉护甲的同一单位」，
	# 多次采样求均值，比值应落在 0.70 附近
	var plain: Dictionary = boss.duplicate(true)
	plain["traits"] = []
	var attacker := {"element": "light", "atk": 400.0, "crit": 0.0, "crit_dmg": 1.5,
		"buff_atk": 0.0}
	var sum_boss := 0.0
	var sum_plain := 0.0
	var n := 400
	for _i in n:
		sum_boss += float(core.compute_damage(attacker, boss, 1.0, "phys").value)
		sum_plain += float(core.compute_damage(attacker, plain, 1.0, "phys").value)
	var ratio := sum_boss / maxf(1.0, sum_plain)
	_ok("护甲把物理伤害压到约 70%", absf(ratio - 0.70) < 0.05, "实测比值 %.3f" % ratio)
	# 魔法伤害不吃物理护甲
	var sum_boss_m := 0.0
	var sum_plain_m := 0.0
	for _i in n:
		sum_boss_m += float(core.compute_damage(attacker, boss, 1.0, "magic").value)
		sum_plain_m += float(core.compute_damage(attacker, plain, 1.0, "magic").value)
	_ok("护甲不影响魔法伤害", absf(sum_boss_m / maxf(1.0, sum_plain_m) - 1.0) < 0.05,
		"比值 %.3f" % (sum_boss_m / maxf(1.0, sum_plain_m)))

	# 防御越高伤害越低
	var soft := {"element": "light", "def": 50.0, "mres": 50.0, "traits": [], "shield": 0}
	var hard := {"element": "light", "def": 800.0, "mres": 800.0, "traits": [], "shield": 0}
	var s1 := 0
	var s2 := 0
	for _i in 200:
		s1 += int(core.compute_damage(attacker, soft, 1.0, "phys").value)
		s2 += int(core.compute_damage(attacker, hard, 1.0, "phys").value)
	_ok("高防御吃到的物理伤害更低", s2 < s1, "低防 %d vs 高防 %d" % [s1, s2])

	# 目标选择：前排优先
	var target: Array = core.resolve_targets(_first_player(core), "nearest_front", false)
	_ok("nearest_front 打的是对面前排", target.size() == 1 and str(target[0].row) == "front",
		str(target[0].row) if target.size() > 0 else "无目标")
	# 切后排
	var back: Array = core.resolve_targets(_first_player(core), "lowest_hp_back", false)
	_ok("lowest_hp_back 打的是对面后排", back.size() == 1 and str(back[0].row) == "back",
		str(back[0].row) if back.size() > 0 else "无目标")
	# 群攻：中排有几个就打几个
	var mid_alive := 0
	for u in core.team_of("enemy"):
		if str(u.row) == "middle":
			mid_alive += 1
	var aoe: Array = core.resolve_targets(_first_player(core), "middle_row", true)
	_eq("middle_row 群攻覆盖整排", aoe.size(), mid_alive)

	# ATB：攻速最高的先动
	var fastest: Dictionary = {}
	for u in core.units:
		if fastest.is_empty() or float(u.spd) > float(fastest.spd):
			fastest = u
	_eq("先手是最快的单位", int(core.peek_actor().uid), int(fastest.uid))


func _first_player(core: RefCounted) -> Dictionary:
	var list: Array = core.team_of("player")
	return list[0] if not list.is_empty() else {}


func _unit_by_id(core: RefCounted, char_id: String) -> Dictionary:
	for u in core.team_of("player"):
		if str(u.get("char_id", "")) == char_id:
			return u
	return {}


# ---------------------------------------------------------------- 羁绊开局效果

## 羁绊的战斗级效果必须在战斗里真的兑现：开局能量 / 开局护盾 / 元素伤害。
## 配置与求值已由 formation_suite 钉住，这一段只管「战斗内核读不读、算不算」。
func _check_synergy_open() -> void:
	print("\n· 羁绊开局效果（战斗侧）")

	# ---- 光暗交织：神圣牧师 + 暗夜刺客 → 全队暴击 +5%、开局 15 点能量 ----
	var ld := RealmDB.apply_synergies(RealmDB.roster_of([
		{"slot": 7, "char_id": "shadow_assassin"},
		{"slot": 8, "char_id": "holy_priest"},
	]))
	var ld_core: RefCounted = _core_script.new()
	ld_core.setup(1001, ld, {"seed": SEED})
	var assassin := _unit_by_id(ld_core, "shadow_assassin")
	_ok("暗夜刺客场上找到", not assassin.is_empty())
	if not assassin.is_empty():
		_eq("开局能量 = 15", int(assassin.get("energy", 0)), 15)
		var base_crit: float = float(GameDB.character("shadow_assassin").get("base", {}).get("crit", 0.0))
		_ok("暴击率吃到 +5%（加算）",
			is_equal_approx(float(assassin.get("crit", 0.0)), base_crit + 0.05),
			"%.3f vs %.3f" % [float(assassin.get("crit", 0.0)), base_crit + 0.05])

	# ---- 全元素共鸣：队内 4 种元素 → 全员开局护盾 15% 最大生命 ----
	var four := RealmDB.apply_synergies(RealmDB.roster_of([
		{"slot": 2, "char_id": "knight_rock"},
		{"slot": 5, "char_id": "pyro_girl"},
		{"slot": 6, "char_id": "elf_ranger"},
		{"slot": 8, "char_id": "holy_priest"},
	]))
	var shield_core: RefCounted = _core_script.new()
	shield_core.setup(1001, four, {"seed": SEED})
	var all_shielded := true
	var detail := ""
	for u in shield_core.team_of("player"):
		var want := int(round(float(u["max_hp"]) * 0.15))
		if int(u["shield"]) != want:
			all_shielded = false
			detail += "%s %d≠%d " % [str(u["name"]), int(u["shield"]), want]
	_ok("四人各自带上 15% 最大生命的开局护盾", all_shielded, detail)

	# ---- 云端先锋队：火元素伤害 +10% ----
	# 同一内核里采样 200 次，带加成的均值应比剥掉加成的同一个人高约 10%。
	# 单次伤害带暴击与 ±5% 浮动，所以比均值；区间留够 3σ（约 ±6%）。
	var cv := RealmDB.apply_synergies(RealmDB.roster_of([
		{"slot": 1, "char_id": "flame_knight"},
		{"slot": 5, "char_id": "arcane_girl"},
	]))
	var elem_core: RefCounted = _core_script.new()
	elem_core.setup(1001, cv, {"seed": SEED})
	var caster := _unit_by_id(elem_core, "arcane_girl")
	var foes: Array = elem_core.team_of("enemy")
	_ok("自动找到敌方可打目标", not foes.is_empty() and not caster.is_empty())
	if not foes.is_empty() and not caster.is_empty():
		var foe: Dictionary = foes[0]
		var bare: Dictionary = caster.duplicate()
		bare["elem_dmg"] = {}
		var buffed := 0.0
		var plain := 0.0
		for i in 200:
			buffed += float(elem_core.compute_damage(caster, foe, 1.0, "magic").get("value", 0))
			plain += float(elem_core.compute_damage(bare, foe, 1.0, "magic").get("value", 0))
		var ratio := buffed / maxf(1.0, plain)
		_ok("火系伤害吃到元素加成", buffed > plain, "%.0f vs %.0f" % [buffed, plain])
		_ok("加成幅度约 +10%（4%~18%）", ratio > 1.04 and ratio < 1.18, "x%.3f" % ratio)

	# ---- 没有羁绊的编队不该凭空多出这些效果 ----
	var solo := RealmDB.apply_synergies(RealmDB.roster_of([{"slot": 5, "char_id": "arcane_girl"}]))
	var solo_core: RefCounted = _core_script.new()
	solo_core.setup(1001, solo, {"seed": SEED})
	var lone := _unit_by_id(solo_core, "arcane_girl")
	_eq("单人编队开局无能量", int(lone.get("energy", 0)), 0)
	_eq("单人编队开局无护盾", int(lone.get("shield", 0)), 0)


# ---------------------------------------------------------------- 战斗流程

## 推进到「养成后」的阵容：名单取默认展演队，等级顶到各品质的 level_cap。
## Boss 关那些长流程机制（满能量大招 / 眩晕）要求战斗撑够长，Boss 才能叠满怒气；
## 而展演态现在跟新号一样是 Lv.1 —— 拿 1 级队测这些只会测到「被秒杀」。
## RealmDB.roster_of 的属性来自 SaveDB.find_card，所以这里先把卡发到内存存档并拉高
## 等级/星级，算完 roster 再把存档卡片还原，不污染后面的用例（不写盘）。
func _progressed_team() -> Array:
	var backup: Array = SaveDB.profile.get("cards", []).duplicate(true)
	var entries: Array = []
	for cid in GameDB.menu().get("demo_team_slots", []):
		var cfg := GameDB.character(str(cid))
		if cfg.is_empty():
			continue
		var cap := maxi(1, int(GameDB.rarity(str(cfg.get("rarity", "R"))).get("level_cap", 20)))
		var card := SaveDB.grant_card(str(cid), false)
		card["level"] = cap
		card["star"] = clampi(int(cfg.get("demo_star", 1)) + 2, 1,
			maxi(1, int(GameDB.rarity(str(cfg.get("rarity", "R"))).get("star_max", 3))))
		entries.append({
			"slot": int(cfg.get("prefer_slot", 1)),
			"char_id": str(cid),
		})
	var roster := RealmDB.apply_synergies(RealmDB.roster_of(entries))
	SaveDB.profile["cards"] = backup
	return roster


func _check_battle_flow() -> void:
	print("\n· 战斗流程")

	# 引导关必赢
	var easy: RefCounted = _core_script.new()
	easy.setup(1001, _core_script.player_entries(), {"seed": SEED})
	_eq("1001 我方 3 人", easy.team_of("player").size(), 3)
	_eq("1001 敌方 2 只", easy.team_of("enemy").size(), 2)
	easy.run_all()
	_eq("1001 我方必胜", easy.winner, "player")
	_eq("1001 全歼结束", easy.end_reason, "wipe")
	_ok("战斗会结束", easy.finished)
	_ok("战报有内容", easy.log_lines.size() > 5, "%d 行" % easy.log_lines.size())

	# Boss 关：特性、大招、眩晕都在日志里出现（用养成后的队伍，理由见 _progressed_team）
	var hard: RefCounted = _core_script.new()
	hard.setup(1010, _progressed_team(), {"seed": SEED})
	_eq("1010 敌方 6 单位", hard.team_of("enemy").size(), 6)
	var evs: Array = hard.run_all()
	_ok("1010 会分出胜负", hard.winner in ["player", "enemy", "draw"], str(hard.winner))
	_ok("1010 战报提到花岗岩护甲", _has_line(hard, "花岗岩护甲"))
	_ok("1010 有单位放出大招", _has_line(hard, "释放【"))
	var stressed := false
	for raw in evs:
		if str((raw as Dictionary).get("t", "")) == "stun_apply":
			stressed = true
	_ok("裂地震击能打出眩晕", stressed)
	# 眩晕确实让单位少行动一次
	_ok("眩晕在战报里有记录", _has_line(hard, "被震晕") or _has_line(hard, "跳过行动"))

	# 治疗：带上萨满的关卡里，敌方出现过回血
	var heal: RefCounted = _core_script.new()
	heal.setup(1008, _core_script.player_entries(), {"seed": SEED})
	var healed := false
	for raw in heal.run_all():
		if str((raw as Dictionary).get("t", "")) == "heal" and int((raw as Dictionary).get("value", 0)) > 0:
			healed = true
	_ok("萨满给队友回血", healed)
	_ok("1008 战报提到先祖图腾", _has_line(heal, "先祖图腾"))

	# 环境效果：1004 的风属性单位攻速被放大
	var storm: RefCounted = _core_script.new()
	storm.setup(1004, _core_script.player_entries(), {"seed": SEED})
	var wind_spd := 0.0
	var base_spd := 0.0
	for u in storm.team_of("enemy"):
		if str(u.element) == "wind":
			wind_spd = maxf(wind_spd, float(u.spd))
		base_spd = maxf(base_spd, float(GameDB.monster(str(u.mob_id)).base.spd))
	_ok("风暴气场把风属性攻速放大 20%", is_equal_approx(wind_spd, base_spd * 1.2),
		"%.1f vs %.1f" % [wind_spd, base_spd * 1.2])
	_ok("1004 战报提到风暴气场", _has_line(storm, "风暴气场"))

	# 祭坛祝福：外部增伤必须真的进到伤害公式里
	# （不拿「总伤害」做断言 —— 伤害越高越早打完，累计输出未必更高，那样测的是节奏不是倍率）
	var buff_core: RefCounted = _core_script.new()
	buff_core.setup(1003, _core_script.player_entries(), {"seed": 777, "atk_bonus": 1.15})
	_ok("祭坛祝福被内核接住", is_equal_approx(float(buff_core.atk_bonus), 1.15),
		str(buff_core.atk_bonus))
	var dummy := {"element": "light", "def": 200.0, "mres": 200.0, "traits": [], "shield": 0}
	var attacker := {"element": "light", "atk": 400.0, "crit": 0.0, "crit_dmg": 1.5, "buff_atk": 0.0}
	var plain_core: RefCounted = _core_script.new()
	plain_core.setup(1003, _core_script.player_entries(), {"seed": 777})
	var plain_sum := 0.0
	var buff_sum := 0.0
	for _i in 400:
		plain_sum += float(plain_core.compute_damage(attacker, dummy, 1.0, "phys").value)
		buff_sum += float(buff_core.compute_damage(attacker, dummy, 1.0, "phys").value)
	_ok("祝福把伤害抬到约 115%", absf(buff_sum / maxf(1.0, plain_sum) - 1.15) < 0.04,
		"实测 %.3f" % (buff_sum / maxf(1.0, plain_sum)))

	# 超时裁定：把上限压到 1 拍，必须给出结果而不是卡死
	var timeout: RefCounted = _core_script.new()
	timeout.setup(1010, _core_script.player_entries(), {"seed": SEED})
	timeout.run_all(1)
	_ok("拍数上限触发超时裁定", timeout.finished, "%s / %s" % [timeout.winner, timeout.end_reason])
	_eq("超时结束原因", timeout.end_reason, "timeout")


func _has_line(core: RefCounted, key: String) -> bool:
	for l in core.log_lines:
		if str(l).contains(key):
			return true
	return false


# ---------------------------------------------------------------- 确定性

func _check_determinism() -> void:
	print("\n· 确定性（同一个种子必须跑出同一个过程）")
	var a: RefCounted = _core_script.new()
	a.setup(1009, _core_script.player_entries(), {"seed": 20260101})
	var ev_a: Array = a.run_all()
	var b: RefCounted = _core_script.new()
	b.setup(1009, _core_script.player_entries(), {"seed": 20260101})
	var ev_b: Array = b.run_all()
	_eq("同种子拍数一致", a.action_count, b.action_count)
	_eq("同种子胜负一致", a.winner, b.winner)
	_eq("同种子伤害序列一致", _damage_series(ev_a), _damage_series(ev_b))
	_eq("同种子战报一致", a.log_lines.size(), b.log_lines.size())

	var c: RefCounted = _core_script.new()
	c.setup(1009, _core_script.player_entries(), {"seed": 20260202})
	var ev_c: Array = c.run_all()
	_ok("换种子后过程不同", _damage_series(ev_a) != _damage_series(ev_c))

	# 关卡配置只读：跑几场不该改到 GameDB 的配置
	_eq("跑完战斗后配置未变", int(GameDB.chapter_stage(1009).get("recommend_power", 0)), 11200)


func _damage_series(evs: Array) -> Array:
	var out: Array = []
	for raw in evs:
		var e: Dictionary = raw
		if str(e.get("t", "")) == "damage":
			out.append([int(e.get("value", 0)), bool(e.get("crit", false))])
	return out


# ---------------------------------------------------------------- 场景

func _check_scene() -> void:
	print("\n· 战斗场景骨架（以 1010 Boss 关为样本）")
	# 关掉随机数：结算分支（胜/败）会影响后面的奖励断言，必须可复现
	BattleCtx.begin_from_stage(1010, "smoke")
	BattleCtx.seed_override = SEED

	var ps: PackedScene = load(SCENE_PATH)
	_ok("场景可加载", ps != null)
	if ps == null:
		return
	_scene = ps.instantiate()
	_ok("根节点为 Control", _scene is Control, _scene.get_class())
	_tree.root.add_child(_scene)

	var scr: Script = _scene.get_script()
	_ok("根节点已挂脚本", scr != null)
	if scr != null:
		_ok("挂的是 battle.gd", str(scr.resource_path).ends_with("battle.gd"), str(scr.resource_path))

	for u in ["StageNo", "StageName", "StageKind", "PowerMine", "PowerRec",
			"CellLayer", "UnitLayer", "PlateLayer", "FloatLayer",
			"TeamBox", "InfoTitle", "InfoBody", "LogBox", "TurnLabel", "AllyCount",
			"EnemyCount", "OrderLayer", "SpeedButton", "PauseButton", "SkipButton",
			"RetreatButton", "EnvLabel", "ResultPanel", "ResultTitle", "ResultSub",
			"ResultRewardBox", "ResultRetry", "ResultClose", "Toast", "ToastLabel", "FooterInfo"]:
		_ok("唯一名 %%%s 可解析" % u, _scene.get_node_or_null("%%%s" % u) != null)

	var core: RefCounted = _scene.get("core")
	_ok("场景已建立战斗内核", core != null)
	if core == null:
		return

	# 战场节点数 = 双方单位数；格子固定 18 个（两侧各 9 格，空格也要铺出来）
	var cells: Control = _scene.get_node_or_null("%CellLayer")
	_eq("格子数 = 两侧 × 9", cells.get_child_count(), 18)
	var units: Control = _scene.get_node_or_null("%UnitLayer")
	_eq("单位节点数 = 参战单位数", units.get_child_count(), core.units.size())
	var plates: Control = _scene.get_node_or_null("%PlateLayer")
	_eq("名牌独立成层且一单位一块", plates.get_child_count(), core.units.size())

	# 单位落位：立绘的脚下中心必须落在配置算出的锚点上
	var uid: int = int(core.units[0].uid)
	var token: Node = units.get_node_or_null("Unit_%d" % uid)
	_ok("单位节点按 uid 命名", token != null)
	if token != null:
		var anchor: Vector2 = core.unit_pos(core.units[0])
		var foot := (token as Control).position + Vector2((token as Control).size.x * 0.5,
			float((token as Control).size.y))
		_ok("立绘脚下对齐格子锚点", foot.distance_to(anchor) < 8.0,
			"foot=(%.0f,%.0f) anchor=(%.0f,%.0f)" % [foot.x, foot.y, anchor.x, anchor.y])

	# 名牌在头顶上方
	var plate: Control = plates.get_child(0)
	_ok("名牌挂在立绘上方", plate.position.y < core.unit_pos(core.units[0]).y,
		"plate.y=%.0f" % plate.position.y)

	# Boss 专属表现：必须比别人大、并且挂 BOSS 角标
	var boss: Dictionary = core.boss_unit()
	_ok("1010 场上有 Boss", not boss.is_empty())
	if not boss.is_empty():
		var boss_token: Node = units.get_node_or_null("Unit_%d" % int(boss.uid))
		var boss_plate: Node = plates.get_node_or_null("Plate_%d" % int(boss.uid))
		_ok("Boss 有独立立绘节点", boss_token != null)
		var normals: Array = []
		for u in core.team_of("enemy"):
			if int(u.uid) != int(boss.uid):
				normals.append(float(u.max_hp))
		var normal_h := float(GameDB.battle_cfg().token.monster_h)
		var boss_sprite: TextureRect = boss_token.get_node_or_null("Sprite")
		_ok("Boss 立绘比普通怪大", boss_sprite != null and boss_sprite.size.y > normal_h,
			"%.0f > %.0f" % [boss_sprite.size.y, normal_h])
		var badge := boss_token.get_node_or_null("BossBadge") != null
		_ok("Boss 挂了 BOSS 角标", badge)
		_ok("Boss 名牌独立存在", boss_plate != null)

	# HUD 文案
	var sid := int(_scene.get("stage_id"))
	var stage_cfg: Dictionary = GameDB.chapter_stage(sid)
	var no_lbl: Label = _scene.get_node_or_null("%StageNo")
	_eq("顶部关卡编号", no_lbl.text, str(int(stage_cfg.get("id", 0))))
	var nm: Label = _scene.get_node_or_null("%StageName")
	_eq("顶部关卡名称", nm.text, GameDB.stage_display_name(sid))
	_ok("顶部写出了关卡类型", (_scene.get_node_or_null("%StageKind") as Label).text.contains(
		GameDB.stage_kind_name(str(stage_cfg.get("kind", "")))))
	var mine: Label = _scene.get_node_or_null("%PowerMine")
	_ok("顶部写出我方战力", mine.text.contains("我方战力"), mine.text)
	var rec: Label = _scene.get_node_or_null("%PowerRec")
	_ok("顶部写出建议战力", rec.text.contains("建议战力"), rec.text)
	var turn: Label = _scene.get_node_or_null("%TurnLabel")
	_eq("回合从第 0 拍开始", turn.text, "第 0 拍")
	var enemy_cnt: Label = _scene.get_node_or_null("%EnemyCount")
	_eq("敌方人数取的是真实阵容", enemy_cnt.text, "敌方 6/6")

	var log_box: VBoxContainer = _scene.get_node_or_null("%LogBox")
	_ok("战报已铺出", log_box.get_child_count() > 0, "%d 行" % log_box.get_child_count())

	var order: HBoxContainer = _scene.get_node_or_null("%OrderLayer")
	_ok("行动顺序条有内容", order.get_child_count() > 0, "%d 个" % order.get_child_count())

	var info: Label = _scene.get_node_or_null("%InfoBody")
	_eq("默认显示关卡机制", info.text, _clip(GameDB.chapter_stage(int(_scene.get("stage_id"))).get("mechanic", ""), 108))


func _clip(text: String, limit: int) -> String:
	return text if text.length() <= limit else text.substr(0, limit - 1) + "…"


# ---------------------------------------------------------------- 交互

func _check_interact() -> void:
	print("\n· 交互与结算")
	if _scene == null or _scene.get("core") == null:
		_ok("场景可用", false)
		return
	var core: RefCounted = _scene.get("core")

	# 倍速循环
	var speed: Button = _scene.get_node_or_null("%SpeedButton")
	var i0 := int(_scene.get("_speed_index"))
	speed.pressed.emit()
	var i1 := int(_scene.get("_speed_index"))
	_ok("点速度会切到下一档", i1 != i0, "%d -> %d" % [i0, i1])
	_ok("速度文案跟着变", speed.text.contains(["1×", "2×", "3×"][i1]), speed.text)
	for _k in 2:
		speed.pressed.emit()
	_eq("倍速循环回到起点", int(_scene.get("_speed_index")), i0)

	# 暂停 / 继续
	var pause: Button = _scene.get_node_or_null("%PauseButton")
	pause.pressed.emit()
	_ok("暂停后按钮变「继续」", pause.text == "继续", pause.text)
	_ok("暂停标志已置位", bool(_scene.get("_paused")))
	pause.pressed.emit()
	_ok("继续后恢复「暂停」", pause.text == "暂停", pause.text)

	# 推进一拍：血量与血条必须同步变化
	var first: Dictionary = core.units[0]
	var hp_before := int(first.hp)
	for _k in 3:
		_scene.call("_do_action")
	_ok("推进若干拍后战斗状态前进了", core.action_count > 0, "拍数 %d" % core.action_count)
	var turn: Label = _scene.get_node_or_null("%TurnLabel")
	_ok("回合文案跟着推进", turn.text.contains(str(core.action_count)), turn.text)

	# 血条宽度与血量成正比
	var tokens: Dictionary = _scene.get("_tokens")
	_ok("单位演出表已建立", tokens.size() == core.units.size(), "%d" % tokens.size())
	var mismatch := 0
	for u in core.units:
		var t: Dictionary = tokens.get(int(u.uid), {})
		if t.is_empty():
			mismatch += 1
			continue
		var want := float(t.bar_w) * float(u.hp) / maxf(1.0, float(u.max_hp))
		if absf(float((t.hp_fill as Panel).size.x) - want) > 1.5:
			mismatch += 1
	_eq("血条宽度与血量一致", mismatch, 0)

	# 点击单位 -> 左侧面板切成单位详情
	var uid := int(core.units[0].uid)
	_scene.call("_on_unit_clicked", uid)
	var title: Label = _scene.get_node_or_null("%InfoTitle")
	_ok("点单位后标题变成单位名", title.text.contains(str(core.units[0].name)), title.text)
	var body: Label = _scene.get_node_or_null("%InfoBody")
	_ok("单位详情写出了属性", body.text.contains("攻击"), body.text.replace("\n", " / "))
	_scene.call("_on_bg_input", _left_click())
	_eq("点空白恢复关卡机制", title.text, "关卡机制")

	# 跳过：直接跑完
	_scene.call("_on_skip")
	_ok("跳过会直接结束战斗", core.finished, "%s / %s" % [core.winner, core.end_reason])

	# 结算入账：把结果面板打开，检查战利品与钱包
	var stage: Dictionary = _scene.get("stage")
	var gold_before := SaveDB.balance("gold")
	_scene.call("_show_result")
	var panel: Panel = _scene.get_node_or_null("%ResultPanel")
	_ok("结算面板弹出来了", panel != null and panel.visible)
	var rtitle: Label = _scene.get_node_or_null("%ResultTitle")
	_ok("结算标题是胜负之一", rtitle.text in ["战斗胜利", "战斗失败", "撤退"], rtitle.text)
	var box: VBoxContainer = _scene.get_node_or_null("%ResultRewardBox")
	_ok("结算面板有战利品行", box.get_child_count() > 0, "%d 行" % box.get_child_count())

	if str(core.winner) == "player":
		var gold_want := 0
		for raw in stage.get("rewards", []):
			var r: Dictionary = raw
			if str(r.get("id", "")) == "gold":
				gold_want = int(r.get("count", 0))
		if gold_want > 0:
			_eq("金币奖励已入账", SaveDB.balance("gold"), gold_before + gold_want)
		var clears: Dictionary = SaveDB.profile.get("progress", {}).get("stage_clears", {})
		_ok("通关次数已记录", clears.has(str(int(_scene.get("stage_id")))), str(clears))
	else:
		_ok("失败时金币不变", SaveDB.balance("gold") == gold_before)

	_check_first_clear()

	# 撤退
	var retreat: Button = _scene.get_node_or_null("%RetreatButton")
	_ok("撤退按钮存在且已接信号", retreat != null and retreat.pressed.get_connections().size() > 0)

	_check_settle_sync()


## 结算同步：星级评分 → progress.stage_stars（只升不降），材料 → 材料仓 + 累计统计。
## 这条链是「战斗结果 → 选关地图星星」的唯一通路，断了的话地图上永远是无星。
func _check_settle_sync() -> void:
	print("\n· 结算同步：星级评分与材料统计")
	if _scene == null or _scene.get("core") == null:
		_ok("结算同步样本可用", false)
		return
	var core: RefCounted = _scene.get("core")
	var sid := int(_scene.get("stage_id"))
	var grade: Dictionary = _scene.get("_grade")

	if str(core.winner) != "player":
		_ok("非胜利不评星", grade.is_empty(), str(grade))
		return

	_ok("胜利后给出星级评定", not grade.is_empty(), str(grade))
	var stars := int(grade.get("stars", 0))
	var max_stars := GameDB.star_max()
	_ok("星级落在 1..满星", stars >= 1 and stars <= max_stars,
		"%d★ / %d★" % [stars, max_stars])
	_eq("星级写入了存档 stage_stars", SaveDB.stage_stars(sid), stars)

	# 只升不降：打得更差不能把地图上的星星擦掉
	_ok("更低星不会覆盖记录", not SaveDB.record_stage_stars(sid, maxi(1, stars - 1)))
	_eq("更低星之后记录不变", SaveDB.stage_stars(sid), stars)

	var box: VBoxContainer = _scene.get_node_or_null("%ResultRewardBox")
	_ok("结算面板有星级行", box != null and box.get_node_or_null("StarRatingRow") != null)
	_ok("累计星级已统计", SaveDB.stat("stars_total") >= stars,
		"累计 ★%d" % SaveDB.stat("stars_total"))
	_ok("战斗场次已统计", SaveDB.stat("battles") >= 1, "%d 场" % SaveDB.stat("battles"))

	# 材料：再发一次奖，材料仓增量必须恰好等于本次发放的非货币件数
	var before: Dictionary = SaveDB.material_tally()
	SaveDB.profile["progress"]["stage_clears"] = {}
	_scene.set("_result_open", false)
	var granted: Array = _scene.call("_grant_rewards")
	var after: Dictionary = SaveDB.material_tally()
	var gained := 0
	var owned_ok := true
	for raw in granted:
		var r: Dictionary = raw
		var rid := str(r.get("id", ""))
		if GameDB.currency(rid).is_empty():
			gained += int(r.get("count", 0))
			if int(r.get("owned", -1)) != SaveDB.material_count(rid):
				owned_ok = false
		elif int(r.get("owned", -1)) != SaveDB.balance(rid):
			owned_ok = false
	_ok("本关配置里有材料奖励", gained > 0, "本关材料件数 %d" % gained)
	_eq("材料件数按发放量累加到材料仓",
		int(after.get("total", 0)) - int(before.get("total", 0)), gained)
	_ok("每行奖励都带回入账后的持有量", owned_ok)
	_ok("材料仓报出了种类数", int(after.get("kinds", 0)) > 0, str(after))


## 首通专属奖励（SSR 英雄）只发一次：这里直接把「已通关」的存档状态造出来，
## 再跑一次发放逻辑，验证第二次不会再落账。
func _check_first_clear() -> void:
	var stage: Dictionary = _scene.get("stage")
	var first_id := ""
	for raw in stage.get("rewards", []):
		if bool((raw as Dictionary).get("first_clear", false)):
			first_id = str((raw as Dictionary).get("id", ""))
	if first_id == "":
		_ok("1010 有首通专属奖励", false, "配置里没找到 first_clear 奖励")
		return
	_ok("1010 有首通专属奖励", true, first_id)

	_scene.set("_result_open", false)
	SaveDB.profile["progress"]["stage_clears"] = {str(int(_scene.get("stage_id"))): 1}
	var pending_before: Dictionary = \
		(SaveDB.profile["progress"].get("pending_items", {}) as Dictionary).duplicate()
	var granted: Array = _scene.call("_grant_rewards")
	var skipped := true
	for raw in granted:
		if str((raw as Dictionary).get("id", "")) == first_id:
			skipped = false
	var pending_after: Dictionary = SaveDB.profile["progress"].get("pending_items", {})
	_ok("重复通关不再发首通奖励", skipped)
	# 只比首通那一件：普通奖励本来就该重复发，比整个背包会把「正常发放」误判成 bug
	_eq("首通奖励不重复落账",
		int(pending_after.get(first_id, 0)), int(pending_before.get(first_id, 0)))

	# 反过来：当作从没通关过，必须发得出来
	SaveDB.profile["progress"]["stage_clears"] = {}
	var pending2: Dictionary = \
		(SaveDB.profile["progress"].get("pending_items", {}) as Dictionary).duplicate()
	var again: Array = _scene.call("_grant_rewards")
	var got := false
	for raw in again:
		if str((raw as Dictionary).get("id", "")) == first_id:
			got = true
	var pending3: Dictionary = SaveDB.profile["progress"].get("pending_items", {})
	_ok("首次通关会发首通奖励", got)
	_ok("首通奖励确实落了账", int(pending3.get(first_id, 0)) > int(pending2.get(first_id, 0)),
		"%s: %d -> %d" % [first_id, int(pending2.get(first_id, 0)), int(pending3.get(first_id, 0))])


func _left_click() -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	return e
