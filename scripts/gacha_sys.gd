extends Node
## GachaSys —— 抽卡系统（召唤）
##
## 唯一职责：一次抽卡的全部结算 —— 掷品质 / 同品质内选内容 / 保底推进 /
## 扣费 / 发卡发道具 / 累积心愿水晶 / 招募商店兑换。
## 所有数值都读 GameDB 的配置（概率表、保底尺、单价、UP 名单），本文件不写死规则。
##
## 两个刻意的设计：
##   1. **关键决策都是纯函数**：随机数从外面传进来（pick_rarity / choose_entry），
##      所以「概率边界」「UP 占 50%」「保底在第几抽触发」都能脱离随机性被验证；
##   2. **pull() 支持 free 模式**：不扣费、不入账、不落盘，只把保底在本地副本上推进。
##      跑两万次只看分布，不会写爆存档，也不会污染真实保底计数。
##
## 保底继承：计数存在 SaveDB 的 pity_group 分组里，不跟卡池 id 绑定 ——
## 限时池换期后新卡池用同一个 group，计数继续累计，即「跨期全额继承」。

signal pulled(pool_id: String, result: Dictionary)
signal exchanged(pool_id: String, char_id: String, result: Dictionary)

const REASON_NORMAL := "normal"
const REASON_SMALL_PITY := "small_pity"
const REASON_UP_PITY := "up_pity"
const REASON_TEN := "ten_guarantee"

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


# ---------------------------------------------------------------- 查询

func pool_ids() -> Array:
	return GameDB.gacha_pool_ids()


func pools() -> Array:
	return GameDB.gacha_pools()


func pool(pool_id: String) -> Dictionary:
	return GameDB.gacha_pool(pool_id)


func rates(pool_id: String) -> Dictionary:
	return GameDB.gacha_rates(pool_id)


func crystal_currency() -> String:
	return str(GameDB.gacha_crystal().get("currency", "wish_crystal"))


func crystals() -> int:
	return SaveDB.balance(crystal_currency())


func crystals_per_pull() -> int:
	return int(GameDB.gacha_crystal().get("per_pull", 1))


## 当期头条 UP 英雄：取品质最高的那一位（大保底必出的就是它）
func up_hero(pool_id: String) -> String:
	var best := ""
	for raw in GameDB.gacha_up(pool_id):
		var id := str(raw)
		var cfg := GameDB.character(id)
		if cfg.is_empty():
			continue
		if best == "" or GameDB.rarity_rank(str(cfg.get("rarity", ""))) \
				> GameDB.rarity_rank(str(GameDB.character(best).get("rarity", ""))):
			best = id
	return best


## 保底可视化：还差几抽必出（差 0 表示这一抽就保底）
func pity_state(pool_id: String) -> Dictionary:
	var cfg := GameDB.gacha_pity(pool_id)
	var group := str(cfg.get("group", pool_id))
	var entry := SaveDB.pity_of(group)
	var small_max := int(cfg.get("small_count", 50))
	var large_max := int(cfg.get("large_count", 100))
	var small := int(entry.get("small", 0))
	var large := int(entry.get("large", 0))
	return {
		"group": group,
		"small": small, "large": large,
		"small_max": small_max, "large_max": large_max,
		"small_on": bool(cfg.get("small_on", true)),
		"large_on": bool(cfg.get("large_on", false)),
		"small_left": maxi(0, small_max - small),
		"large_left": maxi(0, large_max - large),
		"small_guarantee": str(cfg.get("small_guarantee", "SSR")),
		"small_desc": str(cfg.get("small_desc", "")),
		"large_desc": str(cfg.get("large_desc", "")),
		"inherit": bool(cfg.get("inherit", false)),
	}


## 持有量：券 / 道具在材料仓，其余在钱包
func owned_of(kind: String, id: String) -> int:
	if kind == "currency":
		return SaveDB.balance(id)
	return SaveDB.material_count(id)


## 本次抽卡要花什么、花不花得起。options 按「券优先」排列，option 是自动选中的一种。
func cost(pool_id: String, count: int) -> Dictionary:
	var size := "ten" if count >= 10 else "single"
	var raw: Variant = GameDB.gacha_cost(pool_id).get("options", {})
	var table: Dictionary = raw if raw is Dictionary else {}
	var list: Variant = table.get(size, [])
	var options: Array = []
	var chosen: Dictionary = {}
	for e in (list if list is Array else []):
		if not (e is Dictionary):
			continue
		var row: Dictionary = (e as Dictionary).duplicate()
		row["size"] = size
		row["owned"] = owned_of(str(row.get("kind", "")), str(row.get("id", "")))
		row["enough"] = int(row["owned"]) >= int(row.get("amount", 0))
		options.append(row)
		if chosen.is_empty() and bool(row["enough"]):
			chosen = row
	return {
		"pool_id": pool_id, "count": count, "size": size,
		"options": options, "option": chosen,
		"affordable": not chosen.is_empty(),
	}


