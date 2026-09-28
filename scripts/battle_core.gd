class_name BattleCore
extends RefCounted
## BattleCore —— 3×3 半自动战斗内核（纯逻辑）
##
## 设计原则：**内核不认识「软泥怪」三个字**。
##   怪物打哪一排、是治疗还是加攻、Boss 有什么特性，全部读配置的
##   action / skill / traits 字段来解释执行。加一只新怪 = 加一条配置，不改这个文件。
##
## 时间轴：ATB 但不用 delta 累积 —— 每个单位的「下次行动时刻」= 已用时 + gauge_max / spd，
##   每次取最早的那个执行。好处是同一份种子跑出的战报逐字节一致，
##   冒烟测试可以断言具体数值，UI 也只需要「隔 0.7 秒调一次 step()」就能演出来。
##
## 与界面层的契约：step() 返回一串事件（伤害 / 治疗 / buff / 死亡 / 结束），
##   界面只负责把事件播成动画，不参与任何数值计算。

const SIDE_PLAYER := "player"
const SIDE_ENEMY := "enemy"
const ROW_ORDER := ["front", "middle", "back"]

const GROWTH := preload("res://scripts/growth_core.gd")

# ---------------------------------------------------------------- 状态

var stage: Dictionary = {}
var stage_id: int = 0
var reward_scale_note: String = ""

var units: Array = []          ## 双方全部单位（含已阵亡，便于战后统计）
var finished: bool = false
var winner: String = ""        ## "player" / "enemy" / "draw"
var end_reason: String = ""    ## "wipe" / "timeout"
var action_count: int = 0
var log_lines: Array = []      ## 人话战报，右侧面板直接显示
var rng_seed: int = 0
var atk_bonus: float = 1.0     ## 来自祭坛祝福这类外部增益

var _rng := RandomNumberGenerator.new()
var _clock: float = 0.0        ## 当前行动时刻
## 不另建行动队列：每个单位的 time 字段就是「它下次行动的时刻」，
## 谁最小谁先动。单位数 ≤ 12，线性扫描比维护堆更简单，也不会出现
## 「队列里的引用和 units 里的对象不是同一个 Dictionary」这类 identity 坑。


func setup(p_stage_id: int, player_entries: Array, opts: Dictionary = {}) -> void:
	stage_id = p_stage_id
	stage = GameDB.chapter_stage(stage_id)
	rng_seed = int(opts.get("seed", -1))
	if rng_seed < 0:
		rng_seed = int(Time.get_ticks_usec() & 0x7FFFFFFF)
	_rng.seed = rng_seed
	atk_bonus = float(opts.get("atk_bonus", 1.0))

	units.clear()
	log_lines.clear()
	_clock = 0.0
	action_count = 0
	finished = false
	winner = ""
	end_reason = ""

	_build_players(player_entries)
	_build_enemies()
	_apply_env()
	_apply_open_traits()
	_apply_synergy_open()
	_schedule_all()

	_push("【%s】战斗开始 —— 我方战力 %d，建议战力 %d"
		% [str(stage.get("name", "未知关卡")), team_power(SIDE_PLAYER),
			int(stage.get("recommend_power", 0))])


## 我方上阵名单：优先用存档里的真实编队；存档还没有编队时（新号 / 演示态）
## 回落到主界面那套演示阵容，保证「选关页点进去就能打」。
static func player_entries() -> Array:
	var roster: Array = RealmDB.roster()
	if not roster.is_empty():
		return roster

	var by_id: Dictionary = {}
	for item in RealmDB.showcase_lineup():
		by_id[str(item.get("char_id", ""))] = item

	var out: Array = []
	for cid in GameDB.menu().get("demo_team_slots", []):
		var item: Variant = by_id.get(str(cid), null)
		if not (item is Dictionary):
			continue
		var entry: Dictionary = item
		var cfg: Dictionary = entry.get("config", {})
		var slot := int(cfg.get("prefer_slot", 1))
		out.append({
			"slot": slot,
			"side": SIDE_PLAYER,
			"cell": GameDB.slot_cell(SIDE_PLAYER, slot),
			"row": GameDB.row_of_slot(slot),
			"char_id": str(entry.get("char_id", "")),
			"card": entry.get("card", {}),
			"config": cfg,
			"stats": entry.get("stats", {}),
		})
	out.sort_custom(func(a, b): return int(a.slot) < int(b.slot))
	return out


