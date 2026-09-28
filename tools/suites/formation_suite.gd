extends RefCounted
## formation_suite.gd —— 卡牌选择与编队页冒烟测试
##
## 由 tools/smoke_formation.gd 在第一帧之后动态 load()。
##
## 覆盖：
##   数据层 —— 上阵上限 / 编队规范化（同名、越界槽位、超员截断）、
##             羁绊规则求值与战力口径（总战力 = 基础 + 羁绊）、属性与职业克制报告；
##   界面   —— 场景骨架与唯一名、脚本是否真的挂上（解析失败会静默退回静态骨架）、
##             卡牌陈列的默认选中与切换、3x3 棋盘按 slot_to_cell 落位、
##             卡库缩略图与「已上阵」标记、筛选 / 排序 / 搜索、
##             上阵 / 下阵 / 一键上阵 / 三种阵容预设切换，
##             以及「确认选择 → 扣体力 → 写档 → 交接给战斗」的闭环。

var passed := 0
var failed := 0

## 与 scripts/formation.gd 的常量对应（棋盘格是运行时 new 出来的，只能按同值断言）
const BOARD_CELL := 76.0
const BOARD_GAP := 10.0
const BOARD_GUTTER := 52.0
const MAX_MEMBERS := 5

var _tree: SceneTree
var _scene: Node

## 用例会真的写 user://save.json（编队 / 预设 / 体力），先留底，结尾还原
const SAVE_PATH := "user://save.json"
var _save_backup := ""
var _had_save := false

const SEED_TEAM := ["knight_rock", "pyro_girl", "elf_ranger"]

## 全部英雄：从配置实时取（加卡不用改测试），run() 里填充
var ALL_HEROES: Array = []


func run(tree: SceneTree) -> Dictionary:
	_tree = tree
	print("\n========== 卡牌大冒险 · 卡牌选择与编队页冒烟 ==========")

	# 让测试可重复：回到默认存档与满体力，避免上一次运行的残留污染断言
	_backup_save()
	SaveDB.reset_profile()
	StaminaSys.fill()
	BattleCtx.reset()

	ALL_HEROES = GameDB.characters().map(func(c: Dictionary) -> String: return str(c.get("id", "")))
	print("· 英雄总数 %d：%s" % [ALL_HEROES.size(), ALL_HEROES])

	# 编队卡池只收已持有的卡：默认档不发卡（0 张），
	# 后面的陈列 / 筛选 / 排序用例要覆盖全部英雄，先把全卡发放齐
	_eq("新号默认持卡 = 0", SaveDB.cards().size(), 0)
	for hid in ALL_HEROES:
		SaveDB.grant_card(hid, false)
	SaveDB.save_profile()

	_check_config()
	_check_team_normalize()
	_check_synergy()
	_check_gdd_synergy()
	_check_counters()
	_check_skeleton()
	_check_fan()
	_check_board_layout()
	_check_library()
	_check_filter_sort_search()
	_check_team_ops()
	_check_quick_fill()
	_check_presets()
	_check_confirm()

	print("\n---------- 结果：通过 %d / 失败 %d ----------" % [passed, failed])
	_restore_save()
	return {"passed": passed, "failed": failed}


# ---------------------------------------------------------------- 存档留底

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


# ---------------------------------------------------------------- 断言