## 概率公示行：每个品质一行，带该品质可出的内容与公示概率
func rate_rows(pool_id: String) -> Array:
	var rates := GameDB.gacha_rates(pool_id)
	var out: Array = []
	for raw in GameDB.rarity_order():
		var rid := str(raw)
		var p := float(rates.get(rid, 0.0))
		if p <= 0.0:
			continue
		var names: Array = []
		for e in GameDB.gacha_pool_entries(pool_id, rid):
			var ed: Dictionary = e
			var id := str(ed.get("id", ""))
			if str(ed.get("type", "hero")) == "hero":
				names.append(str(GameDB.character(id).get("name", id)))
			else:
				names.append("%s ×%d" % [str(ed.get("name", id)), int(ed.get("count", 1))])
		var r := GameDB.rarity(rid)
		out.append({
			"rarity": rid, "name": str(r.get("name", rid)),
			"color": str(r.get("color", "#FFFFFF")), "rate": p,
			"percent": p * 100.0, "contents": names,
			"up": GameDB.gacha_up(pool_id, rid).size() > 0,
		})
	return out


## 招募商店可兑换内容：优先当期 UP，没有 UP 就退到该池全部 UR / SSR
func exchange_options(pool_id: String) -> Array:
	var crystal := GameDB.gacha_crystal()
	var costs: Dictionary = crystal.get("exchange_cost", {})
	var ids: Array = GameDB.gacha_up(pool_id)
	if ids.is_empty():
		for rid in ["UR", "SSR"]:
			for e in GameDB.gacha_pool_entries(pool_id, str(rid)):
				var ed: Dictionary = e
				if str(ed.get("type", "hero")) == "hero":
					ids.append(str(ed.get("id", "")))
	var out: Array = []
	for raw in ids:
		var id := str(raw)
		var cfg := GameDB.character(id)
		if cfg.is_empty():
			continue
		var rarity := str(cfg.get("rarity", "R"))
		var need := int(costs.get(rarity, 0))
		if need <= 0:
			continue
		var owned := SaveDB.balance(crystal_currency())
		out.append({
			"char_id": id, "name": str(cfg.get("name", id)), "rarity": rarity,
			"config": cfg, "cost": need, "owned": owned,
			"affordable": owned >= need and need > 0,
			"is_new": SaveDB.find_card(id).is_empty(),
			"up": id in GameDB.gacha_up(pool_id),
		})
	return out


## 「最近获得」条：最近的英雄抽取（跳过道具），最新在前
func recent_heroes(limit: int = 4) -> Array:
	return SaveDB.recent_heroes(limit)


# ---------------------------------------------------------------- 抽取