# ---------------------------------------------------------------- 装配

func _build_players(entries: Array) -> void:
	for raw in entries:
		var e: Dictionary = raw
		var cfg: Dictionary = e.get("config", {})
		var stats: Dictionary = e.get("stats", {})
		if cfg.is_empty() or stats.is_empty():
			continue
		var slot := int(e.get("slot", cfg.get("prefer_slot", 1)))
		var u := _base_unit(SIDE_PLAYER)
		u.slot = slot
		u.cell = GameDB.slot_cell(SIDE_PLAYER, slot)
		u.row = GameDB.row_of_slot(slot)
		u.char_id = str(cfg.get("id", ""))
		u.name = str(cfg.get("name", ""))
		u.level = int((e.get("card", {}) as Dictionary).get("level", 1))
		u.star = int((e.get("card", {}) as Dictionary).get("star", 1))
		u.rarity = str(cfg.get("rarity", "R"))
		u.element = str(cfg.get("element", ""))
		u.role = str(cfg.get("role", ""))
		u.icon = str(cfg.get("portrait", ""))
		u.portrait = str(cfg.get("portrait", ""))
		u.max_hp = int(stats.get("hp", 1))
		u.hp = u.max_hp
		u.atk = float(stats.get("atk", 1))
		u.def = float(stats.get("def", 0))
		u.mres = float(stats.get("mres", 0))
		u.crit = float(stats.get("crit", 0.05))
		u.crit_dmg = float(stats.get("crit_dmg", GameDB.combat().get("base_crit_damage", 1.5)))
		u.spd = float(stats.get("spd", 100))
		u.ult = cfg.get("skill", {}).get("effect", {})
		u.ult_name = str(cfg.get("skill", {}).get("name", ""))
		# 羁绊的战斗级效果：技能词条之外的那部分（开局能量 / 开局护盾 / 元素伤害）
		var buffs: Variant = e.get("synergy_buffs", {})
		if buffs is Dictionary:
			u.open_energy = float(buffs.get("open_energy", 0.0))
			u.open_shield = float(buffs.get("open_shield", 0.0))
			var ed: Variant = buffs.get("elem_dmg", {})
			if ed is Dictionary:
				u.elem_dmg = ed
		var act: Dictionary = _role_action(str(cfg.get("role", "")))
		u.action = act
		units.append(u)


func _build_enemies() -> void:
	var enemies: Array = stage.get("enemies", [])
	var scale := float(stage.get("power_scale", 1.0))
	for raw in enemies:
		var e: Dictionary = raw
		var mob_id := str(e.get("mob", ""))
		var cfg: Dictionary = GameDB.monster(mob_id)
		if cfg.is_empty():
			push_warning("[BattleCore] 关卡 %d 引用了不存在的怪物 %s" % [stage_id, mob_id])
			continue
		var base: Dictionary = cfg.get("base", {})
		var slot := int(e.get("slot", 1))
		var u := _base_unit(SIDE_ENEMY)
		u.slot = slot
		u.cell = GameDB.slot_cell(SIDE_ENEMY, slot)
		u.row = GameDB.row_of_slot(slot)
		u.mob_id = mob_id
		u.name = str(cfg.get("name", mob_id))
		u.level = int(e.get("lv", stage.get("no", 1)))
		u.element = str(cfg.get("element", ""))
		u.role = str(cfg.get("role", ""))
		u.icon = str(cfg.get("icon", ""))
		u.portrait = str(cfg.get("portrait", ""))
		u.is_boss = bool(cfg.get("boss", false))
		# 只缩放战斗成长轴；spd / crit 是节奏轴，不参与强度缩放
		u.max_hp = int(round(float(base.get("hp", 1)) * scale))
		u.hp = u.max_hp
		u.atk = float(base.get("atk", 1)) * scale
		u.def = float(base.get("def", 0)) * scale
		u.mres = float(base.get("mres", 0)) * scale
		u.crit = float(base.get("crit", 0.03))
		u.crit_dmg = float(base.get("crit_dmg", 1.5))
		u.spd = float(base.get("spd", 100))
		u.action = cfg.get("action", {})
		u.skill = cfg.get("skill", {})
		u.traits = cfg.get("traits", [])
		units.append(u)