func _ok(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  [PASS] %s%s" % [label, ("  " + detail) if detail != "" else ""])
	else:
		failed += 1
		print("  [FAIL] %s%s" % [label, ("  " + detail) if detail != "" else ""])


func _eq(label: String, got, want) -> void:
	_ok(label, got == want, "got=%s want=%s" % [str(got), str(want)])


# ---------------------------------------------------------------- 配置口径

func _check_config() -> void:
	print("\n· 编队配置口径")
	var f := GameDB.formation()
	_ok("formation 段存在", not f.is_empty())
	_eq("上阵上限取自配置", GameDB.team_max(), MAX_MEMBERS)
	_eq("棋盘槽位 9 格", GameDB.status_max(), 9)
	_eq("扣体力的位置", GameDB.spend_stamina_at(), "formation")
	_eq("阵容预设 3 栏", GameDB.presets().size(), 3)
	_ok("职业克制链非空", GameDB.role_chain().size() >= 3, str(GameDB.role_chain()))
	_ok("羁绊规则表非空", GameDB.synergies().size() >= 4, "%d 条" % GameDB.synergies().size())
	_ok("职业克制表非空", GameDB.role_counters().size() >= 3)
	_ok("战斗定位文案取自配置",
		GameDB.battle_role_text("mage") == "中排魔法输出 / 范围破盾",
		GameDB.battle_role_text("mage"))
	_ok("确认按钮文案取自配置",
		str(GameDB.formation_section("confirm_button").get("text", "")) == "确认选择")
	_ok("编队页场景路径指向 formation.tscn",
		GameDB.formation_scene().ends_with("formation.tscn"), GameDB.formation_scene())
	_ok("编队页的下一站（战斗场景）存在",
		ResourceLoader.exists(str(f.get("battle_scene", ""))), str(f.get("battle_scene", "")))
	_ok("返回主界面的目标场景存在",
		ResourceLoader.exists(str(GameDB.formation_section("back_button").get("route", ""))))

	# 关卡敌方构成：编队页的克制提示与一键上阵都读这一份
	var e3 := GameDB.stage_enemy_units(1003)
	_eq("1003 有 3 个敌方单位", e3.size(), 3)
	var comp := GameDB.stage_enemy_comp(1003)
	_eq("1003 敌方正排人数 = 1（城堡重装卫兵）", int(comp["roles"].get("tank", 0)), 1)
	_eq("1003 敌方元素种类 = 2（光 / 地）", (comp["elements"] as Dictionary).size(), 2)


# ---------------------------------------------------------------- 编队规范化

func _check_team_normalize() -> void:
	print("\n· 编队规范化（上限 / 同名 / 槽位）")
	var seed := SaveDB.preset_entries("main")
	_eq("主线队初始 3 人", seed.size(), 3)
	_eq("主线队初始按槽位升序", [int(seed[0].slot), int(seed[1].slot), int(seed[2].slot)], [1, 5, 6])

	# 同名 hero_id 不可重复上阵
	var dup := [
		{"slot": 1, "char_id": "pyro_girl"},
		{"slot": 5, "char_id": "pyro_girl"},
	]
	_eq("同名单卡只留一份", SaveDB.normalize_team(dup).size(), 1)

	# 槽位必须落在 1..9
	var bad_slot := [
		{"slot": 0, "char_id": "pyro_girl"},
		{"slot": 12, "char_id": "elf_ranger"},
		{"slot": 3, "char_id": "knight_rock"},
	]
	var fixed := SaveDB.normalize_team(bad_slot)
	_eq("越界槽位被丢掉", fixed.size(), 1)
	_eq("留下的是合法槽位", int(fixed[0].slot), 3)

	# 同一槽位不能被两个人占
	var same_slot := [
		{"slot": 4, "char_id": "pyro_girl"},
		{"slot": 4, "char_id": "elf_ranger"},
	]
	_eq("同槽位只留一人", SaveDB.normalize_team(same_slot).size(), 1)

	# 未知英雄直接丢
	_eq("未知 hero_id 被丢弃",
		SaveDB.normalize_team([{"slot": 1, "char_id": "not_a_hero"}]).size(), 0)

	# 超员按上限截断（用 9 个槽位塞 4 个英雄 + 复用的占位 id 验上限）
	var many: Array = []
	for i in range(1, 10):
		many.append({"slot": i, "char_id": ALL_HEROES[i % ALL_HEROES.size()]})
	_ok("超员编队被截到上限",
		SaveDB.normalize_team(many).size() <= MAX_MEMBERS,
		"%d 人" % SaveDB.normalize_team(many).size())

	# 错误说明（toast 文案用）
	_ok("越界槽位能报出人类可读的错误",
		SaveDB.team_errors([{"slot": 12, "char_id": "pyro_girl"}]).size() > 0)


# ---------------------------------------------------------------- 羁绊

func _check_synergy() -> void:
	print("\n· 羁绊规则与战力口径")
	var report := RealmDB.formation_report(_entries(SEED_TEAM))
	_eq("上阵 3 人", int(report["count"]), 3)
	_ok("基础战力 > 0", int(report["base_power"]) > 0, str(report["base_power"]))
	_eq("队伍战力 = 基础 + 羁绊",
		int(report["total_power"]), int(report["base_power"]) + int(report["synergy_power"]))
	_ok("3 人阵容有羁绊加成", int(report["synergy_power"]) > 0, str(report["synergy_power"]))
	_ok("三才阵（上阵满 3 人）生效", _has_synergy(report["synergies"], "trinity"))
	_ok("坚守阵线（队内有前排）生效", _has_synergy(report["synergies"], "vanguard"))

	# 单人也算得出战力，且不吃「满 3 人」这类人数羁绊
	var one := RealmDB.formation_report(_entries(["pyro_girl"]))
	_ok("单人不成三才阵", not _has_synergy(one["synergies"], "trinity"))
	_eq("单人战力 = 基础（无羁绊增量）",
		int(one["total_power"]), int(one["base_power"]))

	# 空编队不能崩
	var empty := RealmDB.formation_report([])
	_eq("空编队战力为 0", int(empty["total_power"]), 0)
	_ok("空编队给出激活提示", str(empty.get("hint", "")) != "", str(empty.get("hint", "")))

	# 羁绊增幅真的落到属性上：全属性 +5% 的「三才阵」必须让 def 变大
	var plain := RealmDB.roster_of(_entries(["knight_rock", "pyro_girl", "elf_ranger"]))
	var boosted := RealmDB.apply_synergies(RealmDB.roster_of(
		_entries(["knight_rock", "pyro_girl", "elf_ranger"])))
	var a := float(plain[0]["stats"]["def"])
	var b := float(boosted[0]["stats"]["def"])
	_ok("羁绊把防御抬高了", b > a, "%.0f -> %.0f" % [a, b])

	# 与战斗侧同一口径：roster() 也走这套羁绊结算
	_ok("roster_of 与 battle_power 口径一致",
		RealmDB.battle_power(RealmDB.roster_of(_entries(["pyro_girl"]))[0]["stats"])
			== int(RealmDB.formation_report(_entries(["pyro_girl"]))["base_power"]))


# ---------------------------------------------------------------- GDD 羁绊

## 四条 GDD 羁绊各有不同机制：指定英雄组合 / 前排定向 / 暴击加算 / 战斗级开局效果。
## 这一段把每条机制的「配置能表达、求值能算对、战斗能拿到」都钉住。
func _check_gdd_synergy() -> void:
	print("\n· GDD 羁绊（指定英雄 / 定向 / 战斗级效果）")

	# ---- 云端先锋队：炎赫骑士 + 秘法少女 → 攻击 +8%，火元素伤害 +10% ----
	var cv_ids := ["flame_knight", "arcane_girl"]
	var cv_plain := RealmDB.roster_of(_entries(cv_ids))
	var cv := RealmDB.apply_synergies(RealmDB.roster_of(_entries(cv_ids)))
	_ok("云端先锋队（指定两名英雄）生效",
		_has_synergy(RealmDB.active_synergies(cv_plain), "cloud_vanguard"))
	_ok("全队攻击 +8% 落到实处",
		_stat_of(cv, "arcane_girl", "atk") > _stat_of(cv_plain, "arcane_girl", "atk"),
		"%.0f -> %.0f" % [_stat_of(cv_plain, "arcane_girl", "atk"),
			_stat_of(cv, "arcane_girl", "atk")])
	var fire_buff: float = float(_elem_dmg_of(cv, "arcane_girl").get("fire", 0.0))
	_ok("火元素伤害 +10% 写进战斗 buff", absf(fire_buff - 0.10) < 0.001, str(fire_buff))
	_ok("只上阵其中一人不激活",
		not _has_synergy(RealmDB.active_synergies(
			RealmDB.roster_of(_entries(["flame_knight", "pyro_girl"]))), "cloud_vanguard"))

	# ---- 自然之护：精灵游侠(中排) + 大地守卫(前排) → 只有前排吃生命 / 防御 ----
	var ng_ids := ["elf_ranger", "earth_guardian"]
	var ng_plain := RealmDB.roster_of(_entries(ng_ids))
	var ng := RealmDB.apply_synergies(RealmDB.roster_of(_entries(ng_ids)))
	_ok("自然之护生效", _has_synergy(RealmDB.active_synergies(ng_plain), "nature_guard"))
	_ok("前排英雄生命上限 +12%",
		_stat_of(ng, "earth_guardian", "hp") > _stat_of(ng_plain, "earth_guardian", "hp"),
		"%.0f -> %.0f" % [_stat_of(ng_plain, "earth_guardian", "hp"),
			_stat_of(ng, "earth_guardian", "hp")])
	_eq("中排英雄不吃前排专属加成",
		int(_stat_of(ng, "elf_ranger", "hp")), int(_stat_of(ng_plain, "elf_ranger", "hp")))
	_eq("大地守卫确实落在前排",
		GameDB.row_of_slot(int(GameDB.character("earth_guardian").get("prefer_slot", 1))), "front")

	# ---- 光暗交织：暴击 +5%（加算）+ 开局 15 能量 ----
	var ld_ids := ["holy_priest", "shadow_assassin"]
	var ld_plain := RealmDB.roster_of(_entries(ld_ids))
	var ld := RealmDB.apply_synergies(RealmDB.roster_of(_entries(ld_ids)))
	_ok("光暗交织生效", _has_synergy(RealmDB.active_synergies(ld_plain), "light_dark_weave"))
	var crit_gain := _stat_of(ld, "shadow_assassin", "crit") \
		- _stat_of(ld_plain, "shadow_assassin", "crit")
	_ok("全队暴击率 +5%（加算）", absf(crit_gain - 0.05) < 0.0001, "%.4f" % crit_gain)
	_ok("开局能量 15 点写进战斗 buff",
		absf(float(_buffs_of(ld, "shadow_assassin").get("open_energy", 0.0)) - 15.0) < 0.001,
		str(_buffs_of(ld, "shadow_assassin")))

	# ---- 全元素共鸣：队内 4 种元素 → 全员开局护盾 15% 最大生命 ----
	var four := ["knight_rock", "pyro_girl", "elf_ranger", "holy_priest"]  # 地 / 火 / 风 / 光
	var rp := RealmDB.formation_report(_entries(four))
	_ok("全元素共鸣（4 种元素）生效", _has_synergy(rp["synergies"], "all_element_resonance"))
	var units := RealmDB.apply_synergies(RealmDB.roster_of(_entries(four)))
	var shielded := 0
	for raw in units:
		var u: Dictionary = raw
		if absf(float(_buffs_of(units, str(u["char_id"])).get("open_shield", 0.0)) - 0.15) < 0.001:
			shielded += 1
	_eq("全员都拿到 15% 开局护盾", shielded, four.size())
	_ok("三元素阵容不触发（与五行流转区分）",
		not _has_synergy(RealmDB.formation_report(
			_entries(["pyro_girl", "elf_ranger", "holy_priest"]))["synergies"], "all_element_resonance"))

	# ---- schema：effect 单条写法与 effects 数组写法等价 ----
	var old_rule := {"cond": {"type": "member_count", "min": 1}, "effect": {"stat": "atk", "pct": 0.08}}
	_eq("单条 effect 仍被识别", RealmDB.synergy_effects(old_rule).size(), 1)
	var new_rule := {"cond": {"type": "member_count", "min": 1},
		"effects": [{"stat": "atk", "pct": 0.08}, {"stat": "crit", "value": 0.05}]}
	_eq("effects 数组逐条展开", RealmDB.synergy_effects(new_rule).size(), 2)
	_eq("属性类效果走乘算", str(RealmDB.synergy_effects(new_rule)[0]["mode"]), "mul")
	_eq("暴击走加算", str(RealmDB.synergy_effects(new_rule)[1]["mode"]), "add")


# ---------------------------------------------------------------- 克制

func _check_counters() -> void:
	print("\n· 属性 / 职业克制提示")
	var pyro := _unit("pyro_girl")

	# 1003 有「城堡重装卫兵（重装）」→ 法师对重装应有职业克制提示
	var vs_armor := RealmDB.counter_report(pyro, GameDB.stage_enemy_units(1003))
	_ok("法师对重装给出克制提示", int(vs_armor["hits"]) > 0, "hits=%d" % int(vs_armor["hits"]))
	_ok("克制幅度为 25%", int(vs_armor["pct"]) == 25, str(vs_armor["pct"]))
	var joined := "\n".join(vs_armor["lines"])
	_ok("提示文案写出「魔法对重装 +25% 伤害」", joined.contains("魔法对重装"), joined)

	# 1004 全是风属性 → 火克风，属属性克制（±25%）
	var vs_wind := RealmDB.counter_report(pyro, GameDB.stage_enemy_units(1004))
	var joined2 := "\n".join(vs_wind["lines"])
	_ok("火对风给出属性克制提示", joined2.contains("火") and joined2.contains("风"), joined2)
	_eq("属性克制命中 3 个目标", int(vs_wind["hits"]), 3)

	# 没有敌方信息时不能瞎报
	var none := RealmDB.counter_report(pyro, [])
	_eq("无敌人时无克制文案", none["lines"].size(), 0)


# ---------------------------------------------------------------- 骨架

func _check_skeleton() -> void:
	print("\n· 场景骨架")
	var ps: PackedScene = load("res://scenes/formation.tscn")
	_ok("场景可加载", ps != null)
	if ps == null:
		return

	_scene = ps.instantiate()
	_ok("场景根节点为 Control", _scene is Control, str(_scene.get_class()))
	_tree.root.add_child(_scene)

	# 陷阱：UI 脚本解析失败时，场景会静默退回静态骨架（动态节点为 0、图标全无），
	# 控制台只有一行 Parse Error。先确认脚本真的挂上了。
	var scr: Script = _scene.get_script()
	_ok("根节点已挂脚本", scr != null)
	if scr != null:
		_ok("挂的是 formation.gd", str(scr.resource_path).ends_with("formation.gd"),
			str(scr.resource_path))

	for u in ["BackButton", "TopBar", "SearchEdit", "TitleLabel", "SubTitle", "CardStage",
			"PowerValue", "BoardPanel", "BoardGrid", "BoardCount",
			"LibraryPanel", "LibraryScroll", "LibraryGrid", "LibraryCount",
			"TacticalPanel", "CommandPanel", "PresetBar", "QuickFillButton",
			"ClearButton", "DeployButton", "RemoveButton", "ConfirmButton", "ConfirmSub",
			"SaveButton",
			"Toast", "ToastLabel", "FilterPanel", "FilterGroups", "SortPanel", "SortOptions"]:
		_ok("唯一名 %%%s 可解析" % u, _scene.get_node_or_null("%%%s" % u) != null)

	# 背景与选关页同一张底图（编队页就是从选关页走下来的）
	var bg: TextureRect = _scene.get_node_or_null("Background")
	_ok("背景底图已加载", bg != null and bg.texture != null)
	if bg != null and bg.texture != null:
		_ok("用的是选关页专用底图",
			str(bg.texture.resource_path).ends_with("bg_stage_select.png"),
			str(bg.texture.resource_path))


# ---------------------------------------------------------------- 卡牌陈列

func _check_fan() -> void:
	print("\n· 中央卡牌陈列")
	var fan: CardFan = _scene.get_node_or_null("%CardStage")
	_ok("CardStage 是 CardFan", fan != null)
	if fan == null:
		return
	_eq("陈列英雄数 = 配置英雄数", fan.cards.size(), GameDB.characters().size())

	# 默认选中由配置指定（概念稿里高亮的是 SSR）
	_eq("默认选中取自配置", str(_scene.get("_selected_id")),
		str(GameDB.formation().get("default_selected", "")))

	var picked: CardView = fan.find_card(str(_scene.get("_selected_id")))
	_ok("选中卡存在", picked != null)
	if picked != null:
		_ok("选中卡带金色高亮边框", _ring_visible(picked))
		_ok("选中卡被放大", float(picked.get("_select_mult")) > 1.0,
			"mult=%.2f" % float(picked.get("_select_mult")))
	for cv in fan.cards:
		if cv.char_id != str(_scene.get("_selected_id")):
			_ok("未选中卡 %s 无高亮边框" % str(cv.char_id), not _ring_visible(cv))

	# 点另一张卡 → 高亮整块切过去
	fan.card_pressed.emit("knight_rock")
	_eq("点击后选中切换", str(_scene.get("_selected_id")), "knight_rock")
	_ok("新选中卡高亮", _ring_visible(fan.find_card("knight_rock")))
	_ok("旧选中卡高亮撤掉", not _ring_visible(fan.find_card("pyro_girl")))

	# 战斗定位面板要跟着选中卡换
	var body: Control = _tactic_body("battle_role")
	_ok("战斗定位已刷新", body != null and body.get_child_count() > 0)
	if body != null:
		var head := body.get_child(0) as Label
		_ok("战斗定位写出重装的定位",
			head != null and head.text.contains("前排"), head.text if head != null else "")


# ---------------------------------------------------------------- 棋盘落位

func _check_board_layout() -> void:
	print("\n· 3x3 编队棋盘")
	var grid: Control = _scene.get_node_or_null("%BoardGrid")
	_ok("BoardGrid 存在", grid != null)
	if grid == null:
		return

	# 3 个行标签 + 9 个格子
	_eq("行标签 3 个 + 格子 9 个", grid.get_child_count(), 3 + 9)

	for slot in range(1, 10):
		var cell := _find("BoardCell_%d" % slot)
		_ok("槽位 %d 的格子已实例化" % slot, cell != null)
		if cell == null:
			continue
		# 格子位置直接由配置的 slot_to_cell 反推 —— UI 不做第二套坐标
		var at := GameDB.slot_cell("player", slot)
		var want := Vector2(
			BOARD_GUTTER + float(at.x) * (BOARD_CELL + BOARD_GAP),
			float(at.y - 3) * (BOARD_CELL + BOARD_GAP))
		_ok("槽位 %d 落位与 slot_to_cell 一致" % slot,
			(cell as Control).position.distance_to(want) < 0.5,
			"got=(%.0f,%.0f) want=(%.0f,%.0f)" % [
				(cell as Control).position.x, (cell as Control).position.y, want.x, want.y])

	# 前排在上：slot 1 属于前排（row 3），必须比 slot 7（后排）更靠上
	var c1 := _find("BoardCell_1") as Control
	var c7 := _find("BoardCell_7") as Control
	_ok("前排格子在后排上方", c1.position.y < c7.position.y,
		"slot1.y=%.0f slot7.y=%.0f" % [c1.position.y, c7.position.y])

	# 棋盘实时反映编队：主线队 3 人应各自出现在自己的槽位
	for raw in SaveDB.preset_entries("main"):
		var slot := int(raw.get("slot", 0))
		var char_id := str(raw.get("char_id", ""))
		var cell := _find("BoardCell_%d" % slot)
		_ok("槽位 %d 上是 %s" % [slot, char_id], _cell_owner_name(cell) == _hero_name(char_id),
			_cell_owner_name(cell))

	_ok("上阵计数写在面板上",
		str(_scene.get_node("%BoardCount").text).contains("3"),
		str(_scene.get_node("%BoardCount").text))


# ---------------------------------------------------------------- 卡库

func _check_library() -> void:
	print("\n· 备选英雄库")
	var grid: GridContainer = _scene.get_node_or_null("%LibraryGrid")
	_ok("LibraryGrid 存在", grid != null)
	if grid == null:
		return

	# 期望值从配置推导：英雄多于栅格时按英雄数铺满，少于栅格时用「空位」补齐
	var lib: Dictionary = GameDB.formation_section("library")
	var cols := int(lib.get("columns", 2))
	var rows := int(lib.get("rows", 3))
	_eq("缩略图 + 空位补齐到整屏栅格", grid.get_child_count(),
		maxi(ALL_HEROES.size(), cols * rows))

	for char_id in ALL_HEROES:
		var thumb := _find("Hero_%s" % char_id)
		_ok("英雄 %s 有缩略图" % char_id, thumb != null)
		if thumb == null:
			continue
		_ok("缩略图带英雄名", _first_label_text(thumb).contains(_hero_name(char_id)),
			_first_label_text(thumb))

	# 已上阵的英雄要有标记
	for char_id in SEED_TEAM:
		_ok("%s 标了「已上阵」" % char_id, _thumb_deployed_text(_find("Hero_%s" % char_id)) != "",
			_thumb_deployed_text(_find("Hero_%s" % char_id)))
	_ok("未上阵的英雄没有「已上阵」标记",
		_thumb_deployed_text(_find("Hero_holy_priest")) == "",
		_thumb_deployed_text(_find("Hero_holy_priest")))

	_ok("卡库计数文案取自配置",
		str(_scene.get_node("%LibraryCount").text).ends_with("名"),
		str(_scene.get_node("%LibraryCount").text))

	# 点缩略图 = 选中（不是直接上阵）
	(_find("Hero_holy_priest") as Button).pressed.emit()
	_eq("点卡库缩略图会选中该英雄", str(_scene.get("_selected_id")), "holy_priest")
	_ok("选中后缩略图高亮",
		_thumb_border_is_gold(_find("Hero_holy_priest")))


# ---------------------------------------------------------------- 筛选 / 排序 / 搜索

func _check_filter_sort_search() -> void:
	print("\n· 筛选 / 排序 / 搜索")
	var fan: CardFan = _scene.get_node_or_null("%CardStage")

	# ---- 元素筛选：只看火 ----
	var chip := _find("Chip_element_fire") as Button
	_ok("元素筛选芯片存在", chip != null)
	if chip != null:
		var fire_ids := _ids_where("element", "fire")
		chip.pressed.emit()
		_eq("按火元素筛选后只剩火系英雄", fan.cards.size(), fire_ids.size())
		_ok("筛选结果全是火系", _cards_all_in(fan, fire_ids), _cards_ids(fan))
		_ok("火系英雄里有紫焰少女", str(fan.cards[0].char_id) in fire_ids, _cards_ids(fan))
		_ok("筛选是实时生效的（面板不用点确定）", _view_size() == fire_ids.size(), str(_view_size()))
		chip.pressed.emit()
		_eq("再点一次取消勾选", fan.cards.size(), ALL_HEROES.size())

	# ---- 职业筛选 ----
	var role_chip := _find("Chip_role_healer") as Button
	if role_chip != null:
		role_chip.pressed.emit()
		_eq("按牧师筛选后只剩 1 张", fan.cards.size(), 1)
		_eq("剩下的是神圣牧师", str(fan.cards[0].char_id), "holy_priest")
		(_find("FilterResetButton") as Button).pressed.emit()
		_eq("重置后恢复全部", fan.cards.size(), ALL_HEROES.size())

	# ---- 排序：战力降序 ----
	var sort_btn := _find("Sort_power") as Button
	_ok("排序选项存在", sort_btn != null)
	if sort_btn != null:
		sort_btn.pressed.emit()
		_eq("排序态被记住", str(_scene.get("_sort_id")), "power")
		var want := _power_sorted_ids()
		var got: Array = []
		for cv in fan.cards:
			got.append(str(cv.char_id))
		_eq("陈列按战力降序重排", got, want)

	# ---- 排序：名称 ----
	var name_btn := _find("Sort_name") as Button
	if name_btn != null:
		name_btn.pressed.emit()
		var want2: Array = ALL_HEROES.duplicate()
		want2.sort_custom(func(a, b): return _hero_name(str(a)) < _hero_name(str(b)))
		var got2: Array = []
		for cv in fan.cards:
			got2.append(str(cv.char_id))
		_eq("陈列按名称重排", got2, want2)
		(_find("Sort_default") as Button).pressed.emit()

	# ---- 搜索 ----
	var edit: LineEdit = _scene.get_node_or_null("%SearchEdit")
	_ok("搜索框存在", edit != null)
	if edit != null:
		edit.text = "牧"
		edit.text_changed.emit("牧")
		_eq("搜「牧」只剩神圣牧师", fan.cards.size(), 1)
		_eq("命中的是 holy_priest", str(fan.cards[0].char_id), "holy_priest")
		# 品质关键字也要能搜到
		edit.text = "ssr"
		edit.text_changed.emit("ssr")
		var ssr_ids := _ids_where("rarity", "SSR")
		_eq("搜「ssr」只剩 SSR 卡", fan.cards.size(), ssr_ids.size())
		_ok("命中的都是 SSR", _cards_all_in(fan, ssr_ids), _cards_ids(fan))
		# 无结果时卡库给出空态提示
		edit.text = "zzz"
		edit.text_changed.emit("zzz")
		_eq("无结果时陈列清空", fan.cards.size(), 0)
		_ok("无结果时卡库给出空态文案",
			_library_has_text(str(GameDB.formation_section("library").get("empty_result", ""))),
			str(GameDB.formation_section("library").get("empty_result", "")))
		edit.text = ""
		edit.text_changed.emit("")
		_eq("清空搜索后恢复全部", fan.cards.size(), ALL_HEROES.size())

	# ---- 顶部标签页只做弹层开合 ----
	(_find("Tab_filter") as Button).pressed.emit()
	_ok("点「筛选」打开筛选弹层", (_scene.get_node("%FilterPanel") as Control).visible)
	(_find("Tab_sort") as Button).pressed.emit()
	_ok("点「排序」打开排序弹层", (_scene.get_node("%SortPanel") as Control).visible)
	_ok("两个弹层不会同时开", not (_scene.get_node("%FilterPanel") as Control).visible)
	(_find("Tab_select") as Button).pressed.emit()
	_ok("点「选择」收起全部弹层",
		not (_scene.get_node("%FilterPanel") as Control).visible
		and not (_scene.get_node("%SortPanel") as Control).visible)


# ---------------------------------------------------------------- 上阵 / 下阵

func _check_team_ops() -> void:
	print("\n· 上阵 / 下阵 / 清空")
	var clear_btn: Button = _scene.get_node_or_null("%ClearButton")
	var deploy_btn: Button = _scene.get_node_or_null("%DeployButton")
	var remove_btn: Button = _scene.get_node_or_null("%RemoveButton")
	_ok("清空 / 上阵 / 下阵按钮齐备", clear_btn != null and deploy_btn != null and remove_btn != null)
	if clear_btn == null:
		return

	clear_btn.pressed.emit()
	_eq("清空后阵中无人", _team_size(), 0)

	# 点空位放置
	_scene.call("_select", "knight_rock")
	(_find("BoardCell_2") as Button).pressed.emit()
	_eq("点空位后上阵 1 人", _team_size(), 1)
	_eq("落在被点的那一格", int(_scene.call("_slot_of", "knight_rock")), 2)
	# 改动即时落盘：不点「确认选择」也是永久的（从主界面编队入口进来直接走也保得住）
	_eq("上阵即时写进出战编队", SaveDB.team().size(), 1)
	_eq("上阵即时写进当前预设", SaveDB.preset_entries(str(_scene.get("_preset_id"))).size(), 1)

	# 点已上阵的人 + 下阵按钮
	remove_btn.pressed.emit()
	_eq("下阵按钮把人撤下来", _team_size(), 0)
	_eq("下阵即时同步存档", SaveDB.team().size(), 0)

	# 同一个英雄不能上两次
	_scene.call("_select", "pyro_girl")
	deploy_btn.pressed.emit()
	_eq("上阵按钮放到推荐槽位", int(_scene.call("_slot_of", "pyro_girl")), 5)
	deploy_btn.pressed.emit()
	_eq("同一英雄不会重复上阵", _team_size(), 1)
	_ok("重复上阵给出提示",
		str(_scene.get_node("%ToastLabel").text).contains(_hero_name("pyro_girl")),
		str(_scene.get_node("%ToastLabel").text))

	# 点已上阵的格子 = 再点一次下阵
	_scene.call("_select", "pyro_girl")
	(_find("BoardCell_5") as Button).pressed.emit()
	_eq("再点已上阵的格子会下阵", _team_size(), 0)

	# 空位已被占用时不能硬塞
	_scene.call("_select", "knight_rock")
	(_find("BoardCell_4") as Button).pressed.emit()
	_scene.call("_select", "elf_ranger")
	_scene.call("_deploy", "elf_ranger", 4)
	_eq("同槽位不能挤两个人", _team_size(), 1)
	_ok("占位冲突给出提示",
		str(_scene.get_node("%ToastLabel").text).contains("占用"),
		str(_scene.get_node("%ToastLabel").text))

	# 点别人占着的格子 = 选中那个人，而不是把对方挤掉
	(_find("BoardCell_4") as Button).pressed.emit()
	_eq("点别人的格子只会切选中", str(_scene.get("_selected_id")), "knight_rock")
	_eq("并且没有把人挤下来", _team_size(), 1)

	# 上阵人数永远不会超过上限（真正的护栏在 SaveDB.normalize_team）
	_eq("阵中人数不超过上限", _team_size() <= MAX_MEMBERS, true)


# ---------------------------------------------------------------- 一键上阵

func _check_quick_fill() -> void:
	print("\n· 一键上阵")
	# 挂上 1003（敌方有重装），克制收益应该参与打分
	BattleCtx.begin_from_stage(1003, "smoke")
	_ok("关卡交接进了战斗上下文", int(BattleCtx.stage_id) == 1003)

	(_find("ClearButton") as Button).pressed.emit()
	_eq("先清空", _team_size(), 0)

	(_find("QuickFillButton") as Button).pressed.emit()
	_eq("一键上阵填满可用英雄", _team_size(), mini(ALL_HEROES.size(), MAX_MEMBERS))
	_ok("一键上阵后战力 > 0", int(_scene.get("_report").get("total_power", 0)) > 0,
		str(_scene.get("_report").get("total_power", 0)))
	_ok("一键上阵给出提示",
		str(_scene.get_node("%ToastLabel").text).contains("一键上阵"),
		str(_scene.get_node("%ToastLabel").text))

	# 一键上阵是启发式：多人抢同一推荐位时，排名靠前的人就位、后来者在**同排**里
	# 另找空位（法师不会被塞到前排）。这里钉两条硬不变式。
	var team: Array = _scene.get("_team")
	var seen_slots := {}
	var on_prefer_row := 0
	for raw in team:
		var e: Dictionary = raw
		var cid := str(e.get("char_id", ""))
		var slot := int(e.get("slot", 0))
		var want := int(GameDB.character(cid).get("prefer_slot", 1))
		seen_slots[slot] = true
		var row := GameDB.row_of_slot(slot)
		_eq("%s 落在推荐排（%s）" % [cid, GameDB.row_name(GameDB.row_of_slot(want))],
			row, GameDB.row_of_slot(want))
		if slot == want:
			on_prefer_row += 1
	_ok("至少有英雄就位在自己的推荐槽位", on_prefer_row > 0, "%d / %d" % [on_prefer_row, team.size()])
	_eq("一键上阵不会占用重复槽位", seen_slots.size(), team.size())


# ---------------------------------------------------------------- 阵容预设

func _check_presets() -> void:
	print("\n· 阵容预设（3 栏）")
	var bar: HBoxContainer = _scene.get_node_or_null("%PresetBar")
	_ok("预设栏存在", bar != null)
	if bar != null:
		_eq("3 个预设按钮", bar.get_child_count(), 3)

	_eq("初始停在配置里的第一个预设", str(_scene.get("_preset_id")), "main")

	# 从干净状态起：手编一套主线队，这样才能验「切走时会不会把阵容带走」
	(_find("ClearButton") as Button).pressed.emit()
	_eq("先清空", _team_size(), 0)
	for char_id in SEED_TEAM:
		_scene.call("_deploy", char_id)
	_eq("手编出主线队 3 人", _team_size(), 3)

	# 切到 PVP 队：当前 3 人要先落回 main，再载入空的 pvp
	(_find("PresetBtn_pvp") as Button).pressed.emit()
	_eq("切到 PVP 队", str(_scene.get("_preset_id")), "pvp")
	_eq("PVP 队初始为空", _team_size(), 0)
	_eq("存档里的当前预设同步", SaveDB.active_preset(), "pvp")
	_eq("主线队被存回旧预设", SaveDB.preset_entries("main").size(), 3)

	# 在 PVP 队里编 1 人，切到副本队触发落盘，再切回主线队
	_scene.call("_deploy", "holy_priest")
	_eq("PVP 队编入 1 人", _team_size(), 1)
	(_find("PresetBtn_dungeon") as Button).pressed.emit()
	_eq("副本队为空", _team_size(), 0)
	_eq("PVP 队的 1 人被单独存住", SaveDB.preset_entries("pvp").size(), 1)
	_eq("副本队确实存了空档", SaveDB.preset_entries("dungeon").size(), 0)

	(_find("PresetBtn_main") as Button).pressed.emit()
	_eq("切回主线队", _team_size(), 3)
	_eq("切回后阵容就是那 3 个人",
		[_team_id_at(0), _team_id_at(1), _team_id_at(2)],
		["knight_rock", "pyro_girl", "elf_ranger"])
	_eq("当前预设标记同步回来", SaveDB.active_preset(), "main")
	_ok("预设提示写出了人数",
		str(_scene.get_node("%PresetHint").text).contains("3"),
		str(_scene.get_node("%PresetHint").text))


# ---------------------------------------------------------------- 确认闭环

func _check_confirm() -> void:
	print("\n· 确认选择 → 扣体力 → 写档 → 交接战斗")
	var confirm: Button = _scene.get_node_or_null("%ConfirmButton")
	var sub: Label = _scene.get_node_or_null("%ConfirmSub")
	var tl: Label = _scene.get_node_or_null("%ToastLabel")
	_ok("确认按钮与副标题齐备", confirm != null and sub != null)
	if confirm == null:
		return

	_ok("确认按钮副文案取自配置",
		sub.text == str(GameDB.formation_section("confirm_button").get("sub_text", "")), sub.text)

	# 真跑的话会切场景，把后续断言全打断；这里关掉自动跳转，只验前半段
	_scene.set("auto_transition", false)
	_ok("确认后去的是战斗场景",
		str(_scene.get("battle_scene")).ends_with("battle.tscn"), str(_scene.get("battle_scene")))
	_ok("战斗场景真实存在", ResourceLoader.exists(str(_scene.get("battle_scene"))))

	# ---- 空队伍不许出发 ----
	(_find("ClearButton") as Button).pressed.emit()
	_eq("阵中无人", _team_size(), 0)
	confirm.pressed.emit()
	_ok("空队伍被拦下", tl.text.contains("至少上阵"), tl.text.replace("\n", " / "))

	# ---- 选好关卡与阵容后出发 ----
	BattleCtx.begin_from_stage(1004, "smoke")
	for char_id in SEED_TEAM:
		_scene.call("_deploy", char_id)
	_eq("出发前阵中 3 人", _team_size(), 3)

	var cost := GameDB.stage_stamina(1004)
	_eq("1004 的体力消耗取自关卡配置", cost, 6)
	var before := StaminaSys.current()
	confirm.pressed.emit()
	_eq("确认选择扣掉本关体力", StaminaSys.current(), before - cost)
	_ok("提示条报出关卡号", tl.text.contains("1004"), tl.text.replace("\n", " / "))
	_eq("出战编队被写进存档", SaveDB.team().size(), 3)
	_eq("当前预设也同步存了一份", SaveDB.preset_entries("main").size(), 3)
	_eq("存档里的槽位与界面一致",
		[int(SaveDB.team()[0].slot), int(SaveDB.team()[1].slot), int(SaveDB.team()[2].slot)],
		[1, 5, 6])

	# 写档后 battle 侧读到的阵容必须与编队页一致（同一份数据、同一套战力口径）
	var roster := RealmDB.roster()
	_eq("战斗侧读到的上阵人数一致", roster.size(), 3)
	_ok("战斗侧阵容战力 > 0", RealmDB.team_power() > 0, str(RealmDB.team_power()))

	# ---- 体力不足时拒绝出发，且不再扣 ----
	StaminaSys.spend(StaminaSys.current())
	_eq("体力已压到 0", StaminaSys.current(), 0)
	confirm.pressed.emit()
	_eq("体力不足时不扣体力", StaminaSys.current(), 0)
	_ok("提示条说明体力不足", tl.text.contains("体力不足"), tl.text.replace("\n", " / "))

	# ---- 保存按钮：显式点一次，存档与界面必须对上 ----
	var save_btn: Button = _scene.get_node_or_null("%SaveButton")
	_ok("保存按钮存在", save_btn != null)
	if save_btn != null:
		_ok("保存按钮已接信号", save_btn.pressed.get_connections().size() > 0)
		_ok("保存按钮文案取自配置",
			save_btn.text == str(GameDB.formation_section("save_button").get("text", "保存编队")),
			save_btn.text)
		(_find("ClearButton") as Button).pressed.emit()
		_scene.call("_deploy", "knight_rock")
		save_btn.pressed.emit()
		_eq("点保存后出战编队落盘 1 人", SaveDB.team().size(), 1)
		_eq("点保存后当前预设同步", SaveDB.preset_entries(str(_scene.get("_preset_id"))).size(), 1)
		_ok("保存给出确认反馈", tl.text.contains("已保存"), tl.text)

	# ---- 返回按钮 ----
	var back: Button = _scene.get_node_or_null("%BackButton")
	_ok("返回按钮已接信号", back != null and back.pressed.get_connections().size() > 0)
	_ok("返回按钮文案取自配置",
		back.text.contains(str(GameDB.formation_section("back_button").get("text", ""))), back.text)

	StaminaSys.fill()


# ---------------------------------------------------------------- 取节点与判定

func _find(nm: String) -> Node:
	if _scene == null:
		return null
	return _scene.find_child(nm, true, false)


func _tactic_body(id: String) -> Control:
	var box := _find("TacticBox_%s" % id)
	if box == null:
		return null
	return box.get_node_or_null("Body") as Control


func _ring_visible(cv: CardView) -> bool:
	if cv == null:
		return false
	var ring: Node = cv.get_node_or_null("SelectionRing")
	return ring != null and (ring as Control).visible


## 棋盘格上写的英雄名：格子内容 = 立绘 + 底部名牌（Panel 里套一个 Label）
func _cell_owner_name(cell: Node) -> String:
	if cell == null:
		return "<null>"
	for c in cell.get_children():
		if not (c is Panel):
			continue
		for cc in c.get_children():
			if cc is Label:
				return (cc as Label).text
	return ""


func _first_label_text(node: Node) -> String:
	if node == null:
		return "<null>"
	for c in node.get_children():
		if c is Label:
			return (c as Label).text
	return ""


func _thumb_deployed_text(node: Node) -> String:
	if node == null:
		return "<null>"
	for c in node.get_children():
		if c is Label and (c as Label).text.begins_with("已上阵"):
			return (c as Label).text
	return ""


func _thumb_border_is_gold(node: Node) -> bool:
	if node == null:
		return false
	var btn := node as Button
	if btn == null:
		return false
	var sb := btn.get_theme_stylebox("normal") as StyleBoxFlat
	if sb == null:
		return false
	return sb.border_color.g > 0.7 and sb.border_color.r > 0.9 and sb.border_width_left >= 4


func _library_has_text(text: String) -> bool:
	for c in (_scene.get_node("%LibraryGrid") as Node).get_children():
		if c is Label and (c as Label).text == text:
			return true
	return false


func _has_synergy(list: Array, id: String) -> bool:
	for raw in list:
		if str((raw as Dictionary).get("id", "")) == id:
			return true
	return false


## 编队条目里按 char_id 找单位（羁绊断言的公共取数口径）
func _unit_of(units: Array, char_id: String) -> Dictionary:
	for raw in units:
		var u: Dictionary = raw
		if str(u.get("char_id", "")) == char_id:
			return u
	return {}


func _stat_of(units: Array, char_id: String, key: String) -> float:
	var st: Dictionary = _unit_of(units, char_id).get("stats", {})
	return float(st.get(key, 0.0))


func _buffs_of(units: Array, char_id: String) -> Dictionary:
	var v: Variant = _unit_of(units, char_id).get("synergy_buffs", {})
	return v if v is Dictionary else {}


func _elem_dmg_of(units: Array, char_id: String) -> Dictionary:
	var v: Variant = _buffs_of(units, char_id).get("elem_dmg", {})
	return v if v is Dictionary else {}


func _view_size() -> int:
	return (_scene.get("_view") as Array).size()


func _team_size() -> int:
	return (_scene.get("_team") as Array).size()


func _team_id_at(i: int) -> String:
	return str((_scene.get("_team") as Array)[i].get("char_id", ""))


func _hero_name(char_id: String) -> String:
	return str(GameDB.character(char_id).get("name", char_id))


## 按配置字段筛出英雄 id（期望值从配置推导，加卡不用改测试）
func _ids_where(field: String, value: String) -> Array:
	var out: Array = []
	for raw in GameDB.characters():
		var c: Dictionary = raw
		if str(c.get(field, "")) == value:
			out.append(str(c.get("id", "")))
	return out


func _cards_ids(fan: CardFan) -> String:
	var out: Array = []
	for cv in fan.cards:
		out.append(str(cv.char_id))
	return str(out)


func _cards_all_in(fan: CardFan, ids: Array) -> bool:
	for cv in fan.cards:
		if not (str(cv.char_id) in ids):
			return false
	return true


func _entries(ids: Array) -> Array:
	var out: Array = []
	for raw in ids:
		var char_id := str(raw)
		out.append({
			"slot": int(GameDB.character(char_id).get("prefer_slot", 1)),
			"char_id": char_id,
		})
	return out


func _unit(char_id: String) -> Dictionary:
	var cfg := GameDB.character(char_id)
	var card := {
		"char_id": char_id,
		"level": int(cfg.get("demo_level", 1)),
		"star": int(cfg.get("demo_star", 1)),
		"exp": 0,
		"equipment": [],
	}
	return {"char_id": char_id, "config": cfg, "card": card,
		"stats": RealmDB.stats_of(card)}


func _power_sorted_ids() -> Array:
	var items := RealmDB.all_heroes()
	items.sort_custom(func(a, b): return int(a.get("power", 0)) > int(b.get("power", 0)))
	var out: Array = []
	for item in items:
		out.append(str(item.get("char_id", "")))
	return out
