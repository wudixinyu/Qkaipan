extends Node
## GameDB —— 配置层（只读）
##
## 唯一职责：把 res://data/game_data.json 读进内存，并提供类型化的查询接口。
## 不持有任何玩家存档状态，不写盘。所有模块通过它读取策划配置。

const DATA_PATH := "res://data/game_data.json"

var data: Dictionary = {}
var loaded: bool = false


func _ready() -> void:
	load_data()


func load_data() -> bool:
	if not FileAccess.file_exists(DATA_PATH):
		push_error("[GameDB] 配置表不存在: %s" % DATA_PATH)
		return false
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		push_error("[GameDB] 无法打开配置表，错误码 %d" % FileAccess.get_open_error())
		return false
	var txt := f.get_as_text()
	f.close()

	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[GameDB] 配置表 JSON 解析失败")
		return false

	data = parsed
	loaded = true
	print("[GameDB] 配置载入完成 v%s：%d 张角色 / %d 个元素 / %d 个档位"
		% [version(), characters().size(), elements().size(), rarities().size()])
	return true


func version() -> String:
	return str(section("meta").get("version", data.get("version", "?")))


func section(key: String) -> Dictionary:
	var v: Variant = data.get(key, {})
	return v if typeof(v) == TYPE_DICTIONARY else {}


func meta() -> Dictionary:
	return section("meta")


# ---------------------------------------------------------------- 元素克制

func elements() -> Array:
	var out: Array = []
	var table: Dictionary = section("elements").get("table", {})
	for id in section("elements").get("order", []):
		if table.has(id):
			var e: Dictionary = table[id].duplicate()
			e["id"] = id
			out.append(e)
	return out


func element(id: String) -> Dictionary:
	var t: Dictionary = section("elements").get("table", {})
	return t.get(id, {})


func element_name(id: String) -> String:
	return str(element(id).get("name", "?"))


func element_color(id: String) -> Color:
	return Color(str(element(id).get("color", "#9E9E9E")))


func element_icon(id: String) -> String:
	return str(element(id).get("icon", ""))


## 属性克制是否成立：攻方 strong_against 命中守方即为克制（光暗互克由此天然成立）
func is_counter(attacker_elem: String, defender_elem: String) -> bool:
	if attacker_elem.is_empty() or defender_elem.is_empty():
		return false
	var strong: Variant = element(attacker_elem).get("strong_against", [])
	return strong is Array and defender_elem in strong


## 克制时返回 counter_damage_mult（125%），否则 1.0
func damage_multiplier(attacker_elem: String, defender_elem: String) -> float:
	var c := combat()
	return float(c.get("counter_damage_mult", 1.25)) if is_counter(attacker_elem, defender_elem) \
		else 1.0


## 克制时额外暴击率（+10%），否则 0
func crit_bonus(attacker_elem: String, defender_elem: String) -> float:
	var c := combat()
	return float(c.get("counter_crit_bonus", 0.10)) if is_counter(attacker_elem, defender_elem) \
		else 0.0


# ---------------------------------------------------------------- 战斗

func combat() -> Dictionary:
	return section("combat")


func board() -> Dictionary:
	return combat().get("board", {})


func row_of_slot(slot: int) -> String:
	var rs: Dictionary = board().get("row_slots", {})
	for row in ["front", "middle", "back"]:
		var slots: Array = rs.get(row, [])
		for v in slots:
			# JSON 里的数字可能被解析成 float，统一按整数比较
			if int(v) == slot:
				return row
	return ""


func row_name(row: String) -> String:
	return str(board().get("row_names", {}).get(row, row))


## 返回 [col, row]，row 0..2 为敌方（0=后排），3..5 为己方（3=前排）
func slot_cell(side: String, slot: int) -> Vector2i:
	var map: Dictionary = board().get("slot_to_cell", {}).get(side, {})
	var cell: Variant = map.get(str(slot), null)
	if cell is Array and cell.size() == 2:
		return Vector2i(int(cell[0]), int(cell[1]))
	return Vector2i.ZERO


# ---------------------------------------------------------------- 品质 / 角色

func rarities() -> Array:
	var out: Array = []
	var t: Dictionary = section("rarities").get("table", {})
	for id in section("rarities").get("order", []):
		if t.has(id):
			var r: Dictionary = t[id].duplicate()
			r["id"] = id
			out.append(r)
	return out


func rarity(id: String) -> Dictionary:
	var t: Dictionary = section("rarities").get("table", {})
	return t.get(id, {})


## 供 CardFan / CardView 整表注入使用的原始表
func rarity_table() -> Dictionary:
	return section("rarities").get("table", {})