func _base_unit(side: String) -> Dictionary:
	return {
		"uid": units.size(), "side": side, "slot": 0, "cell": Vector2i.ZERO, "row": "",
		"char_id": "", "mob_id": "", "name": "", "level": 1, "star": 1, "rarity": "R",
		"element": "", "role": "", "icon": "", "portrait": "",
		"max_hp": 1, "hp": 1, "shield": 0, "shield_until": 0,
		"atk": 1.0, "def": 0.0, "mres": 0.0, "crit": 0.05, "crit_dmg": 1.5, "spd": 100.0,
		"energy": 0, "stun": 0, "actions": 0, "atk_stacks": 0, "buff_atk": 0.0,
		# 羁绊的开局效果（RealmDB.apply_synergies 从配置里算好塞进 entries）
		"open_energy": 0.0, "open_shield": 0.0, "elem_dmg": {},
		"action": {}, "skill": {}, "ult": {}, "ult_name": "", "traits": [],
		"is_boss": false, "alive": true, "damage_dealt": 0, "damage_taken": 0,
		"time": 0.0,
	}


## 场上的环境效果（如 1004 的【风暴气场】）：命中单位的元素就吃到一个属性乘区
func _apply_env() -> void:
	var env: Dictionary = stage.get("env", {})
	if env.is_empty():
		return
	var elem := str(env.get("element", ""))
	var stat := str(env.get("stat", ""))
	var mult := float(env.get("mult", 1.0))
	var hit := 0
	for u in units:
		if str(u.element) != elem:
			continue
		u[stat] = float(u.get(stat, 0.0)) * mult
		hit += 1
	if hit > 0:
		_push("环境效果【%s】：%d 个 %s属性单位的%s 提升 %d%%"
			% [str(env.get("name", "")), hit, GameDB.element_name(elem), _stat_name(stat),
				int(round((mult - 1.0) * 100.0))])


## 开局被动：花岗岩护甲的护盾在这里一次性结算
func _apply_open_traits() -> void:
	for u in units:
		for raw in u.traits:
			var tr: Dictionary = raw
			if str(tr.get("id", "")) != "granite_armor":
				continue
			var shield := int(round(float(u.max_hp) * float(tr.get("shield_pct", 0.0))))
			u.shield += shield
			u.shield_until = 999999
			_push("%s 开局展开【%s】：护盾 %d（等同 %d%% 最大生命值）"
				% [str(u.name), str(tr.get("name", "")), shield,
					int(round(float(tr.get("shield_pct", 0.0)) * 100.0))])


## 羁绊的开局效果：开局能量 / 开局护盾。
##
## 数值由 RealmDB.apply_synergies 从 formation.synergies 里算好，挂在编队条目上，
## 这里只负责「一次性兑现」—— 战斗内核不解析羁绊规则，加新羁绊不用改这个文件。
func _apply_synergy_open() -> void:
	var gained := 0
	var shielded := 0
	for u in units:
		if str(u.side) != SIDE_PLAYER:
			continue
		if float(u.open_energy) > 0.0:
			var gain := int(round(float(u.open_energy)))
			u.energy = mini(100, int(u.energy) + gain)
			_push("羁绊开局：%s 能量 +%d（当前 %d）" % [str(u.name), gain, int(u.energy)])
			gained += 1
		if float(u.open_shield) > 0.0:
			var shield := int(round(float(u.max_hp) * float(u.open_shield)))
			if shield > 0:
				u.shield += shield
				u.shield_until = 999999
				_push("羁绊开局：%s 展开护盾 %d（%d%% 最大生命）"
					% [str(u.name), shield, int(round(float(u.open_shield) * 100.0))])
				shielded += 1
	if gained > 0 or shielded > 0:
		_push("—— 羁绊开局效果结算完毕（能量 %d 人 / 护盾 %d 人）" % [gained, shielded])


## 角色的普通行动（角色定位决定出手方式，不写死在界面里）
func _role_action(role_id: String) -> Dictionary:
	match role_id:
		"tank", "warrior":
			return {"kind": "attack", "target": "nearest_front", "damage": "phys", "mult": 1.0}
		"mage":
			return {"kind": "attack", "target": "middle_row", "damage": "magic", "mult": 0.9, "aoe": true}
		"archer", "assassin":
			return {"kind": "attack", "target": "lowest_hp_back", "damage": "phys", "mult": 1.0}
		"healer":
			return {"kind": "heal", "target": "lowest_hp_ally", "heal_pct": 0.18}
		"support":
			return {"kind": "buff_atk", "target": "all_allies", "value": 0.08, "max_stacks": 3}
		_:
			return {"kind": "attack", "target": "nearest_front", "damage": "phys", "mult": 1.0}


