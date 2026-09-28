extends Node
## RealmDB —— 运行时派生层
##
## 唯一职责：把 SaveDB 里的裸存档（等级 / 星级 / 装备）换算成可直接用于
## 战斗与界面展示的最终属性。不写盘，不读配置以外的外部资源。
##
## 公式在 GrowthCore（纯函数层，场景构建脚本共用同一份），本层只负责喂配置，
## 并在其之上叠加羁绊增幅。装备加成尚未接入：GrowthCore.stats_of 不读 card.equipment。

const GROWTH := preload("res://scripts/growth_core.gd")


func stats_of(card: Dictionary) -> Dictionary:
	var cfg := GameDB.character(str(card.get("char_id", "")))
	if cfg.is_empty():
		return {}
	return GROWTH.stats_of(cfg, int(card.get("level", 1)), int(card.get("star", 1)),
		GameDB.star_bonus_table())


## 星级对全属性的百分比增幅，索引即星级
func star_multiplier(star: int) -> float:
	return GROWTH.star_multiplier(GameDB.star_bonus_table(), star)


## 单张卡的战力估值，用于关卡推荐战力比对
func battle_power(stats: Dictionary) -> int:
	if stats.is_empty():
		return 0
	return GROWTH.battle_power(stats)


## 战斗编队：按 grid slot 升序返回，含最终属性（已计入羁绊增幅）
func roster() -> Array:
	return apply_synergies(roster_of(SaveDB.team()))


## 用任意编队条目（{ "slot", "char_id" }）构造 unit 列表，不必先落盘 ——
## 编队页要预览、冒烟测试要断言，都靠这个入口；口径与 roster() 完全一致。
##
## 存档里没有这张卡时回落到配置的展演态（demo_level / demo_star）：
## 编队是有卡就能排的，不该因为「还没抽到」而算不出属性。
func roster_of(entries: Array) -> Array:
	var out: Array = []
	for raw in entries:
		if not (raw is Dictionary):
			continue
		var entry: Dictionary = raw
		var char_id := str(entry.get("char_id", ""))
		if char_id == "":
			continue
		var cfg := GameDB.character(char_id)
		if cfg.is_empty():
			continue
		var card := _card_or_demo(char_id, cfg)
		var slot := int(entry.get("slot", cfg.get("prefer_slot", 1)))
		var stats := stats_of(card)
		out.append({
			"slot": slot,
			"side": "player",
			"cell": GameDB.slot_cell("player", slot),
			"row": GameDB.row_of_slot(slot),
			"char_id": char_id,
			"card": card,
			"config": cfg,
			"stats": stats,
			"power": battle_power(stats),
		})
	out.sort_custom(func(a, b): return int(a["slot"]) < int(b["slot"]))
	return out


func team_power() -> int:
	var total := 0
	for unit in roster():
		total += battle_power(unit.stats)
	return total


# ---------------------------------------------------------------- 羁绊
#
# 羁绊是**声明式规则**：条件（cond）+ 效果（effect）都写在 formation.synergies 里，
# 这里只负责求值与结算，不在代码里写死任何组合。

## 羁绊条件求值
func synergy_matches(rule: Dictionary, units: Array) -> bool:
	var cond: Dictionary = rule.get("cond", {})
	if cond.is_empty() or units.is_empty():
		return false
	var need := int(cond.get("min", 1))
	match str(cond.get("type", "")):
		"member_count":
			return units.size() >= need
		"row_count":
			return _count_in(units, "row", cond.get("row", "")) >= need
		"role_count":
			return _count_cfg_in(units, "role", cond.get("roles", [])) >= need
		"element_count":
			return _count_cfg_in(units, "element", cond.get("elements", [])) >= need
		"rarity_count":
			return _count_cfg_in(units, "rarity", cond.get("rarities", [])) >= need
		"char_ids":
			# 指定英雄组合（GDD 的「同时上阵【A】+【B】」）：
			# min 缺省 = ids 全到齐，也可以显式写 min 表示「其中任意 N 名」
			var ids := _as_array(cond.get("ids", []))
			var hit := 0
			for u in units:
				var cfg: Dictionary = u["config"]
				if str(cfg.get("id", "")) in ids:
					hit += 1
			return hit >= (int(cond.get("min", ids.size())) if ids.size() > 0 else need)
		"distinct_elements":
			var seen := {}
			for u in units:
				var cfg: Dictionary = u["config"]
				var eid := str(cfg.get("element", ""))
				if eid != "":
					seen[eid] = true
			return seen.size() >= need
	return false