## 抽卡。count 支持 1 与 10（其余一律按最近的档位取价）。
## opts:
##   "free": true      只模拟不落盘（不扣费 / 不发卡 / 不写档），保底只在本地副本上推进
##   "seed": int       固定随机种子，用来复现某次结果
##   "use_pity": true  是否走保底规则；给 false 就是「纯基础概率」（校验分布用）
func pull(pool_id: String, count: int = 1, opts: Dictionary = {}) -> Dictionary:
	var free := bool(opts.get("free", false))
	var use_pity := bool(opts.get("use_pity", true))
	if opts.has("seed"):
		_rng.seed = int(opts["seed"])
	if GameDB.gacha_pool(pool_id).is_empty():
		return _fail(pool_id, "未知卡池：%s" % pool_id)

	var n := 10 if count >= 10 else maxi(1, count)
	var pay: Dictionary = {}
	if not free:
		var c := cost(pool_id, n)
		if not bool(c.get("affordable", false)):
			var r := _fail(pool_id, _lack_text(c))
			r["cost"] = c
			return r
		pay = c["option"]

	var pity_cfg := GameDB.gacha_pity(pool_id)
	var group := str(pity_cfg.get("group", pool_id))
	var saved := SaveDB.pity_of(group)
	var p_small := int(saved.get("small", 0))
	var p_large := int(saved.get("large", 0))
	var small_max := int(pity_cfg.get("small_count", 50))
	var large_max := int(pity_cfg.get("large_count", 100))
	var small_on := bool(pity_cfg.get("small_on", true))
	var large_on := bool(pity_cfg.get("large_on", false))
	var small_need := str(pity_cfg.get("small_guarantee", "SSR"))

	var guarantee := GameDB.gacha_ten_guarantee_rarity(pool_id)
	var ten_ok := false
	var items: Array = []
	var best := ""

	for i in n:
		var want_min := ""
		var force_up := ""
		var reason := REASON_NORMAL
		if use_pity and large_on and p_large + 1 >= large_max:
			# 大保底：压过一切，直接给当期头条 UP
			force_up = up_hero(pool_id)
			if force_up != "":
				reason = REASON_UP_PITY
		if use_pity and force_up == "" and small_on and p_small + 1 >= small_max:
			want_min = small_need
			reason = REASON_SMALL_PITY
		if use_pity and force_up == "" and want_min == "" and n >= 10 and i == n - 1 \
				and guarantee != "" and not ten_ok:
			# 十连保底：抽到最后一抽还没有 SR 及以上，这一抽兜底
			want_min = guarantee
			reason = REASON_TEN

		var item := _roll(pool_id, want_min, force_up, reason)
		if item.is_empty():
			continue
		items.append(item)
		var rarity := str(item.get("rarity", ""))
		if best == "" or GameDB.rarity_rank(rarity) > GameDB.rarity_rank(best):
			best = rarity

		# —— 保底推进（use_pity=false 时整段冻结，这样分布断言拿到的就是纯基础概率）——
		if not use_pity:
			continue
		if GameDB.rarity_at_least(rarity, small_need):
			p_small = 0
		else:
			p_small += 1
		if guarantee != "" and GameDB.rarity_at_least(rarity, guarantee):
			ten_ok = true
		if bool(item.get("is_up", false)):
			p_large = 0
		else:
			p_large += 1

	var result := {
		"ok": true, "reason": "", "pool_id": pool_id, "count": items.size(),
		"free": free, "pay": pay, "items": items,
		"max_rarity": best,
		"has_ur": best != "" and GameDB.rarity_at_least(best, "UR"),
		"has_ssr": best != "" and GameDB.rarity_at_least(best, "SSR"),
		"has_up": _any_up(items),
		"crystals": 0,
		"pity_before": { "small": int(saved.get("small", 0)), "large": int(saved.get("large", 0)) },
		# free 模式的 pity_after 是「如果真抽了会变成多少」，没有落盘（pity_persisted=false）
		"pity_after": { "small": p_small, "large": p_large },
		"pity_persisted": not free,
	}

	if free:
		_simulate_items(items)
		return result

	# —— 入账：一次抽卡只落一次盘 ——
	_pay(pay)
	for it in items:
		_apply_item(it)
	SaveDB.record_pulls(pool_id, n)
	SaveDB.set_pity(group, p_small, p_large)
	var gained := crystals_per_pull() * n
	if gained != 0:
		SaveDB.add_currency(crystal_currency(), gained, false)
		result["crystals"] = gained
	for it in items:
		var row: Dictionary = it
		if str(row.get("char_id", "")) == "":
			continue
		SaveDB.push_gacha_history({
			"pool": pool_id, "char_id": str(row["char_id"]),
			"rarity": str(row.get("rarity", "")), "star": int(row.get("star", 1)),
			"up": bool(row.get("is_up", false)), "at": _now(),
		})
	SaveDB.save_profile()

	pulled.emit(pool_id, result)
	return result


## 招募商店兑换：花心愿水晶指定换当期 UP 英雄
func exchange(pool_id: String, char_id: String) -> Dictionary:
	var row := _exchange_row(pool_id, char_id)
	if row.is_empty():
		return { "ok": false, "reason": "「%s」不在本期兑换名单内" % char_id, "char_id": char_id }
	var cur := crystal_currency()
	var need := int(row["cost"])
	if SaveDB.balance(cur) < need:
		return { "ok": false, "reason": "心愿水晶不足：%d / %d" % [SaveDB.balance(cur), need],
			"char_id": char_id, "cost": need }
	SaveDB.add_currency(cur, -need, false)
	var existed := not SaveDB.find_card(char_id).is_empty()
	var card := SaveDB.grant_card(char_id, false)
	SaveDB.record_exchange(char_id)
	SaveDB.push_gacha_history({
		"pool": pool_id, "char_id": char_id, "rarity": str(row["rarity"]),
		"star": int(card.get("star", 1)), "up": true, "exchange": true, "at": _now(),
	})
	SaveDB.save_profile()

	var result := {
		"ok": true, "reason": "", "char_id": char_id, "cost": need,
		"crystal": crystal_currency(), "balance": SaveDB.balance(cur),
		"is_new": not existed, "card": card, "rarity": str(row["rarity"]),
		"config": GameDB.character(char_id),
		"stats": RealmDB.stats_of(card),
	}
	exchanged.emit(pool_id, char_id, result)
	return result