func element_table() -> Dictionary:
	return section("elements").get("table", {})


func rarity_color(id: String) -> Color:
	return Color(str(rarity(id).get("color", "#FFFFFF")))


func rarity_frame(id: String) -> String:
	return str(rarity(id).get("frame", ""))


func rarity_inner_rect(id: String) -> Rect2:
	var v: Variant = rarity(id).get("inner_rect", [0.08, 0.08, 0.92, 0.92])
	if v is Array and v.size() == 4:
		return Rect2(v[0], v[1], v[2] - v[0], v[3] - v[1])
	return Rect2(0.08, 0.08, 0.84, 0.84)


func characters() -> Array:
	var v: Variant = data.get("characters", [])
	return v if v is Array else []


func character(id: String) -> Dictionary:
	for c in characters():
		if str(c.get("id", "")) == id:
			return c
	return {}


func role(id: String) -> Dictionary:
	var v: Variant = section("roles").get(id, {})
	return v if typeof(v) == TYPE_DICTIONARY else {}


# ---------------------------------------------------------------- 英雄图鉴
#
# codex 段承载「信息表」性质的内容：四大职业归类、每张卡的战斗定位 / 普攻 /
# 绝技 / 被动文案。战斗与养成只读 base / growth / skill，这一层纯展示。

func codex() -> Dictionary:
	return section("codex")


## 四大职业归类（front / dps / agile / support）
func class_matrix() -> Array:
	var v: Variant = codex().get("class_matrix", [])
	return v if v is Array else []


func class_of(role_id: String) -> String:
	return str(role(role_id).get("class", ""))


func class_name_of(role_id: String) -> String:
	var cid := class_of(role_id)
	for raw in class_matrix():
		if raw is Dictionary and str(raw.get("id", "")) == cid:
			return str(raw.get("name", cid))
	return cid


## 卡牌的图鉴信息块（battle_role / attack / ult / passive）
func codex_of(char_id: String) -> Dictionary:
	var v: Variant = character(char_id).get("codex", {})
	return v if typeof(v) == TYPE_DICTIONARY else {}


## 英雄名（依莲 / 莱恩 / 许知夏…）；配置里没写就回落到卡面名
func hero_name(char_id: String) -> String:
	var cfg := character(char_id)
	var hn := str(cfg.get("hero_name", ""))
	return hn if hn != "" else str(cfg.get("name", ""))


## 「卡面名 · 英雄名」的完整称呼；没有英雄名时不补分隔符
func full_name(char_id: String) -> String:
	var cfg := character(char_id)
	if cfg.is_empty():
		return char_id
	var nm := str(cfg.get("name", ""))
	var hn := str(cfg.get("hero_name", ""))
	return nm if hn == "" else "%s · %s" % [nm, hn]


## 卡牌的战斗定位（图鉴优先，缺配置时回落到职业战术文案）
func card_battle_role(char_id: String) -> String:
	var role_text := str(codex_of(char_id).get("battle_role", ""))
	if role_text != "":
		return role_text
	return battle_role_text(str(character(char_id).get("role", "")))


# ---------------------------------------------------------------- 养成 / 经济

func growth() -> Dictionary:
	return section("growth")


## 星级属性增幅表（growth.star_up.per_star_attr_bonus），索引 = 星级-1
func star_bonus_table() -> Array:
	var v: Variant = growth().get("star_up", {}).get("per_star_attr_bonus", [])
	return v if v is Array else []


func equipment_slot_count() -> int:
	return int(growth().get("equipment", {}).get("slot_count", 4))


## 账号等级曲线（growth.player_level）：胜利经验走这条线升级，与卡片升级无关
func player_level_cfg() -> Dictionary:
	return growth().get("player_level", {})


## 某一等级升到下一级所需经验：base + (level-1) × per_level
func player_exp_max(level: int) -> int:
	var c := player_level_cfg()
	var base := int(c.get("base_exp_max", 800))
	var per := int(c.get("exp_max_per_level", 200))
	return maxi(1, base + maxi(0, level - 1) * per)


## 账号等级上限与经验道具 id
func player_max_level() -> int:
	return int(player_level_cfg().get("max_level", 999))


func player_exp_item() -> String:
	return str(player_level_cfg().get("exp_item", "hero_exp"))


## 空白装备槽：长度恒为 slot_count，空槽写 ""（显式卸下语义）。
## 存档卡与演示卡都走这里，避免两种卡片结构不一致。
func blank_equipment() -> Array:
	var out: Array = []
	for i in equipment_slot_count():
		out.append("")
	return out