## 效果归一化：配置里的 effect（单条）与 effects（数组）统一成一份数组。
##
## 每项的 mode 决定它怎么结算：
##   mul    —— 属性乘算（hp / atk / def / mres / spd，stat=all 表示五维全吃）
##   add    —— 属性加算（crit 这类本身就带百分号的比率）
##   battle —— 不写进面板、交给战斗内核（open_energy 开局能量 / open_shield 开局护盾 / elem_dmg 元素伤害）
func synergy_effects(rule: Dictionary) -> Array:
	var out: Array = []
	var list: Variant = rule.get("effects", [])
	if list is Array and not (list as Array).is_empty():
		for raw in list:
			if raw is Dictionary:
				out.append(_normalize_effect(raw))
	else:
		var single: Variant = rule.get("effect", {})
		if single is Dictionary and not (single as Dictionary).is_empty():
			out.append(_normalize_effect(single))
	return out


func _normalize_effect(raw: Dictionary) -> Dictionary:
	var stat := str(raw.get("stat", "all"))
	var mode := "mul"
	if stat in ["open_energy", "open_shield", "elem_dmg"]:
		mode = "battle"
	elif stat == "crit":
		mode = "add"
	return {
		"stat": stat,
		"target": str(raw.get("target", "all")),
		"element": str(raw.get("element", "")),
		"mode": mode,
		# pct 走乘算（0.08 = +8%），value 走加算 / 战斗级数值（15.0 = 15 点能量）
		"pct": float(raw.get("pct", 0.0)),
		"value": float(raw.get("value", raw.get("pct", 0.0))),
	}


func active_synergies(units: Array) -> Array:
	var out: Array = []
	for raw in GameDB.synergies():
		var rule: Dictionary = raw
		if not synergy_matches(rule, units):
			continue
		var effs := synergy_effects(rule)
		var head: Dictionary = effs[0] if not effs.is_empty() else {}
		out.append({
			"id": str(rule.get("id", "")),
			"name": str(rule.get("name", "")),
			"text": str(rule.get("text", "")),
			"effects": effs,
			# 兼容旧口径：只读 stat / pct 的调用方拿到的仍是「第一条」效果
			"stat": str(head.get("stat", "all")),
			"pct": float(head.get("pct", 0.0)),
		})
	return out


## 把激活的羁绊增幅就地写回每个 unit 的 stats（并重算 power）。
## 战力口径因此天然统一：队伍战力 = Σ battle_power(带羁绊的最终属性)。
##
## 逐单位结算而不是全场共享一个乘区：羁绊效果可以定向（target: row:front），
## 前排专属的加成不该落到后排头上。
##
## 战斗级效果（开局能量 / 开局护盾 / 元素伤害）写进 unit["synergy_buffs"]，
## 由 battle_core 在布阵时读取 —— 界面显示的就是战斗里真正生效的。
func apply_synergies(units: Array) -> Array:
	var active := active_synergies(units)
	if active.is_empty() or units.is_empty():
		return units
	for u in units:
		var st: Dictionary = u["stats"]
		var mul := {"hp": 1.0, "atk": 1.0, "def": 1.0, "mres": 1.0, "spd": 1.0}
		var crit_add := 0.0
		var open_energy := 0.0
		var open_shield := 0.0
		var elem_dmg := {}

		for a in active:
			for raw in a["effects"]:
				var e: Dictionary = raw
				if not _effect_hits(e, u):
					continue
				var stat := str(e["stat"])
				match str(e["mode"]):
					"mul":
						var keys: Array = mul.keys() if stat == "all" else [stat]
						for k in keys:
							if mul.has(k):
								mul[k] = float(mul[k]) * (1.0 + float(e["pct"]))
					"add":
						if stat == "crit":
							crit_add += float(e["value"])
					"battle":
						match stat:
							"open_energy":
								open_energy += float(e["value"])
							"open_shield":
								open_shield += float(e["value"])
							"elem_dmg":
								var el := str(e["element"])
								if el != "":
									elem_dmg[el] = float(elem_dmg.get(el, 0.0)) + float(e["pct"])

		for k in ["hp", "atk", "def", "mres", "spd"]:
			st[k] = int(round(float(st.get(k, 0)) * float(mul[k])))
		if crit_add != 0.0:
			st["crit"] = minf(0.95, float(st.get("crit", 0.0)) + crit_add)
		u["stats"] = st
		u["power"] = battle_power(st)

		var buffs := {}
		if open_energy > 0.0:
			buffs["open_energy"] = open_energy
		if open_shield > 0.0:
			buffs["open_shield"] = open_shield
		if not elem_dmg.is_empty():
			buffs["elem_dmg"] = elem_dmg
		if not buffs.is_empty():
			u["synergy_buffs"] = buffs
	return units


