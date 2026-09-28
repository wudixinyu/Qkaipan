extends Node
## SaveDB —— 存档层
##
## 唯一职责：把玩家存档读写到 user://save.json。
## 任何模块要持久化，都必须通过这里，不允许各自开文件。
##
## 约定：
##   - 装备槽位始终写满 slot_count 个，空槽写 ""（显式卸下），加载时 "" 不回退默认值
##   - 缺失字段用默认值补齐，不做静默覆盖已有字段

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1

signal saved()
signal loaded()

var profile: Dictionary = {}


func _ready() -> void:
	load_profile()


# ---------------------------------------------------------------- 默认存档

func _default_profile() -> Dictionary:
	var p: Dictionary = GameDB.menu().get("player", {})
	var wallet := {
		"gem": int(p.get("gem", 0)),
		"gold": int(p.get("gold", 0)),
		"bound_gem": 0,
		"arena_token": 0,
		"guild_token": 0,
		"wish_crystal": 0,   # 心愿水晶：抽卡积分，招募商店用它兑换当期 UP
	}
	var items := _new_player_items()
	# 新号赠送：货币进钱包、道具进材料仓 —— 与战斗奖励同一套路由规则
	for id in GameDB.gacha_new_player_gift().keys():
		var n := int(GameDB.gacha_new_player_gift()[id])
		if n <= 0:
			continue
		var key := str(id)
		if not GameDB.currency(key).is_empty():
			wallet[key] = int(wallet.get(key, 0)) + n
		else:
			items[key] = int(items.get(key, 0)) + n
	return {
		"version": SAVE_VERSION,
		"player": {
			"name": str(p.get("name", "云上旅人")),
			"level": int(p.get("level", 1)),
			"exp": int(p.get("exp", 0)),
			"exp_max": int(p.get("exp_max", 800)),
			"avatar": "res://assets/art/characters/char_knight.png",
		},
		"wallet": wallet,
		"stamina": {
			"value": int(p.get("stamina", GameDB.stamina_cfg().get("max", 60))),
			# 上次结算时刻（unix 秒）；为 0 表示从未结算，首次进入按满值处理
			"accounted_at": 0,
		},
		"cards": [],           # [{ "char_id", "level", "star", "exp", "equipment": [String x slot_count] }] 新号默认无卡，卡片全部靠抽卡 / 兑换获得
		"team": [],            # [{ "slot": int, "char_id": String }] 出战编队，只由编队页写
		"team_presets": _default_presets(),   # 阵容预设：pid -> 条目数组（主线队 / PVP队 / 副本队）
		"team_active_preset": _default_active_preset(),
		"progress": {
			"chapter": "ch1",
			"cleared_stages": 0,
			"unlocked_modes": ["tower"],
			"stage_clears": {},   # str(stage_id) -> 通关次数
			"stage_stars": {},    # str(stage_id) -> 历史最佳星级（只升不降）
			"pending_items": items,  # 材料仓：材料 / 道具 id -> 累计件数（背包做好前先记这里）
			"stats": {            # 累计统计，结算时同步更新
				"battles": 0,
				"wins": 0,
				"stars_total": 0,
				"materials_total": 0,
			},
		},
		"gacha": _default_gacha(),
		"settings": { "music": 0.7, "sfx": 0.8 },
	}


## 材料仓初始内容：召唤券这类开局道具由 gacha.new_player_gift 决定，
## 这里只保证「券有地方放」，具体数额不写死在代码里。
func _new_player_items() -> Dictionary:
	return {}


## 新号初始卡：按「默认无卡」的口径返回空表。
## 名单曾取自 menu.demo_team_slots（主界面展演队），现在抽卡才是唯一入卡渠道：
## 十连保底保证第一波抽取必得人物卡，所以这里可以放心留空。
## 保留函数是为了给测试与旧脚本一个「清档回默认态」的统一入口。
func _starter_cards() -> Array:
	return []


func _default_gacha() -> Dictionary:
	# pity 按 pity_group 分组存放：限时池换代后同组计数继续累计 = 跨期全额继承
	return {
		"total_pulls": 0,
		"pulls_by_pool": {},   # pool_id -> 累计抽数
		"pity": {},            # pity_group -> { small, large }
		"history": [],         # 最近 N 条：{ pool, char_id, rarity, star, at }
		"exchanges": {},       # char_id -> 招募商店兑换次数
	}