# ---------------------------------------------------------------- 抽卡（Gacha）
#
# 本段只做「读配置 + 归一化」：概率表、卡池内容、保底尺、单价。
# 掷点 / 保底推进 / 扣费 / 落盘都在 GachaSys（系统状态层），不在这里 ——
# 与其他系统同一分工：GameDB 只读配置，系统层持有状态。

func gacha() -> Dictionary:
	return section("gacha")


func gacha_pools() -> Array:
	var v: Variant = gacha().get("pools", [])
	return v if v is Array else []


func gacha_pool_ids() -> Array:
	var out: Array = []
	for raw in gacha_pools():
		if raw is Dictionary:
			out.append(str((raw as Dictionary).get("id", "")))
	return out


func gacha_pool(pool_id: String) -> Dictionary:
	for raw in gacha_pools():
		if raw is Dictionary and str((raw as Dictionary).get("id", "")) == pool_id:
			return raw
	return {}


## 品质阶序（R < SR < SSR < UR），索引即大小
func rarity_order() -> Array:
	var v: Variant = section("rarities").get("order", [])
	return v if v is Array else []


func rarity_rank(id: String) -> int:
	return rarity_order().find(id)


## a 是否不低于 b（未知品质一律视为最低）
func rarity_at_least(a: String, b: String) -> bool:
	return rarity_rank(a) >= rarity_rank(b)


## 概率表：只保留「概率 > 0」的品质，按品质阶序归一化到 1。
## 归一化是为了容错 —— 策划改表时就算漏加一边也还能跑，不会掷出越界区间。
func gacha_rates(pool_id: String) -> Dictionary:
	var raw: Variant = gacha_pool(pool_id).get("rates", {})
	var src: Dictionary = raw if raw is Dictionary else {}
	var total := 0.0
	var kept: Dictionary = {}
	for rid in rarity_order():
		var w := maxf(0.0, float(src.get(str(rid), 0.0)))
		if w <= 0.0:
			continue
		kept[str(rid)] = w
		total += w
	if total <= 0.0:
		return {}
	var out: Dictionary = {}
	for rid in kept.keys():
		out[rid] = float(kept[rid]) / total
	return out


## 某品质可出的内容。配置里**写了这个品质**（哪怕写成空数组）就以配置为准；
## 完全没写才回落成「自动收集同品质全部英雄」—— 以后加英雄不必回来改每张表。
func gacha_pool_entries(pool_id: String, rarity: String) -> Array:
	var raw: Variant = gacha_pool(pool_id).get("pool", {})
	var table: Dictionary = raw if raw is Dictionary else {}
	if table.has(rarity):
		var list: Variant = table.get(rarity, [])
		var out: Array = []
		if list is Array:
			for e in list:
				if e is Dictionary:
					out.append(e)
		return out
	var auto: Array = []
	for c in characters():
		if str(c.get("rarity", "")) == rarity:
			auto.append({"type": "hero", "id": str(c.get("id", "")), "weight": 1})
	return auto


## 是否有可出内容（空品质桶不参与掷点）
func gacha_pool_has(pool_id: String, rarity: String) -> bool:
	return not gacha_pool_entries(pool_id, rarity).is_empty()


## 当期 UP 英雄 id 列表；不传品质就返回全部
func gacha_up(pool_id: String, rarity: String = "") -> Array:
	var raw: Variant = gacha_pool(pool_id).get("up", {})
	var table: Dictionary = raw if raw is Dictionary else {}
	var out: Array = []
	if rarity != "":
		var list: Variant = table.get(rarity, [])
		return list if list is Array else []
	for rid in rarity_order():
		var l: Variant = table.get(str(rid), [])
		if l is Array:
			out.append_array(l)
	return out


func gacha_up_rate(pool_id: String) -> float:
	return clampf(float(gacha_pool(pool_id).get("up_rate", 0.5)), 0.0, 1.0)


func gacha_ticket(pool_id: String) -> Dictionary:
	var key := str(gacha_pool(pool_id).get("ticket", ""))
	if key == "":
		return {}
	var raw: Variant = gacha().get("tickets", {}).get(key, {})
	var t: Dictionary = raw if raw is Dictionary else {}
	if t.is_empty():
		return {}
	t["key"] = key
	return t


func gacha_gem_currency() -> String:
	return str(gacha().get("gem_currency", "bound_gem"))