## 效果是否命中这个单位：默认全场，row:<排> 时只作用于该排
func _effect_hits(e: Dictionary, u: Dictionary) -> bool:
	var target := str(e.get("target", "all"))
	if target == "" or target == "all":
		return true
	if target.begins_with("row:"):
		return str(u.get("row", "")) == target.substr(4)
	return true


## 还没激活、但最接近激活的那条羁绊 —— 空态里给玩家一句「怎么才能激活」
func synergy_hint(units: Array) -> String:
	var best_gap := 999
	var best_rule: Dictionary = {}
	for raw in GameDB.synergies():
		var rule: Dictionary = raw
		if synergy_matches(rule, units):
			continue
		var cond: Dictionary = rule.get("cond", {})
		if str(cond.get("type", "")) != "member_count":
			continue
		var gap := int(cond.get("min", 1)) - units.size()
		if gap <= 0 or gap >= best_gap:
			continue
		best_gap = gap
		best_rule = rule
	if best_rule.is_empty():
		return ""
	var fmt := str(GameDB.formation_section("tactical").get("synergy_hint_format", "上阵 %d 人可激活"))
	return (fmt % int(best_rule.get("cond", {}).get("min", 1))) + str(best_rule.get("name", ""))


# ---------------------------------------------------------------- 克制

## 属性克制 + 职业克制的提示文案。敌方构成来自关卡表（GameDB.stage_enemy_units）。
func counter_report(unit: Dictionary, enemy_units: Array) -> Dictionary:
	var cfg: Dictionary = unit.get("config", {})
	var elem_id := str(cfg.get("element", ""))
	var role_id := str(cfg.get("role", ""))
	var lines: Array = []
	var hits := 0
	var best_pct := 0

	var enemy_elem := {}
	var enemy_role := {}
	for e in enemy_units:
		var eid := str(e.get("element", ""))
		var rid := str(e.get("role", ""))
		if eid != "":
			enemy_elem[eid] = int(enemy_elem.get(eid, 0)) + 1
		if rid != "":
			enemy_role[rid] = int(enemy_role.get(rid, 0)) + 1

	# 属性克制：走 GameDB.is_counter，与战斗内核同一张克制表
	if elem_id != "":
		var hit_names: Array = []
		for eid in enemy_elem.keys():
			if GameDB.is_counter(elem_id, str(eid)):
				hit_names.append(GameDB.element_name(str(eid)))
				hits += int(enemy_elem[eid])
		if not hit_names.is_empty():
			var pct := int(round((GameDB.damage_multiplier(elem_id, str(hit_names[0])) - 1.0) * 100.0))
			best_pct = maxi(best_pct, pct)
			var tmpl := str(GameDB.formation_section("tactical").get("counter_format",
				"%s 克 %s　+%d%% 伤害"))
			lines.append(tmpl % [GameDB.element_name(elem_id), "、".join(hit_names), pct])

	# 职业克制：配置表里声明式匹配（攻方职业 → 守方职业）
	for raw in GameDB.role_counters():
		var rc: Dictionary = raw
		if not (role_id in _as_array(rc.get("attacker_roles", []))):
			continue
		var matched := 0
		for rid in _as_array(rc.get("defender_roles", [])):
			matched += int(enemy_role.get(str(rid), 0))
		if matched <= 0:
			continue
		hits += matched
		best_pct = maxi(best_pct, int(round(float(rc.get("pct", 0.0)) * 100.0)))
		lines.append(str(rc.get("text", "")))

	return {
		"lines": lines,
		"pct": best_pct,
		"hits": hits,
		"element": elem_id,
		"role": role_id,
	}


# ---------------------------------------------------------------- 编队报告

## 编队页唯一的数据出口：上阵列表 + 战力拆解 + 激活羁绊。
## 队伍总战力 = 卡牌基础战力（含装备属性）+ 羁绊加成带来的增量。
func formation_report(entries: Array) -> Dictionary:
	var units := roster_of(entries)
	var base := 0
	for u in units:
		base += battle_power(u["stats"])
	var active := active_synergies(units)
	apply_synergies(units)
	var total := 0
	for u in units:
		total += battle_power(u["stats"])
	return {
		"units": units,
		"count": units.size(),
		"base_power": base,
		"equip_power": 0,               # 装备系统未接入，先占住这条口径
		"synergy_power": total - base,
		"total_power": total,
		"synergies": active,
		"hint": synergy_hint(units),
	}