## 用默认值补齐缺失键（递归，不覆盖已存在的键）
func _fill_defaults(target: Dictionary, defaults: Dictionary) -> void:
	for k in defaults.keys():
		if not target.has(k):
			target[k] = defaults[k]
		elif typeof(target[k]) == TYPE_DICTIONARY and typeof(defaults[k]) == TYPE_DICTIONARY:
			_fill_defaults(target[k], defaults[k])


# ---------------------------------------------------------------- 阵容预设

## 预设由配置驱动：formation.presets 里的 id / name / seed
func _default_presets() -> Dictionary:
	var out := {}
	for raw in GameDB.formation_list("presets"):
		var p: Dictionary = raw
		var pid := str(p.get("id", ""))
		if pid == "":
			continue
		out[pid] = _seed_entries(pid)
	return out


func _default_active_preset() -> String:
	var list: Array = GameDB.formation_list("presets")
	if list.is_empty():
		return ""
	return str(list[0].get("id", ""))


## 预设的初始阵容：把 seed 里的 hero_id 换成 { slot, char_id }
func _seed_entries(preset_id: String) -> Array:
	var out: Array = []
	for raw in GameDB.preset_cfg(preset_id).get("seed", []):
		var char_id := str(raw)
		var cfg := GameDB.character(char_id)
		if cfg.is_empty():
			continue
		out.append({"slot": int(cfg.get("prefer_slot", 1)), "char_id": char_id})
	return out


# ---------------------------------------------------------------- 读写

func load_profile() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		var parsed: Variant = null
		if f != null:
			parsed = JSON.parse_string(f.get_as_text())
			f.close()
		if typeof(parsed) == TYPE_DICTIONARY:
			profile = parsed
			_fill_defaults(profile, _default_profile())
			_normalize_cards()
			_migrate_gacha()
			print("[SaveDB] 存档已载入：%s Lv.%d，持卡 %d 张"
				% [profile.player.name, profile.player.level, profile.cards.size()])
			loaded.emit()
			return

	profile = _default_profile()
	save_profile()
	print("[SaveDB] 未找到存档，已创建默认存档")


func save_profile() -> void:
	profile["version"] = SAVE_VERSION
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("[SaveDB] 存档写入失败，错误码 %d" % FileAccess.get_open_error())
		return
	f.store_string(JSON.stringify(profile, "\t"))
	f.close()
	saved.emit()


func reset_profile() -> void:
	profile = _default_profile()
	save_profile()


## 装备槽位必须写满，空槽用 "" 表示显式卸下
func _normalize_cards() -> void:
	var slot_count := GameDB.equipment_slot_count()
	for c in profile.get("cards", []):
		var eq: Variant = c.get("equipment", [])
		var fixed: Array = []
		for i in slot_count:
			fixed.append(str(eq[i]) if eq is Array and i < eq.size() else "")
		c["equipment"] = fixed


## 旧档的保底计数是一份全局值（pity_small / pity_large），没有分组概念。
## 按策划案把它归到「限时池」那一组 —— 卡池换代时计数继续往累计，即跨期继承。
## 迁移只做一次：搬完就把旧键删掉，之后 count 归各池自己的 pity_group 管。
func _migrate_gacha() -> void:
	var table := gacha_state()
	var legacy_small := int(table.get("pity_small", 0))
	var legacy_large := int(table.get("pity_large", 0))
	var pity: Variant = table.get("pity", {})
	var groups: Dictionary = pity if pity is Dictionary else {}
	if groups.is_empty() and (legacy_small > 0 or legacy_large > 0):
		groups["limited"] = { "small": legacy_small, "large": legacy_large }
	table["pity"] = groups
	table.erase("pity_small")
	table.erase("pity_large")


# ---------------------------------------------------------------- 便捷访问

func wallet() -> Dictionary:
	return profile.get("wallet", {})


func balance(currency_id: String) -> int:
	return int(wallet().get(currency_id, 0))


func add_currency(currency_id: String, amount: int, save: bool = true) -> void:
	var w := wallet()
	w[currency_id] = max(0, int(w.get(currency_id, 0)) + amount)
	if save:
		save_profile()


func spend_currency(currency_id: String, amount: int) -> bool:
	if balance(currency_id) < amount:
		return false
	add_currency(currency_id, -amount)
	return true


func cards() -> Array:
	return profile.get("cards", [])


func find_card(char_id: String) -> Dictionary:
	for c in cards():
		if str(c.get("char_id", "")) == char_id:
			return c
	return {}