## 归一化单价：候选支付方式按「券优先」排序，供界面与扣费共用一套口径。
## 返回 { "options": [{kind,id,name,icon,amount,currency}], "gem_currency": String }
func gacha_cost(pool_id: String) -> Dictionary:
	var pool := gacha_pool(pool_id)
	var raw: Variant = pool.get("cost", {})
	var cost: Dictionary = raw if raw is Dictionary else {}
	var single: Variant = cost.get("single", {})
	var ten: Variant = cost.get("ten", {})
	var options := {
		"single": _cost_options(pool_id, single, "single"),
		"ten": _cost_options(pool_id, ten, "ten"),
	}
	return {"options": options, "gem_currency": gacha_gem_currency()}


func _cost_options(pool_id: String, spec: Variant, key: String) -> Array:
	var out: Array = []
	var s: Dictionary = spec if spec is Dictionary else {}
	# 卡池自带 currency 形态（友情池：公会代币）—— 只有一种支付方式
	var cur := str(s.get("currency", ""))
	if cur != "":
		out.append(_cost_row("currency", cur, int(s.get("amount", 0))))
		return out

	var ticket := gacha_ticket(pool_id)
	var defaults: Dictionary = gacha().get("cost", {}).get(key, {})
	var n := int(s.get("ticket", defaults.get("ticket", 0)))
	if ticket.is_empty():
		ticket = _ticket_of_key(str(defaults.get("ticket_key", "basic")))
	if not ticket.is_empty() and n > 0:
		out.append(_cost_row("ticket", str(ticket.get("id", "")), n, ticket))
	var gem := int(s.get("gem", defaults.get("gem", 0)))
	if gem > 0:
		var cid := gacha_gem_currency()
		out.append(_cost_row("currency", cid, gem, currency(cid)))
	# 金币兜底档：券 / 钻石都不够时才轮到它（pay_order 里排最后）
	var gold := int(s.get("gold", defaults.get("gold", 0)))
	if gold > 0:
		out.append(_cost_row("currency", "gold", gold, currency("gold")))
	return out


func _ticket_of_key(key: String) -> Dictionary:
	var raw: Variant = gacha().get("tickets", {}).get(key, {})
	var t: Dictionary = raw if raw is Dictionary else {}
	if t.is_empty():
		return {}
	t["key"] = key
	return t


func _cost_row(kind: String, id: String, amount: int, info: Dictionary = {}) -> Dictionary:
	var row := { "kind": kind, "id": id, "amount": amount }
	if not info.is_empty():
		row["name"] = str(info.get("name", id))
		row["icon"] = str(info.get("icon", ""))
		row["color"] = str(info.get("color", "#FFFFFF"))
	else:
		var c := currency(id)
		row["name"] = str(c.get("name", id))
		row["icon"] = str(c.get("icon", ""))
		row["color"] = str(c.get("color", "#FFFFFF"))
	return row


func gacha_pity_group(pool_id: String) -> String:
	var g := str(gacha_pool(pool_id).get("pity_group", ""))
	return g if g != "" else pool_id


## 该池的保底尺：小保底 / 大保底是否启用、多少抽、保什么
func gacha_pity(pool_id: String) -> Dictionary:
	var raw: Variant = gacha_pool(pool_id).get("pity", {})
	var flags: Dictionary = raw if raw is Dictionary else {}
	var base: Dictionary = gacha().get("pity", {})
	var small: Dictionary = base.get("small", {})
	var large: Dictionary = base.get("large", {})
	return {
		"group": gacha_pity_group(pool_id),
		"small_on": bool(flags.get("small", true)),
		"large_on": bool(flags.get("large", false)),
		"inherit": bool(flags.get("inherit", false)),
		"small_count": maxi(1, int(small.get("count", 50))),
		"small_guarantee": str(small.get("guarantee", "SSR")),
		"small_desc": str(small.get("desc", "")),
		"large_count": maxi(1, int(large.get("count", 100))),
		"large_desc": str(large.get("desc", "")),
	}


func gacha_ten_guarantee() -> Dictionary:
	var raw: Variant = gacha().get("ten_guarantee", {})
	return raw if raw is Dictionary else {}


## 十连保底的品质：从配置想要的品质往下找，
## 概率表里要有它、卡池也要真能出**人物卡**（只堆道具的品质不算），否则退到下一个更低的品质。
func gacha_ten_guarantee_rarity(pool_id: String) -> String:
	var want := str(gacha_ten_guarantee().get("rarity", "SR"))
	var rates := gacha_rates(pool_id)
	var order := rarity_order()
	var idx := maxi(0, order.find(want))
	for i in range(idx, -1, -1):
		var rid := str(order[i])
		if rates.has(rid) and gacha_pool_has_hero(pool_id, rid):
			return rid
	return ""