# ---------------------------------------------------------------- 查询

func team_of(side: String) -> Array:
	var out: Array = []
	for u in units:
		if str(u.side) == side:
			out.append(u)
	return out


func alive_of(side: String) -> Array:
	var out: Array = []
	for u in units:
		if str(u.side) == side and bool(u.alive):
			out.append(u)
	return out


func boss_unit() -> Dictionary:
	for u in units:
		if bool(u.is_boss) and bool(u.alive):
			return u
	return {}


func team_power(side: String) -> int:
	var total := 0
	for u in team_of(side):
		total += unit_power(u)
	return total


## 单张单位的战力估值：走 GrowthCore 的权重（全项目一把尺子），
## 于是「我方战力 / 建议战力」和选关页、主界面的数字对得上。
func unit_power(u: Dictionary) -> int:
	return GROWTH.power_of(float(u.max_hp), float(u.atk), float(u.def),
		float(u.mres), float(u.spd), float(u.crit))


func current_power(side: String) -> int:
	var total := 0
	for u in alive_of(side):
		var ratio := float(u.hp) / maxf(1.0, float(u.max_hp))
		total += int(round(float(unit_power(u)) * ratio))
	return total


func hp_ratio(side: String) -> float:
	var cur := 0.0
	var mx := 0.0
	for u in team_of(side):
		cur += float(u.hp)
		mx += float(u.max_hp)
	return 1.0 if mx <= 0.0 else cur / mx


## 战场上格子的像素落点：锚点 = 单位脚下的地面点，立绘由此向上生长。
## 两侧的纵深方向不同（敌方朝左上收、我方朝左下收），所以各用一套 row step。
func cell_pos(side: String, slot: int) -> Vector2:
	var b: Dictionary = GameDB.battle_cfg()
	var col_step: Array = b.get("col_step", [220, 0])
	var cell := GameDB.slot_cell(side, slot)
	var is_enemy := side == SIDE_ENEMY
	var row_step: Array = b.get("row_step", [-80, -132]) if is_enemy \
		else b.get("player_row_step", [-80, 132])
	var origin: Array = b.get("enemy_origin", [880, 500]) if is_enemy \
		else b.get("player_origin", [880, 678])
	# 相对排数：两侧都以前排为 0、中排 1、后排 2
	var depth := (2 - cell.y) if is_enemy else (cell.y - 3)
	var ox := float(origin[0]) + float(col_step[0]) * float(cell.x - 1) + float(row_step[0]) * float(depth)
	var oy := float(origin[1]) + float(col_step[1]) * float(cell.x - 1) + float(row_step[1]) * float(depth)
	return Vector2(ox, oy)


func unit_pos(u: Dictionary) -> Vector2:
	return cell_pos(str(u.side), int(u.slot))


# ---------------------------------------------------------------- 时间轴

func _schedule_all() -> void:
	var gauge := float(GameDB.combat().get("atb", {}).get("gauge_max", 1000))
	for u in units:
		u.time = gauge / maxf(1.0, float(u.spd))


## 下一个行动者（ATB：谁先攒满谁先动）
func peek_actor() -> Dictionary:
	var best: Dictionary = {}
	for u in units:
		if not bool(u.alive):
			continue
		if best.is_empty() or float(u.time) < float(best.time):
			best = u
	return best


func action_order() -> Array:
	var arr: Array = alive_of(SIDE_PLAYER) + alive_of(SIDE_ENEMY)
	arr.sort_custom(func(a, b): return float(a.time) < float(b.time))
	return arr


# ---------------------------------------------------------------- 回合推进

## 推进一次行动，返回这一拍发生的事件列表（界面按顺序播动画）
func step() -> Array:
	var evs: Array = []
	if finished:
		return evs
	var actor := peek_actor()
	if actor.is_empty():
		_finish_by_wipe(evs)
		return evs

	_clock = float(actor.time)
	_clock_unit_to(actor)
	action_count += 1

	if int(actor.stun) > 0:
		actor.stun = int(actor.stun) - 1
		evs.append({"t": "stun", "unit": actor})
		_push("%s 处于眩晕，跳过行动" % str(actor.name))
	else:
		_act(actor, evs)
		actor.actions = int(actor.actions) + 1

	_expire_shields()
	_check_end(evs)
	return evs