## 发一张新卡（已有则升星到该品质上限），返回卡状态。
##
## 新卡的初始星级取 rarities[rarity].star_default（品质的初始星级），
## 不取角色的 demo_star —— demo_star 是主界面展演阵容的展示星级，
## 改展演视觉效果不该连带改掉抽卡的实际产出。
##
## save=false 供批量发放用（抽卡十连）：先全部入账，最后统一落一次盘。
func grant_card(char_id: String, save: bool = true) -> Dictionary:
	var cfg := GameDB.character(char_id)
	if cfg.is_empty():
		return {}
	var rarity_id := str(cfg.get("rarity", "R"))
	var rarity_cfg := GameDB.rarity(rarity_id)
	var cap := maxi(1, int(rarity_cfg.get("star_max", 1)))
	var existing := find_card(char_id)
	if not existing.is_empty():
		# 星级封顶：重复卡只升到该品质的 star_max，属性不会被滚成无上限
		existing["star"] = mini(cap, int(existing.get("star", 1)) + 1)
		if save:
			save_profile()
		return existing

	profile.cards.append({
		"char_id": char_id,
		"level": 1,
		"star": clampi(int(rarity_cfg.get("star_default", 1)), 1, cap),
		"exp": 0,
		"equipment": GameDB.blank_equipment(),
	})
	if save:
		save_profile()
	return profile.cards.back()


# ---------------------------------------------------------------- 编队
#
# 三条硬规则（3.1 上阵规则）：上限 team_max()、同名 hero_id 不可重复、槽位必须是 1..9。
# 任何写档路径都先过 normalize_team()，保证存档里永远不会出现非法编队。

func team() -> Array:
	return profile.get("team", [])


## 解析「当前该展示的出战编队」：存档 team 优先，空档回落到当前预设。
## 编队页与主界面共用这一份口径，保证两处永远显示同一批英雄（含新号）。
func resolved_team() -> Array:
	var t: Array = team()
	if not t.is_empty():
		return normalize_team(t)
	return normalize_team(preset_entries(active_preset()))


func team_max() -> int:
	return GameDB.team_max()


## 规范化：丢非法槽位 / 同名去重 / 槽位去重 / 按上限截断 / 按槽位排序
func normalize_team(entries: Array) -> Array:
	var out: Array = []
	var seen_id := {}
	var seen_slot := {}
	for raw in entries:
		if not (raw is Dictionary):
			continue
		var e: Dictionary = raw
		var char_id := str(e.get("char_id", ""))
		var slot := int(e.get("slot", 0))
		if char_id == "" or GameDB.character(char_id).is_empty():
			continue
		if slot < 1 or slot > 9:
			continue
		if seen_id.has(char_id) or seen_slot.has(slot):
			continue
		seen_id[char_id] = true
		seen_slot[slot] = true
		out.append({"slot": slot, "char_id": char_id})
	out.sort_custom(func(a, b): return int(a["slot"]) < int(b["slot"]))
	if out.size() > team_max():
		out = out.slice(0, team_max())
	return out


## 人类可读的编队校验错误；空数组 = 合法
func team_errors(entries: Array) -> Array:
	var errs: Array = []
	var max_n := team_max()
	if entries.size() > max_n:
		errs.append("上阵超过 %d 人" % max_n)
	var seen_id := {}
	var seen_slot := {}
	for raw in entries:
		if not (raw is Dictionary):
			errs.append("编队条目格式非法")
			continue
		var e: Dictionary = raw
		var char_id := str(e.get("char_id", ""))
		var slot := int(e.get("slot", 0))
		if slot < 1 or slot > 9:
			errs.append("槽位 %d 越界（合法 1-9）" % slot)
		if char_id == "" or GameDB.character(char_id).is_empty():
			errs.append("未知英雄 %s" % char_id)
		if seen_id.has(char_id):
			errs.append("%s 重复上阵" % char_id)
		if seen_slot.has(slot):
			errs.append("槽位 %d 重复占用" % slot)
		seen_id[char_id] = true
		seen_slot[slot] = true
	return errs


## 写入出战编队，返回落盘后的条目（已被规范化）
func set_team(entries: Array) -> Array:
	var fixed := normalize_team(entries)
	profile["team"] = fixed
	save_profile()
	return fixed


# ---------------------------------------------------------------- 阵容预设

func team_presets() -> Dictionary:
	var v: Variant = profile.get("team_presets", {})
	if typeof(v) != TYPE_DICTIONARY:
		profile["team_presets"] = _default_presets()
	return profile["team_presets"]


func active_preset() -> String:
	var pid := str(profile.get("team_active_preset", ""))
	if pid == "":
		pid = _default_active_preset()
		profile["team_active_preset"] = pid
	return pid