## 某品质能否出人物卡（卡池里该品质含 type==hero 的内容）
func gacha_pool_has_hero(pool_id: String, rarity: String) -> bool:
	for e in gacha_pool_entries(pool_id, rarity):
		if str((e as Dictionary).get("type", "hero")) == "hero":
			return true
	return false


## 十连「至少一张人物卡」的保底品质：只要卡池里真有人物可出，
## 就从最低品质往上第一个含人物的品质 —— 不要求品质，只要求是一张人物卡。
func gacha_hero_floor_rarity(pool_id: String) -> String:
	for raw in rarity_order():
		var rid := str(raw)
		if gacha_pool_has_hero(pool_id, rid):
			return rid
	return ""


func gacha_crystal() -> Dictionary:
	var raw: Variant = gacha().get("crystal", {})
	return raw if raw is Dictionary else {}


func gacha_reveal() -> Dictionary:
	var raw: Variant = gacha().get("reveal", {})
	return raw if raw is Dictionary else {}


func gacha_shop() -> Dictionary:
	var raw: Variant = gacha().get("shop", {})
	return raw if raw is Dictionary else {}


func gacha_new_player_gift() -> Dictionary:
	var raw: Variant = gacha().get("new_player_gift", {})
	return raw if raw is Dictionary else {}


func gacha_history_max() -> int:
	return maxi(0, int(gacha().get("history_max", 30)))


## 概率公示文案（界面「概率公示」弹层逐条展示）
func gacha_rate_notice() -> Array:
	var v: Variant = gacha().get("rate_notice", [])
	return v if v is Array else []


func stamina_cfg() -> Dictionary:
	return section("stamina")


func economy() -> Dictionary:
	return section("economy")


func currency(id: String) -> Dictionary:
	var v: Variant = section("economy").get("currencies", {}).get(id, {})
	return v if typeof(v) == TYPE_DICTIONARY else {}


func mode_entries() -> Array:
	var v: Variant = data.get("modes", [])
	return v if v is Array else []


func menu() -> Dictionary:
	return section("menu")


# ---------------------------------------------------------------- 冒险关卡地图

func adventure() -> Dictionary:
	return section("adventure")


## 选关页（冒险关卡选择）地图配置
func select_map() -> Dictionary:
	var v: Variant = adventure().get("select_map", {})
	return v if typeof(v) == TYPE_DICTIONARY else {}


## 全部关卡节点：优先按小节聚合（sections 为唯一渲染源），
## 无小节数据时回落到旧的扁平 nodes。
func stage_nodes() -> Array:
	var secs := sections()
	if not secs.is_empty():
		var out: Array = []
		for raw in secs:
			if raw is Dictionary:
				out.append_array(section_nodes(str((raw as Dictionary).get("id", ""))))
		return out
	var v: Variant = select_map().get("nodes", [])
	return v if v is Array else []


## 小节列表（select_map.sections）：每节 {id,label,name,chapter_id,stage_ids,gate_stage_id,nodes}
## chapter_id 为空返回全部小节（跨章聚合口径，供 stage_nodes / 布局校验用），
## 指定章时只回该章小节（供选关页按当前章铺小节页签 / 子地图）。
func sections(chapter_id: String = "") -> Array:
	var v: Variant = select_map().get("sections", [])
	if not (v is Array):
		return []
	if chapter_id == "":
		return v
	var out: Array = []
	for raw in v:
		if raw is Dictionary and str((raw as Dictionary).get("chapter_id", "")) == chapter_id:
			out.append(raw)
	return out


## 该章是否有小节地图数据（章节切换栏据此区分「待接入」与「可玩/未解锁」）
func chapter_has_map(chapter_id: String) -> bool:
	return not sections(chapter_id).is_empty()


## 按 id 取某一小节配置（与上方通用 section(key) 区分，故命名 section_cfg）
func section_cfg(section_id: String) -> Dictionary:
	for raw in sections():
		if raw is Dictionary and str(raw.get("id", "")) == section_id:
			return raw
	return {}


## 小节 id 顺序表（chapter_id 为空返回全部小节 id，指定章时只回该章）
func section_order(chapter_id: String = "") -> Array:
	var out: Array = []
	for raw in sections(chapter_id):
		if raw is Dictionary:
			out.append(str(raw.get("id", "")))
	return out


## 某小节的节点列表
func section_nodes(section_id: String) -> Array:
	var v: Variant = section_cfg(section_id).get("nodes", [])
	return v if v is Array else []


## 某小节的守关关 id（通关它即解锁下一小节）
func section_gate_stage(section_id: String) -> int:
	return int(section_cfg(section_id).get("gate_stage_id", 0))