func run_all(max_actions: int = -1) -> Array:
	var limit := max_actions if max_actions > 0 else int(GameDB.battle_cfg().get("max_actions", 400))
	var all: Array = []
	while not finished and action_count < limit:
		all.append_array(step())
	if not finished:
		_finish_by_timeout(all)
	return all


func _clock_unit_to(u: Dictionary) -> void:
	var gauge := float(GameDB.combat().get("atb", {}).get("gauge_max", 1000))
	u.time = _clock + gauge / maxf(1.0, float(u.spd))


func _expire_shields() -> void:
	for u in units:
		if int(u.shield) > 0 and action_count >= int(u.shield_until) and int(u.shield_until) < 999999:
			u.shield = 0


# ---------------------------------------------------------------- 行动执行

func _act(actor: Dictionary, evs: Array) -> void:
	var energy_max := int(GameDB.combat().get("atb", {}).get("ult_energy_max", 100))
	# 怒气满了先放大招（Boss 的大招写在 traits 里，用同一套结算）
	if int(actor.energy) >= energy_max:
		var ult: Dictionary = _ult_of(actor)
		if not ult.is_empty():
			actor.energy = 0
			evs.append({"t": "action", "unit": actor, "kind": "ult", "name": str(ult.get("name", "大招"))})
			_push("★ %s 释放【%s】" % [str(actor.name), str(ult.get("name", "大招"))])
			_execute(actor, ult, evs)
			return

	var skill: Dictionary = actor.skill
	if not skill.is_empty():
		var interval := maxi(1, int(skill.get("interval", 1)))
		var offset := int(skill.get("offset", 0))
		if (int(actor.actions) - offset) % interval == 0:
			evs.append({"t": "action", "unit": actor, "kind": "skill", "name": str(skill.get("name", ""))})
			_push("· %s 使用【%s】" % [str(actor.name), str(skill.get("name", ""))])
			_execute(actor, skill, evs)
			return

	var act: Dictionary = actor.action
	evs.append({"t": "action", "unit": actor, "kind": "attack"})
	_execute(actor, act, evs)


## Boss 大招：优先取 traits 里带 mult / heal 的主动特性
func _ult_of(u: Dictionary) -> Dictionary:
	for raw in u.traits:
		var tr: Dictionary = raw
		if tr.has("mult") and tr.has("target"):
			return tr
	return u.ult


func _execute(actor: Dictionary, spec: Dictionary, evs: Array) -> void:
	var kind := str(spec.get("kind", "attack"))
	match kind:
		"heal", "heal_lowest":
			_do_heal(actor, spec, evs)
		"shield_all":
			# 护盾的作用范围必须从 spec.target 取 —— 骑士的「自身与相邻前排」和
			# 傀儡法师的「全队」都走这条分支，写死成全队会让骑士的护盾到处乱贴
			_do_shield(actor, spec, evs, str(spec.get("target", "all_allies")))
		"buff_atk":
			_do_buff(actor, spec, evs)
		_:
			_do_attack(actor, spec, evs)


func _do_attack(actor: Dictionary, spec: Dictionary, evs: Array) -> void:
	var dtype := str(spec.get("damage", "phys"))
	var mult := float(spec.get("mult", 1.0))
	var targets: Array = resolve_targets(actor, str(spec.get("target", "nearest_front")),
		bool(spec.get("aoe", false)))
	if targets.is_empty():
		return
	for t in targets:
		var d: Dictionary = t
		var dmg := compute_damage(actor, d, mult, dtype)
		apply_damage(actor, d, dmg, evs)
	# 能量按「这一拍打到的目标数」结算：群攻攒怒气更快，和常规卡牌的体感一致
	var energy_per_hit := int(GameDB.combat().get("atb", {}).get("ult_energy_per_hit", 12))
	actor.energy = mini(100, int(actor.energy) + energy_per_hit * targets.size())
	# 裂地震击这类附带控制的效果
	if spec.has("stun_chance"):
		for t in targets:
			var d: Dictionary = t
			if not bool(d.alive):
				continue
			if _rng.randf() < float(spec.get("stun_chance", 0.0)):
				d.stun = int(d.stun) + maxi(1, int(spec.get("stun_actions", 1)))
				evs.append({"t": "stun_apply", "unit": d})
				_push("  ↳ %s 被震晕，下回合无法行动" % str(d.name))