func preset_entries(preset_id: String) -> Array:
	var table := team_presets()
	var v: Variant = table.get(preset_id, [])
	if v is Array and not (v as Array).is_empty():
		return normalize_team(v)
	return _seed_entries(preset_id)


## 把当前编队存进某个预设栏位
func save_preset(preset_id: String, entries: Array) -> Array:
	var fixed := normalize_team(entries)
	team_presets()[preset_id] = fixed
	profile["team_active_preset"] = preset_id
	save_profile()
	return fixed


## 切到某个预设：把它载入出战编队并记为当前预设。
##
## 注意：这里**不**顺手保存旧预设 —— 编队页的工作副本只在它自己手里，
## SaveDB 看不到，硬存只会用旧的 profile.team 覆盖掉玩家刚编好的阵容。
## 所以「先存旧、再载新」由调用方（formation.gd）负责，两步都显式写。
func switch_preset(target_id: String) -> Array:
	profile["team_active_preset"] = target_id
	var entries := preset_entries(target_id)
	profile["team"] = entries
	save_profile()
	return entries


## 兼容旧入口：只切当前预设标记 + 载入（不做「存回旧预设」）
func load_preset(preset_id: String) -> Array:
	return switch_preset(preset_id)


# ---------------------------------------------------------------- 关卡进度

func progress() -> Dictionary:
	if typeof(profile.get("progress")) != TYPE_DICTIONARY:
		profile["progress"] = {}
	return profile["progress"]


## 关卡历史最佳星级（0 = 还没打过 / 未评级）
func stage_stars(stage_id: int) -> int:
	var stars: Variant = progress().get("stage_stars", {})
	if stars is Dictionary:
		return int(stars.get(str(stage_id), 0))
	return 0


## 记录星级：**只升不降**，返回 true 表示刷新了最佳战绩。
## 结算时无论打成什么样都要走这里 —— 打得更差不会把地图上的星星擦掉。
func record_stage_stars(stage_id: int, stars: int) -> bool:
	var p := progress()
	var table: Dictionary = {}
	var raw: Variant = p.get("stage_stars", {})
	if raw is Dictionary:
		table = raw
	var old := int(table.get(str(stage_id), 0))
	if stars <= old:
		return false
	table[str(stage_id)] = stars
	p["stage_stars"] = table
	save_profile()
	return true


func stage_clears_table() -> Dictionary:
	var table: Variant = progress().get("stage_clears", {})
	return table if table is Dictionary else {}


func stage_clear_count(stage_id: int) -> int:
	return int(stage_clears_table().get(str(stage_id), 0))


# ---------------------------------------------------------------- 材料仓

## 材料 / 道具仓：非货币奖励全部落在这里（背包系统还没做，至少不丢账）
func materials() -> Dictionary:
	var v: Variant = progress().get("pending_items", {})
	return v if typeof(v) == TYPE_DICTIONARY else {}


func material_count(item_id: String) -> int:
	return int(materials().get(item_id, 0))


## 材料入账，返回入账后的持有量
func add_material(item_id: String, count: int, save: bool = true) -> int:
	var p := progress()
	var table := materials()
	table[item_id] = maxi(0, int(table.get(item_id, 0)) + count)
	p["pending_items"] = table
	if save:
		save_profile()
	return int(table[item_id])


## 材料扣减：与 add_material 严格对称，不足则不扣、返回 false
func spend_material(item_id: String, count: int, save: bool = true) -> bool:
	if count <= 0:
		return true
	if material_count(item_id) < count:
		return false
	add_material(item_id, -count, save)
	return true


## 统一发放入口：货币走钱包、其余走材料仓 —— 与战斗结算的奖励路由同一条规则。
## 返回 { id, count, owned, kind }，owned 是入账后的持有量。
func grant_reward(item_id: String, count: int, save: bool = true) -> Dictionary:
	if not GameDB.currency(item_id).is_empty():
		add_currency(item_id, count, save)
		return {
			"id": item_id, "count": count, "kind": "currency",
			"owned": balance(item_id),
		}
	var owned := add_material(item_id, count, save)
	return { "id": item_id, "count": count, "kind": "material", "owned": owned }


## 材料仓概览：{ kinds 种类数, total 总件数 } —— 结算面板与选关页的「物资」统计口径
func material_tally() -> Dictionary:
	var kinds := 0
	var total := 0
	for id in materials().keys():
		var n := int(materials()[id])
		if n <= 0:
			continue
		kinds += 1
		total += n
	return {"kinds": kinds, "total": total}