## 关卡属于哪个小节 id（遍历各节 stage_ids）
func stage_section_id(stage_id: int) -> String:
	for raw in sections():
		if not (raw is Dictionary):
			continue
		for sid in (raw as Dictionary).get("stage_ids", []):
			if int(sid) == stage_id:
				return str((raw as Dictionary).get("id", ""))
	return ""


## 某小节内的引导线：[[pre, cur], ...]，仅两端都属该节者计入
func section_links(section_id: String) -> Array:
	var ids := {}
	for sid in section_cfg(section_id).get("stage_ids", []):
		ids[int(sid)] = true
	var out: Array = []
	for raw in section_nodes(section_id):
		if not (raw is Dictionary):
			continue
		var pre := int(raw.get("pre_stage_id", 0))
		if pre > 0 and ids.has(pre):
			out.append([pre, int(raw.get("stage_id", 0))])
	return out


func stage_node(stage_id: int) -> Dictionary:
	for raw in stage_nodes():
		if raw is Dictionary and int(raw.get("stage_id", 0)) == stage_id:
			return raw
	return {}


## 节点锚点：配置按 1920x1080 视口像素记录，这里直接给出 Vector2 供 UI 使用
func stage_node_pos(stage_id: int) -> Vector2:
	var node := stage_node(stage_id)
	var p: Variant = node.get("pos", [])
	if p is Array and p.size() == 2:
		return Vector2(float(p[0]), float(p[1]))
	return Vector2.ZERO


## 选关页引导线：[[前置关卡, 关卡], ...]，由各节点的 pre_stage_id 推导
func stage_links() -> Array:
	var out: Array = []
	for raw in stage_nodes():
		if raw is Dictionary:
			var pre := int(raw.get("pre_stage_id", 0))
			if pre > 0:
				out.append([pre, int(raw.get("stage_id", 0))])
	return out


## 章节列表（adventure.chapters）：[{id, name, stages, ...}, ...]
func chapters() -> Array:
	var v: Variant = adventure().get("chapters", [])
	return v if v is Array else []


## 当前选关页所属章节 id（select_map.chapter_id）
func current_chapter_id() -> String:
	return str(select_map().get("chapter_id", ""))


## 顶部章节切换栏配置（select_map.chapter_tabs.items）：
## [{id, label, name, locked}, ...]。locked 缺省时按「是否当前章」推导。
func chapter_tabs() -> Array:
	var items: Variant = select_map().get("chapter_tabs", {}).get("items", [])
	if not (items is Array):
		return []
	var cur := current_chapter_id()
	var out: Array = []
	for raw in items:
		if not (raw is Dictionary):
			continue
		var tab: Dictionary = raw
		if not tab.has("locked"):
			tab["locked"] = str(tab.get("id", "")) != cur
		out.append(tab)
	return out


func decor_islands() -> Array:
	var v: Variant = select_map().get("decor_islands", [])
	return v if v is Array else []


func enter_button() -> Dictionary:
	var v: Variant = select_map().get("enter_button", {})
	return v if typeof(v) == TYPE_DICTIONARY else {}


## 关卡类型 id（battle / elite / event）-> 中文名
func stage_kind_name(kind_id: String) -> String:
	for raw in adventure().get("stage_kinds", []):
		if raw is Dictionary and str(raw.get("id", "")) == kind_id:
			return str(raw.get("name", kind_id))
	return kind_id


# ---------------------------------------------------------------- 关卡星级

## 星级评定配置（adventure.star_rating）。规则表由策划改，代码只负责判定
func star_rating() -> Dictionary:
	var v: Variant = adventure().get("star_rating", {})
	return v if typeof(v) == TYPE_DICTIONARY else {}


## 满星数，缺省 3
func star_max() -> int:
	return maxi(1, int(star_rating().get("max", 3)))


func star_rules() -> Array:
	var v: Variant = star_rating().get("rules", [])
	return v if v is Array else []


func star_label(key: String, fallback: String = "") -> String:
	var labels: Variant = star_rating().get("labels", {})
	if labels is Dictionary:
		return str(labels.get(key, fallback))
	return fallback


# ---------------------------------------------------------------- 第一章关卡表（战斗用）

## 第一章《云上浮岛·初始之痕》全 10 关
func chapter_stages_section() -> Dictionary:
	var v: Variant = adventure().get("chapter_stages", {})
	return v if typeof(v) == TYPE_DICTIONARY else {}