func _do_heal(actor: Dictionary, spec: Dictionary, evs: Array) -> void:
	var targets: Array = resolve_targets(actor, str(spec.get("target", "lowest_hp_ally")), false)
	if targets.is_empty():
		return
	var amount := 0
	if spec.has("mult"):
		amount = int(round(float(actor.atk) * float(spec.get("mult", 1.0))))
	for t in targets:
		var d: Dictionary = t
		if not bool(d.alive):
			continue
		if amount <= 0:
			amount = int(round(float(d.max_hp) * float(spec.get("heal_pct", 0.18))))
		var before := int(d.hp)
		d.hp = mini(int(d.max_hp), int(d.hp) + amount)
		var real := int(d.hp) - before
		evs.append({"t": "heal", "src": actor, "dst": d, "value": real, "overheal": amount - real})
		_push("  ↳ 治疗 %s +%d (%d/%d)" % [str(d.name), real, int(d.hp), int(d.max_hp)])


func _do_shield(actor: Dictionary, spec: Dictionary, evs: Array, target: String) -> void:
	var targets: Array = resolve_targets(actor, target, true)
	# 护盾量可以按攻击算（法师护盾），也可以按防御算（骑士护盾叠防御）
	var from_stat := str(spec.get("from", "atk"))
	var amount := int(round(float(actor.get(from_stat, actor.atk)) * float(spec.get("mult", 1.0))))
	if spec.has("flat"):
		amount = int(spec.get("flat", 0))
	var turns := int(spec.get("turns", 2))
	for t in targets:
		var d: Dictionary = t
		if not bool(d.alive):
			continue
		d.shield += amount
		d.shield_until = action_count + turns
		evs.append({"t": "shield", "src": actor, "dst": d, "value": amount})
		_push("  ↳ 为 %s 附加护盾 %d（%d 回合）" % [str(d.name), amount, turns])


func _do_buff(actor: Dictionary, spec: Dictionary, evs: Array) -> void:
	var value := float(spec.get("value", 0.08))
	var max_stacks := int(spec.get("max_stacks", 3))
	var targets: Array = resolve_targets(actor, "all_allies", true)
	for t in targets:
		var d: Dictionary = t
		if not bool(d.alive):
			continue
		if int(d.atk_stacks) >= max_stacks:
			continue
		d.atk_stacks = int(d.atk_stacks) + 1
		d.buff_atk = float(d.buff_atk) + value
		evs.append({"t": "buff", "src": actor, "dst": d, "stat": "atk",
			"value": value, "stacks": int(d.atk_stacks)})
	_push("  ↳ 全队攻击力 +%d%%（当前 %d 层）"
		% [int(round(value * 100.0)), int(actor.atk_stacks)])


# ---------------------------------------------------------------- 目标选择

## 目标语义全部相对「被打的那一方」：
##   nearest_front = 对面前排最前面那排；middle_row / back_row = 对面中/后排
##   lowest_hp_back = 对面后排残血；lowest_hp_ally / all_allies = 己方
##   self_and_adjacent_front = 自己与同排（骑士的护盾）
func resolve_targets(actor: Dictionary, target: String, aoe: bool) -> Array:
	var foe := SIDE_ENEMY if str(actor.side) == SIDE_PLAYER else SIDE_PLAYER
	var t := target.trim_prefix("enemy_")
	match t:
		"all_allies":
			return alive_of(str(actor.side))
		"lowest_hp_ally":
			return _lowest_hp(alive_of(str(actor.side)))
		"self_and_adjacent_front":
			return _same_row(actor)
		"nearest_front":
			return _row_target(foe, _frontmost_row(foe), aoe, actor)
		"all_foes":
			# 敌方全体：群攻绝技（陨星风暴）需要跨排选人，_row_target 只管一排
			return alive_of(foe)
		"middle_row":
			return _row_target(foe, "middle", aoe, actor)
		"back_row":
			return _row_target(foe, "back", aoe, actor)
		"lowest_hp_back", "back_lowest_hp":
			# 两种语序都认：配置里既有 enemy_back_lowest_hp，也有 enemy_lowest_hp_back。
			# 早先只登记了后者，前者的卡牌会被静默降级成「打前排最低血」。
			var pool := _units_in_row(foe, "back")
			if pool.is_empty():
				pool = _units_in_row(foe, _frontmost_row(foe))
			if aoe:
				return pool if not pool.is_empty() else _row_target(foe, _frontmost_row(foe), true, actor)
			return _lowest_hp(pool)
		"front_row":
			return _row_target(foe, "front", aoe, actor)
		_:
			return _row_target(foe, _frontmost_row(foe), aoe, actor)