# ---------------------------------------------------------------- 抽卡状态
#
# 只存「状态」，不存规则：概率表 / 保底尺 / 单价全在 GameDB 的配置里，
# 掷点与结算在 GachaSys。这里负责让这些状态安全落盘。
#
# 保底计数按 pity_group 分组 —— 限时池换代后新卡池用同一个 group，
# 计数自然继续累计，这就是策划案里的「跨期全额继承」。

func gacha_state() -> Dictionary:
	var raw: Variant = profile.get("gacha", {})
	if typeof(raw) != TYPE_DICTIONARY:
		profile["gacha"] = _default_gacha()
	var t: Dictionary = profile["gacha"]
	for k in ["total_pulls", "pulls_by_pool", "pity", "history", "exchanges"]:
		if not t.has(k):
			match k:
				"total_pulls":
					t[k] = 0
				"history":
					t[k] = []
				_:
					t[k] = {}
	return t


## 某个保底分组的计数（不存在则建零）
func pity_of(group: String) -> Dictionary:
	var table := gacha_state()
	var pity: Variant = table.get("pity", {})
	var groups: Dictionary = pity if pity is Dictionary else {}
	var entry: Variant = groups.get(group, null)
	if typeof(entry) != TYPE_DICTIONARY:
		entry = { "small": 0, "large": 0 }
		groups[group] = entry
	table["pity"] = groups
	return entry


## 写回保底计数（不落盘，由调用方统一 save_profile）
func set_pity(group: String, small: int, large: int) -> void:
	var e := pity_of(group)
	e["small"] = maxi(0, small)
	e["large"] = maxi(0, large)


func total_pulls() -> int:
	return int(gacha_state().get("total_pulls", 0))


func pulls_of(pool_id: String) -> int:
	var v: Variant = gacha_state().get("pulls_by_pool", {}).get(pool_id, 0)
	return int(v)


## 记一笔抽数（分池 + 总账），不落盘
func record_pulls(pool_id: String, count: int) -> void:
	if count <= 0:
		return
	var t := gacha_state()
	t["total_pulls"] = int(t.get("total_pulls", 0)) + count
	var by: Variant = t.get("pulls_by_pool", {})
	var table: Dictionary = by if by is Dictionary else {}
	table[pool_id] = int(table.get(pool_id, 0)) + count
	t["pulls_by_pool"] = table


## 招募记录：只留最近 history_max 条，避免存档无限膨胀
func push_gacha_history(entry: Dictionary) -> void:
	var t := gacha_state()
	var list: Variant = t.get("history", [])
	var arr: Array = list if list is Array else []
	arr.append(entry.duplicate())
	var cap := GameDB.gacha_history_max()
	if cap > 0 and arr.size() > cap:
		arr = arr.slice(arr.size() - cap, arr.size())
	t["history"] = arr


func gacha_history() -> Array:
	var v: Variant = gacha_state().get("history", [])
	return v if v is Array else []


## 最近抽取的英雄（跳过道具），供界面做「最近获得」条
func recent_heroes(limit: int = 4) -> Array:
	var out: Array = []
	var list := gacha_history()
	for i in range(list.size() - 1, -1, -1):
		var raw: Variant = list[i]
		if not (raw is Dictionary):
			continue
		var e: Dictionary = raw
		if str(e.get("char_id", "")) == "":
			continue
		out.append(e)
		if out.size() >= limit:
			break
	return out


## 招募商店兑换计数（统计用）
func count_exchange(char_id: String) -> int:
	var v: Variant = gacha_state().get("exchanges", {}).get(char_id, 0)
	return int(v)


func record_exchange(char_id: String) -> void:
	var t := gacha_state()
	var raw: Variant = t.get("exchanges", {})
	var table: Dictionary = raw if raw is Dictionary else {}
	table[char_id] = int(table.get(char_id, 0)) + 1
	t["exchanges"] = table


# ---------------------------------------------------------------- 累计统计

func stats() -> Dictionary:
	var v: Variant = progress().get("stats", {})
	if v is Dictionary:
		return v
	progress()["stats"] = {}
	return progress()["stats"]


## 累加统计项（结算时按场次累加：battles / wins / stars_total / materials_total）
func add_stats(delta: Dictionary) -> void:
	var s := stats()
	for k in delta.keys():
		s[str(k)] = int(s.get(str(k), 0)) + int(delta[k])
	save_profile()


func stat(key: String) -> int:
	return int(stats().get(key, 0))