func chapter_stages() -> Array:
	# 跨章聚合：第一章 chapter_stages.list + 其余章 extra_chapter_stages[].list。
	# chapter_stage(id) 因此能跨章命中，战斗/奖励/敌方单位等下游代码无需再改。
	var out: Array = []
	var v: Variant = chapter_stages_section().get("list", [])
	if v is Array:
		out.append_array(v)
	var ex: Variant = adventure().get("extra_chapter_stages", [])
	if ex is Array:
		for raw in ex:
			if raw is Dictionary:
				var l: Variant = (raw as Dictionary).get("list", [])
				if l is Array:
					out.append_array(l)
	return out


## 某章的关卡块（ch1 取 chapter_stages，其余取 extra_chapter_stages）
func chapter_block(chapter_id: String) -> Dictionary:
	if chapter_id == str(chapter_stages_section().get("chapter_id", "ch1")):
		return chapter_stages_section()
	var ex: Variant = adventure().get("extra_chapter_stages", [])
	if ex is Array:
		for raw in ex:
			if raw is Dictionary and str((raw as Dictionary).get("chapter_id", "")) == chapter_id:
				return raw
	return {}


func chapter_stage(stage_id: int) -> Dictionary:
	for raw in chapter_stages():
		if raw is Dictionary and int(raw.get("id", 0)) == stage_id:
			return raw
	return {}


func chapter_title() -> String:
	return str(chapter_stages_section().get("title", adventure().get("chapters", [{}])[0].get("name", "")))


## 该关是不是战斗关（非战斗节点：祭坛 / 喷泉 这类进不了战场）
func stage_is_battle(stage_id: int) -> bool:
	var s := chapter_stage(stage_id)
	if s.is_empty():
		return false
	var kind := str(s.get("kind", "battle"))
	return kind != "event" and kind != "rest"


## 每关体力以关卡自身为准，缺省才回落到 adventure.stamina_per_stage
func stage_stamina(stage_id: int) -> int:
	var s := chapter_stage(stage_id)
	if s.has("stamina"):
		return int(s.get("stamina", 0))
	var node := stage_node(stage_id)
	if node.has("stamina"):
		return int(node.get("stamina", 0))
	return int(adventure().get("stamina_per_stage", 6))


func stage_recommend_power(stage_id: int) -> int:
	var s := chapter_stage(stage_id)
	if s.has("recommend_power"):
		return int(s.get("recommend_power", 0))
	return int(stage_node(stage_id).get("recommend_power", 0))


## 关卡设定的名字：优先关卡表，其次选关页节点（选关页只有 3 个节点有锚点）
func stage_display_name(stage_id: int) -> String:
	var s := chapter_stage(stage_id)
	if not s.is_empty():
		return str(s.get("name", ""))
	return str(stage_node(stage_id).get("name", "关卡 %d" % stage_id))


# ---------------------------------------------------------------- 敌方单位

func monster_table() -> Dictionary:
	var v: Variant = data.get("monsters", {}).get("table", {})
	return v if typeof(v) == TYPE_DICTIONARY else {}


func monster_order() -> Array:
	var v: Variant = data.get("monsters", {}).get("order", [])
	return v if v is Array else []


func monster(id: String) -> Dictionary:
	var t := monster_table()
	var v: Variant = t.get(id, {})
	return v if typeof(v) == TYPE_DICTIONARY else {}


func monster_icon(id: String) -> String:
	return str(monster(id).get("icon", ""))


# ---------------------------------------------------------------- 战场布局

func battle_cfg() -> Dictionary:
	var v: Variant = combat().get("battle", {})
	return v if typeof(v) == TYPE_DICTIONARY else {}


func battle_atb() -> Dictionary:
	var v: Variant = combat().get("atb", {})
	return v if typeof(v) == TYPE_DICTIONARY else {}


# ---------------------------------------------------------------- 卡牌选择与编队
#
# 段里只有**规则与文案**：上阵上限、职业克制表、羁绊条件与效果、按钮文字。
# 像素级布局常量在 tools/build_formation.gd 里，与其他界面同一口径。

func formation() -> Dictionary:
	return section("formation")


func formation_section(key: String) -> Dictionary:
	var v: Variant = formation().get(key, {})
	return v if typeof(v) == TYPE_DICTIONARY else {}


func formation_list(key: String) -> Array:
	var v: Variant = formation().get(key, [])
	return v if v is Array else []


func formation_text(key: String, fallback: String = "") -> String:
	return str(formation().get(key, fallback))


## 队伍上阵「绝对上限」（= 棋盘格数 = 解锁封顶）。
## 注意：这不是玩家当前能上阵的人数 —— 后者随等级解锁，走 SaveDB.team_max()。
func team_max() -> int:
	return maxi(1, int(formation_section("team").get("max_members", 9)))