func _exchange_row(pool_id: String, char_id: String) -> Dictionary:
	for row in exchange_options(pool_id):
		var r: Dictionary = row
		if str(r.get("char_id", "")) == char_id:
			return r
	return {}


# ---------------------------------------------------------------- 纯函数（可测）
#
# 这两个函数是整套概率规则的判定核心：随机数由参数给入，所以「边界值给谁」
# 可以在测试里逐点断言，而不是靠跑一万次去猜。

## 掷品质。valid 里为 false 的品质不参与（该品质在卡池里没有任何内容）。
## min_rarity 非空时只在「不低于它」的品质里按原比例重新归一 —— 保底就是这么实现的。
func pick_rarity(rates: Dictionary, valid: Dictionary, min_rarity: String, roll: float) -> String:
	var kept: Array = []
	var total := 0.0
	for raw in GameDB.rarity_order():
		var rid := str(raw)
		if not bool(valid.get(rid, false)):
			continue
		if min_rarity != "" and not GameDB.rarity_at_least(rid, min_rarity):
			continue
		var w := float(rates.get(rid, 0.0))
		if w <= 0.0:
			continue
		kept.append([rid, w])
		total += w
	if kept.is_empty() or total <= 0.0:
		return ""
	var t := clampf(roll, 0.0, 0.999999) * total
	var acc := 0.0
	for pair in kept:
		acc += float(pair[1])
		if t < acc:
			return str(pair[0])
	return str(kept[kept.size() - 1][0])


## 同品质内选内容：先按 up_rate 决定走 UP 组还是其余内容，再在组内按权重选。
## 返回 { entry, from_up, degrade }；degrade 表示「除 UP 外没有别的内容」这种内容量不足的退化。
func choose_entry(entries: Array, up_ids: Array, up_rate: float, branch_roll: float,
		pick_roll: float) -> Dictionary:
	var up_entries: Array = []
	var rest: Array = []
	for raw in entries:
		if not (raw is Dictionary):
			continue
		var e: Dictionary = raw
		if str(e.get("id", "")) in up_ids:
			up_entries.append(e)
		else:
			rest.append(e)
	var ratio := clampf(up_rate, 0.0, 1.0)
	if not up_entries.is_empty() and branch_roll < ratio:
		return { "entry": _weighted_pick(up_entries, pick_roll), "from_up": true, "degrade": false }
	if rest.is_empty():
		# 该品质只有 UP 英雄可出：分配规则照常执行，只是两边落回同一位英雄
		if not up_entries.is_empty():
			return { "entry": _weighted_pick(up_entries, pick_roll), "from_up": true, "degrade": true }
		return {}
	return { "entry": _weighted_pick(rest, pick_roll), "from_up": false, "degrade": false }


func _weighted_pick(entries: Array, roll: float) -> Dictionary:
	if entries.is_empty():
		return {}
	var total := 0.0
	for raw in entries:
		total += maxf(0.0, float((raw as Dictionary).get("weight", 1.0)))
	if total <= 0.0:
		return entries[0]
	var t := clampf(roll, 0.0, 0.999999) * total
	var acc := 0.0
	for raw in entries:
		acc += maxf(0.0, float((raw as Dictionary).get("weight", 1.0)))
		if t < acc:
			return raw
	return entries[entries.size() - 1]


# ---------------------------------------------------------------- 内部：掷一次

func _roll(pool_id: String, want_min: String, force_up: String, reason: String) -> Dictionary:
	if force_up != "" and not GameDB.character(force_up).is_empty():
		return _make_item(pool_id, { "type": "hero", "id": force_up },
			str(GameDB.character(force_up).get("rarity", "")), true, reason)
	var rates := GameDB.gacha_rates(pool_id)
	if rates.is_empty():
		return {}
	var valid: Dictionary = {}
	for rid in rates.keys():
		valid[str(rid)] = GameDB.gacha_pool_has(pool_id, str(rid))
	var rarity := pick_rarity(rates, valid, want_min, _rng.randf())
	if rarity == "":
		return {}
	var entries := GameDB.gacha_pool_entries(pool_id, rarity)
	var pick := choose_entry(entries, GameDB.gacha_up(pool_id, rarity),
		GameDB.gacha_up_rate(pool_id), _rng.randf(), _rng.randf())
	if pick.is_empty():
		return {}
	var entry: Dictionary = pick.get("entry", {})
	return _make_item(pool_id, entry, rarity, bool(pick.get("from_up", false)), reason)