func _frontmost_row(side: String) -> String:
	for row in ROW_ORDER:
		if not _units_in_row(side, row).is_empty():
			return row
	return "front"


func _units_in_row(side: String, row: String) -> Array:
	var slots: Array = GameDB.board().get("row_slots", {}).get(row, [])
	var out: Array = []
	for u in units:
		if str(u.side) != side or not bool(u.alive):
			continue
		# 逐个数比较，不用 in：配置里的槽位号是 JSON 解析出来的 float，
		# 与内省的 int 做 has() 判定会踩到 Variant 相等性的坑（同 game_db.row_of_slot）
		for s in slots:
			if int(s) == int(u.slot):
				out.append(u)
				break
	return out


## 同一排里挑当前血量最低的（确定性选择 —— 随机目标会让战报无法复现）
func _lowest_hp(pool: Array) -> Array:
	if pool.is_empty():
		return []
	var best: Dictionary = pool[0]
	for u in pool:
		if int(u.hp) < int(best.hp):
			best = u
	return [best]


func _row_target(side: String, row: String, aoe: bool, actor: Dictionary) -> Array:
	var pool := _units_in_row(side, row)
	if pool.is_empty():
		pool = _units_in_row(side, _frontmost_row(side))
	if pool.is_empty():
		return []
	if aoe:
		return pool
	return _lowest_hp(pool)


## 骑士的「自身与相邻前排」：自己 + 同侧同排的其它单位
## 用 uid 判身份而不是字典相等：Dictionary 的 == 在 Godot 里比的是内容，
## 两个属性一样的单位会被判成同一个，uid 是唯一可靠的口径。
func _same_row(actor: Dictionary) -> Array:
	var out: Array = [actor]
	for u in units:
		if str(u.side) == str(actor.side) and bool(u.alive) \
				and int(u.uid) != int(actor.uid) and str(u.row) == str(actor.row):
			out.append(u)
	return out


# ---------------------------------------------------------------- 伤害结算

func compute_damage(a: Dictionary, d: Dictionary, mult: float, dtype: String) -> Dictionary:
	var c: Dictionary = GameDB.combat()
	var atk := float(a.atk) * (1.0 + float(a.buff_atk)) * atk_bonus
	var base := atk * mult

	var k := float(c.get("def_reduction_k", 300))
	var defense := float(d.def) if dtype == "phys" else float(d.mres)
	var mitigation := k / (k + maxf(0.0, defense))
	var dmg := base * mitigation

	var counter := GameDB.is_counter(str(a.element), str(d.element))
	if counter:
		dmg *= GameDB.damage_multiplier(str(a.element), str(d.element))

	# 羁绊给该属性单位的伤害加成（如「云端先锋队」的火元素伤害 +10%）
	var elem_bonus: Dictionary = a.get("elem_dmg", {})
	if not elem_bonus.is_empty():
		var bonus := float(elem_bonus.get(str(a.element), 0.0))
		if bonus > 0.0:
			dmg *= 1.0 + bonus

	var crit_chance := float(a.crit) + (GameDB.crit_bonus(str(a.element), str(d.element)) if counter else 0.0)
	var is_crit := _rng.randf() < crit_chance
	if is_crit:
		dmg *= float(a.crit_dmg)

	var phys_cut := _phys_reduction(d) if dtype == "phys" else 0.0
	dmg *= (1.0 - phys_cut)

	var variance := float(c.get("damage_variance", 0.05))
	dmg *= 1.0 + _rng.randf_range(-variance, variance)

	return {
		"value": maxi(1, int(round(dmg))),
		"crit": is_crit,
		"counter": counter,
		"phys_cut": phys_cut,
		"type": dtype,
	}