## 单张卡的编队语义：是否已上阵 / 在哪个槽位
func slot_of(entries: Array, char_id: String) -> int:
	for raw in entries:
		if raw is Dictionary and str(raw.get("char_id", "")) == char_id:
			return int(raw.get("slot", 0))
	return 0


## 按该英雄的推荐槽位找空位；推荐位被占则**先在推荐排里**找最近的空位，
## 再按 前排→中排→后排 兜底 —— 法师不该被塞到前排去挨打。
func free_slot_for(entries: Array, char_id: String) -> int:
	var used := {}
	for raw in entries:
		if raw is Dictionary:
			used[int(raw.get("slot", 0))] = true
	var prefer := int(GameDB.character(char_id).get("prefer_slot", 1))
	if prefer >= 1 and prefer <= 9 and not used.has(prefer):
		return prefer
	var rows: Array = GameDB.formation_section("team").get("row_order", ["front", "middle", "back"])
	var slots: Dictionary = GameDB.board().get("row_slots", {})
	var prefer_row := GameDB.row_of_slot(prefer)
	var ordered: Array = []
	if prefer_row != "":
		ordered.append(prefer_row)
	for row in rows:
		if str(row) != prefer_row:
			ordered.append(row)
	for row in ordered:
		var list: Array = slots.get(row, [])
		for v in list:
			if not used.has(int(v)):
				return int(v)
	for i in range(1, 10):
		if not used.has(i):
			return i
	return 0


# ---------------------------------------------------------------- 工具

func _count_in(units: Array, key: String, want: Variant) -> int:
	var n := 0
	for u in units:
		if str(u.get(key, "")) == str(want):
			n += 1
	return n


func _count_cfg_in(units: Array, field: String, wanted: Variant) -> int:
	var list := _as_array(wanted)
	if list.is_empty():
		return 0
	var n := 0
	for u in units:
		var cfg: Dictionary = u["config"]
		if str(cfg.get(field, "")) in list:
			n += 1
	return n


func _as_array(v: Variant) -> Array:
	if v is Array:
		return v
	if v == null:
		return []
	return [v]


## 全部英雄（编队卡库 / 图鉴的唯一入口）：逐个英雄造一份「编队条目」。
## 存档里没有这张卡时回落到配置的展演态（demo_level / demo_star），
## 编队是有卡就能排的，不该因为「还没抽到」而算不出属性。
func all_heroes() -> Array:
	var out: Array = []
	for raw in GameDB.characters():
		if not (raw is Dictionary):
			continue
		var cfg: Dictionary = raw
		var char_id := str(cfg.get("id", ""))
		if char_id == "":
			continue
		out.append(hero_item(char_id))
	return out


## 单个英雄的编队条目（编队卡库 / 主界面陈列 / 冒烟测试共用一份构造口径）
func hero_item(char_id: String) -> Dictionary:
	var cfg := GameDB.character(char_id)
	if cfg.is_empty():
		return {}
	var card := _card_or_demo(char_id, cfg)
	var stats := stats_of(card)
	return {
		"char_id": char_id,
		"config": cfg,
		"card": card,
		"stats": stats,
		"power": battle_power(stats),
	}


## 存档里有就用存档的，没有就按配置的展演态造一份（口径只此一处）
func _card_or_demo(char_id: String, cfg: Dictionary) -> Dictionary:
	var card := SaveDB.find_card(char_id)
	if not card.is_empty():
		return card
	return {
		"char_id": char_id,
		"level": int(cfg.get("demo_level", 1)),
		"star": int(cfg.get("demo_star", 1)),
		"exp": 0,
		"equipment": GameDB.blank_equipment(),
	}


## 主界面卡牌陈列：用配置里的 demo_lineup，按 demo_level / demo_star 造一份展演态
func showcase_lineup() -> Array:
	var by_id := {}
	for item in all_heroes():
		by_id[str(item["char_id"])] = item
	var out: Array = []
	for char_id in GameDB.menu().get("demo_lineup", []):
		if by_id.has(str(char_id)):
			out.append(by_id[str(char_id)])
	return out


## 主界面队伍预览条（3 × 3 的前三位）
func showcase_team() -> Array:
	var by_id := {}
	for item in showcase_lineup():
		by_id[item.char_id] = item
	var out: Array = []
	for char_id in GameDB.menu().get("demo_team_slots", []):
		if by_id.has(str(char_id)):
			out.append(by_id[str(char_id)])
	return out