func _make_item(pool_id: String, entry: Dictionary, rarity: String,
		from_up: bool, reason: String) -> Dictionary:
	var kind := str(entry.get("type", "hero"))
	var id := str(entry.get("id", ""))
	if id == "":
		return {}
	var item := {
		"kind": kind, "id": id, "rarity": rarity,
		"is_up": from_up, "reason": reason,
		"is_pity": reason != REASON_NORMAL,
		"is_small_pity": reason == REASON_SMALL_PITY,
		"is_up_pity": reason == REASON_UP_PITY,
		"is_ten_guarantee": reason == REASON_TEN,
		"pool_id": pool_id,
	}
	if kind == "hero":
		var cfg := GameDB.character(id)
		if cfg.is_empty():
			return {}
		var demo := _demo_card(id, cfg)
		item["char_id"] = id
		item["name"] = str(cfg.get("name", id))
		item["rarity"] = str(cfg.get("rarity", rarity))
		item["config"] = cfg
		item["card"] = demo
		item["stats"] = RealmDB.stats_of(demo)
		item["is_new"] = SaveDB.find_card(id).is_empty()
		item["star_up"] = false
	else:
		item["char_id"] = ""
		item["name"] = str(entry.get("name", id))
		item["count"] = maxi(1, int(entry.get("count", 1)))
		item["icon"] = str(entry.get("icon", ""))
		item["owned"] = SaveDB.material_count(id)
	return item


## free 模式下的卡状态：不写档，用配置的展演态算一份，保证界面数据结构一致
func _demo_card(char_id: String, cfg: Dictionary) -> Dictionary:
	return {
		"char_id": char_id,
		"level": int(cfg.get("demo_level", 1)),
		"star": int(cfg.get("demo_star", 1)),
		"exp": 0,
		"equipment": GameDB.blank_equipment(),
	}


## free 模式：只把「抽到了什么」算成 will-be 状态，不动存档
func _simulate_items(items: Array) -> void:
	for raw in items:
		var it: Dictionary = raw
		it["owned"] = SaveDB.material_count(str(it.get("id", ""))) if str(it.get("kind", "")) == "item" else 0


## 真发：英雄走 grant_card（重复即升星，星级封顶由存档层钳制），道具走材料仓
func _apply_item(raw: Variant) -> void:
	var it: Dictionary = raw
	if str(it.get("kind", "")) == "hero":
		var char_id := str(it.get("char_id", ""))
		var before := SaveDB.find_card(char_id)
		var before_star := int(before.get("star", 0)) if not before.is_empty() else 0
		var card := SaveDB.grant_card(char_id, false)
		it["card"] = card
		it["stats"] = RealmDB.stats_of(card)
		it["level"] = int(card.get("level", 1))
		it["star"] = int(card.get("star", 1))
		it["is_new"] = before.is_empty()
		it["star_up"] = (not before.is_empty()) and int(card.get("star", 1)) > before_star
	else:
		var res := SaveDB.grant_reward(str(it.get("id", "")), int(it.get("count", 1)), false)
		it["owned"] = int(res.get("owned", 0))


func _pay(row: Dictionary) -> void:
	if row.is_empty():
		return
	var amount := int(row.get("amount", 0))
	if amount <= 0:
		return
	if str(row.get("kind", "")) == "currency":
		SaveDB.add_currency(str(row.get("id", "")), -amount, false)
	else:
		SaveDB.spend_material(str(row.get("id", "")), amount, false)


func _any_up(items: Array) -> bool:
	for raw in items:
		if raw is Dictionary and bool((raw as Dictionary).get("is_up", false)):
			return true
	return false


func _lack_text(c: Dictionary) -> String:
	var parts: Array = []
	for e in c.get("options", []):
		var row: Dictionary = e
		parts.append("%s %d/%d" % [str(row.get("name", row.get("id", ""))),
			int(row.get("owned", 0)), int(row.get("amount", 0))])
	if parts.is_empty():
		return "没有可用的支付方式"
	return "资源不足：" + "，".join(parts)


func _fail(pool_id: String, reason: String) -> Dictionary:
	return { "ok": false, "reason": reason, "pool_id": pool_id, "count": 0, "items": [],
		"max_rarity": "", "has_ur": false, "has_ssr": false, "has_up": false, "crystals": 0 }


func _now() -> int:
	return int(Time.get_unix_time_from_system())