## 减伤类特性（花岗岩护甲）
func _phys_reduction(u: Dictionary) -> float:
	var cut := 0.0
	for raw in u.traits:
		var tr: Dictionary = raw
		if tr.has("phys_reduction"):
			cut = maxf(cut, float(tr.get("phys_reduction", 0.0)))
	return cut


func apply_damage(actor: Dictionary, target: Dictionary, dmg: Dictionary, evs: Array) -> void:
	var value := int(dmg.get("value", 0))
	var absorbed := 0
	if int(target.shield) > 0:
		absorbed = mini(int(target.shield), value)
		target.shield = int(target.shield) - absorbed
		value -= absorbed
	target.hp = maxi(0, int(target.hp) - value)
	target.damage_taken = int(target.damage_taken) + int(dmg.get("value", 0))
	actor.damage_dealt = int(actor.damage_dealt) + int(dmg.get("value", 0))

	var energy_per_taken := int(GameDB.combat().get("atb", {}).get("ult_energy_per_taken", 8))
	target.energy = mini(100, int(target.energy) + energy_per_taken)

	var lethal := int(target.hp) <= 0
	evs.append({
		"t": "damage", "src": actor, "dst": target, "value": int(dmg.get("value", 0)),
		"hp_loss": value, "shield_absorb": absorbed, "hp_after": int(target.hp),
		"crit": bool(dmg.get("crit", false)), "counter": bool(dmg.get("counter", false)),
		"phys_cut": float(dmg.get("phys_cut", 0.0)), "type": str(dmg.get("type", "phys")),
		"lethal": lethal,
	})

	var tip := ""
	if bool(dmg.get("crit", false)):
		tip += " 暴击"
	if bool(dmg.get("counter", false)):
		tip += " 克制"
	if absorbed > 0:
		tip += " (护盾吸收 %d)" % absorbed
	if float(dmg.get("phys_cut", 0.0)) > 0.0:
		tip += " (护甲 -%d%%)" % int(round(float(dmg.get("phys_cut", 0.0)) * 100.0))
	_push("  %s → %s  %d 伤害%s" % [str(actor.name), str(target.name), int(dmg.get("value", 0)), tip])

	if lethal:
		target.alive = false
		target.hp = 0
		evs.append({"t": "death", "unit": target})
		_push("  ✖ %s 阵亡" % str(target.name))


# ---------------------------------------------------------------- 胜负

func _check_end(evs: Array) -> void:
	if finished:
		return
	_finish_by_wipe(evs)


func _finish_by_wipe(evs: Array) -> void:
	var p := alive_of(SIDE_PLAYER).size()
	var e := alive_of(SIDE_ENEMY).size()
	if e == 0 and p == 0:
		_set_end("draw", "wipe", evs)
	elif e == 0:
		_set_end("player", "wipe", evs)
	elif p == 0:
		_set_end("enemy", "wipe", evs)


func _finish_by_timeout(evs: Array) -> void:
	var pr := hp_ratio(SIDE_PLAYER)
	var er := hp_ratio(SIDE_ENEMY)
	if absf(pr - er) < 0.02:
		_set_end("draw", "timeout", evs)
	else:
		_set_end("player" if pr > er else "enemy", "timeout", evs)


func _set_end(result: String, reason: String, evs: Array) -> void:
	finished = true
	winner = result
	end_reason = reason
	evs.append({"t": "end", "winner": result, "reason": reason,
		"player_hp": hp_ratio(SIDE_PLAYER), "enemy_hp": hp_ratio(SIDE_ENEMY),
		"actions": action_count})
	if reason == "timeout":
		_push("战斗超时，按剩余血量裁定：我方 %.0f%% / 敌方 %.0f%%"
			% [hp_ratio(SIDE_PLAYER) * 100.0, hp_ratio(SIDE_ENEMY) * 100.0])
	_push("战斗结束 —— %s" % ("我方胜利" if result == "player" else
		("我方失败" if result == "enemy" else "平局")))


# ---------------------------------------------------------------- 战报

func _push(line: String) -> void:
	log_lines.append(line)


func _stat_name(key: String) -> String:
	match key:
		"spd": return "攻速"
		"atk": return "攻击"
		"def": return "防御"
		"mres": return "法抗"
		"hp": return "生命"
		_: return key