## 上阵解锁规则（写在 formation.team.unlock）：
##   base 起步人数、interval 每多少级 +1、max 封顶、level_cap 玩家等级上限。
func team_unlock() -> Dictionary:
	return formation_section("team").get("unlock", {})


## 按玩家等级算「当前可上阵人数」：base + level/interval，夹在 [base, max] 之间。
## 纯函数 —— 不读存档，等级由调用方（SaveDB.team_max）传入，保持 GameDB 无状态。
func team_max_for_level(level: int) -> int:
	var u := team_unlock()
	var base := maxi(1, int(u.get("base", 1)))
	var interval := maxi(1, int(u.get("interval", 10)))
	var cap := maxi(base, int(u.get("max", team_max())))
	var n := base + int(maxi(0, level)) / interval
	return clampi(n, base, cap)


## 解锁下一格上阵位所需的玩家等级（当前上限 +1 时）；已满封顶返回 0。
func team_unlock_next_level(level: int) -> int:
	var u := team_unlock()
	var interval := maxi(1, int(u.get("interval", 10)))
	if team_max_for_level(level) >= team_max_for_level(int(u.get("level_cap", 100))):
		return 0
	return (int(level) / interval + 1) * interval


func formation_scene() -> String:
	## 编队页是「选关 → 战斗」之间的准备界面；场景路径写在这里而不是散在各页里
	return str(formation().get("scene", "res://scenes/formation.tscn"))


## 体力在哪一步扣：formation（编队页确认选择）/ stage_select（选关页进入关卡）
func spend_stamina_at() -> String:
	var v := str(formation().get("spend_stamina_at", "formation"))
	return v if v != "" else "formation"


func status_max() -> int:
	## 棋盘槽位数（9），上阵上限与它不是一个概念：槽位多、能上阵的人少
	return maxi(1, int(formation_section("team").get("columns", 3))) * 3


func synergies() -> Array:
	return formation_list("synergies")


func role_counters() -> Array:
	return formation_list("role_counters")


func role_chain() -> Array:
	return formation_list("role_chain")


func role_tactic(role_id: String) -> Dictionary:
	var v: Variant = formation_section("role_tactics").get(role_id, {})
	return v if typeof(v) == TYPE_DICTIONARY else {}


## 「战斗定位」文案：位置 + 职责，缺配置时回落到职业自身描述
func battle_role_text(role_id: String) -> String:
	var t := role_tactic(role_id)
	var sep := str(formation_section("tactical").get("role_sep", " / "))
	var position := str(t.get("position", ""))
	var duty := str(t.get("duty", ""))
	if position == "" and duty == "":
		return str(role(role_id).get("desc", ""))
	if duty == "":
		return position
	return "%s%s%s" % [position, sep, duty]


func presets() -> Array:
	return formation_list("presets")


func preset_cfg(preset_id: String) -> Dictionary:
	for raw in presets():
		var p: Dictionary = raw
		if str(p.get("id", "")) == preset_id:
			return p
	return {}


func sort_options() -> Array:
	return formation_list("sorts")


func filter_groups() -> Array:
	return formation_section("filters").get("groups", [])


## 关卡敌方构成：编队页的克制提示与「一键上阵」都读这一份，不各自解析关卡表
func stage_enemy_units(stage_id: int) -> Array:
	var out: Array = []
	for raw in chapter_stage(stage_id).get("enemies", []):
		var e: Dictionary = raw
		var mob_id := str(e.get("mob", ""))
		var m := monster(mob_id)
		if m.is_empty():
			continue
		var slot := int(e.get("slot", 1))
		out.append({
			"mob_id": mob_id,
			"name": str(m.get("name", mob_id)),
			"element": str(m.get("element", "")),
			"role": str(m.get("role", "")),
			"slot": slot,
			"row": row_of_slot(slot),
			"icon": str(m.get("icon", "")),
		})
	return out


## 敌方构成汇总：{ "elements": {id: n}, "roles": {id: n}, "rows": {row: n} }
func stage_enemy_comp(stage_id: int) -> Dictionary:
	var comp := {"elements": {}, "roles": {}, "rows": {}}
	for u in stage_enemy_units(stage_id):
		for pair in [["elements", "element"], ["roles", "role"], ["rows", "row"]]:
			var bucket := str(pair[0])
			var key := str(u.get(pair[1], ""))
			if key == "":
				continue
			var table: Dictionary = comp[bucket]
			table[key] = int(table.get(key, 0)) + 1
	return comp
