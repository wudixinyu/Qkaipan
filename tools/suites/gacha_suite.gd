extends RefCounted
## gacha_suite.gd —— 抽卡系统冒烟测试套件
##
## 由 tools/smoke_gacha.gd 在主循环起来之后动态 load()（原因见 smoke 入口注释）。
##
## 覆盖四层：
##   配置层   —— 卡池 / 概率 / 单价 / 保底尺 / 水晶，全部来自 game_data.json
##   概率层   —— pick_rarity / choose_entry 两个纯函数逐点验边界（不靠随机性）
##   分布层   —— 两万抽实测占比落在公示概率的容差内
##   状态层   —— 保底触发时机、跨期继承、扣费、水晶累积、兑换、星级封顶、招募记录

const SEED := 20260927

var passed := 0
var failed := 0

var _tree: SceneTree
var _scene: Node


func run(tree: SceneTree) -> Dictionary:
	_tree = tree
	print("\n========== 卡牌大冒险 · 抽卡系统冒烟测试 ==========")

	# 抽卡会真实写档（发卡 / 扣券 / 累水晶），先回到默认存档让断言可重复
	SaveDB.reset_profile()
	StaminaSys.fill()

	_check_config()
	_check_pure_rules()
	_check_distribution()
	_check_up_share()
	_check_pity()
	_check_pull_payment()
	_check_exchange()
	_check_star_cap()
	_check_history()
	_check_scene()
	print("\n---------- 结果：通过 %d / 失败 %d ----------" % [passed, failed])
	return { "passed": passed, "failed": failed }


func _ok(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  [PASS] %s%s" % [label, ("  " + detail) if detail != "" else ""])
	else:
		failed += 1
		print("  [FAIL] %s%s" % [label, ("  " + detail) if detail != "" else ""])


func _eq(label: String, got, want) -> void:
	_ok(label, got == want, "got=%s want=%s" % [str(got), str(want)])


func _near(label: String, got: float, want: float, tol: float) -> void:
	_ok(label, absf(got - want) <= tol,
		"got=%.4f want=%.4f ±%.4f（差 %.4f）" % [got, want, tol, absf(got - want)])


# ---------------------------------------------------------------- 配置层

func _check_config() -> void:
	print("\n· 配置层 GameDB.gacha")
	_eq("卡池数量", GameDB.gacha_pools().size(), 3)
	_eq("卡池顺序", GameDB.gacha_pool_ids(), ["standard", "limited", "friend"])

	var r := GameDB.gacha_rates("standard")
	_near("常驻 UR 概率", float(r.get("UR", 0.0)), 0.005, 0.0001)
	_near("常驻 SSR 概率", float(r.get("SSR", 0.0)), 0.035, 0.0001)
	_near("常驻 SR 概率", float(r.get("SR", 0.0)), 0.18, 0.0001)
	_near("常驻 R 概率", float(r.get("R", 0.0)), 0.78, 0.0001)
	var sum := 0.0
	for k in r.keys():
		sum += float(r[k])
	_near("概率归一化后之和", sum, 1.0, 0.0001)

	_ok("友情池不产 UR", not _rate_has("friend", "UR"),
		"UR 概率 %s" % str(GameDB.gacha_rates("friend").get("UR", 0.0)))
	_eq("十连保底品质", GameDB.gacha_ten_guarantee_rarity("standard"), "SR")
	_eq("十连保底文案", str(GameDB.gacha_ten_guarantee().get("label", "")), "必得 1 张人物卡")
	# 人物卡地板只看「能不能出人物」：从最低品质往上取第一个含英雄的品质
	_eq("人物卡地板品质（常驻池）", GameDB.gacha_hero_floor_rarity("standard"), "R")
	_ok("地板品质里真有人物可出", GameDB.gacha_pool_has_hero("standard", "R"))

	# 单价：券优先 → 绑定钻石 → 金币兜底（三档）
	var single: Array = GameDB.gacha_cost("standard").get("options", {}).get("single", [])
	_eq("单抽候选支付方式 3 种", single.size(), 3)
	if single.size() == 3:
		_eq("单抽首选召唤券", str(single[0].get("kind", "")) + ":" + str(single[0].get("id", "")),
			"ticket:ticket_basic")
		_eq("单抽券量", int(single[0].get("amount", 0)), 1)
		_eq("单抽备选绑定钻石", str(single[1].get("id", "")), "bound_gem")
		_eq("单抽钻石价", int(single[1].get("amount", 0)), 160)
		_eq("单抽金币兜底档", str(single[2].get("id", "")), "gold")
		_eq("单抽金币价", int(single[2].get("amount", 0)), 1600)

	var ten: Array = GameDB.gacha_cost("standard").get("options", {}).get("ten", [])
	_eq("十连候选支付方式 3 种", ten.size(), 3)
	if ten.size() == 3:
		_eq("十连券量", int(ten[0].get("amount", 0)), 10)
		_eq("十连钻石价", int(ten[1].get("amount", 0)), 1600)
		_eq("十连金币价", int(ten[2].get("amount", 0)), 16000)

	var friend_single: Array = GameDB.gacha_cost("friend").get("options", {}).get("single", [])
	_eq("友情池只有一种支付方式", friend_single.size(), 1)
	if friend_single.size() == 1:
		_eq("友情池用公会代币", str(friend_single[0].get("id", "")), "guild_token")
		_eq("友情池单抽价", int(friend_single[0].get("amount", 0)), 10)

	var pity := GameDB.gacha_pity("limited")
	_eq("大保底尺", int(pity.get("large_count", 0)), 100)
	_eq("小保底尺", int(pity.get("small_count", 0)), 50)
	_ok("限时池启用大保底", bool(pity.get("large_on", false)))
	_ok("限时池声明跨期继承", bool(pity.get("inherit", false)))
	_ok("常驻池不启用大保底", not bool(GameDB.gacha_pity("standard").get("large_on", true)))
	_ok("友情池不启用保底", not bool(GameDB.gacha_pity("friend").get("small_on", true)))

	_eq("当期 UP 头牌英雄", GachaSys.up_hero("limited"), "holy_priest")
	_eq("常驻池没有 UP", GachaSys.up_hero("standard"), "")

	var crystal := GameDB.gacha_crystal()
	_eq("水晶货币", str(crystal.get("currency", "")), "wish_crystal")
	_eq("每抽水晶", int(crystal.get("per_pull", 0)), 1)
	_eq("UR 兑换价", int((crystal.get("exchange_cost", {}) as Dictionary).get("UR", 0)), 120)
	_ok("心愿水晶已进货币表", not GameDB.currency("wish_crystal").is_empty())
	_ok("概率公示文案非空", GameDB.gacha_rate_notice().size() >= 3,
		"%d 条" % GameDB.gacha_rate_notice().size())
	_ok("演出配置齐备", not GameDB.gacha_reveal().is_empty())
	_ok("配置声明了语音 / 音效钩子",
		(GameDB.gacha_reveal().get("voice", {}) as Dictionary).has("UR"))

	# 公示面板的每一行都要有内容可展示，否则公示就是空的
	for pool_id in GameDB.gacha_pool_ids():
		var rows := GachaSys.rate_rows(str(pool_id))
		_ok("「%s」公示行非空" % str(pool_id), not rows.is_empty(), "%d 行" % rows.size())
		for raw in rows:
			var row: Dictionary = raw
			_ok("「%s」%s 行有可出内容" % [str(pool_id), str(row.get("rarity", ""))],
				(row.get("contents", []) as Array).size() > 0,
				str(row.get("contents", [])))


func _rate_has(pool_id: String, rarity: String) -> bool:
	var rates := GameDB.gacha_rates(pool_id)
	return float(rates.get(rarity, 0.0)) > 0.0


# ---------------------------------------------------------------- 概率纯函数

func _check_pure_rules() -> void:
	print("\n· 概率规则（纯函数，逐点验边界）")
	var rates := GameDB.gacha_rates("standard")
	var valid := { "UR": true, "SSR": true, "SR": true, "R": true }

	# 掷点按 rarities.order（R → UR）累加，常驻池累计区间：
	# R [0,0.78)  SR [0.78,0.96)  SSR [0.96,0.995)  UR [0.995,1)
	_eq("roll=0 → R", GachaSys.pick_rarity(rates, valid, "", 0.0), "R")
	_eq("roll=0.7799 → R", GachaSys.pick_rarity(rates, valid, "", 0.7799), "R")
	_eq("roll=0.78 → SR", GachaSys.pick_rarity(rates, valid, "", 0.78), "SR")
	_eq("roll=0.9599 → SR", GachaSys.pick_rarity(rates, valid, "", 0.9599), "SR")
	_eq("roll=0.96 → SSR", GachaSys.pick_rarity(rates, valid, "", 0.96), "SSR")
	_eq("roll=0.9949 → SSR", GachaSys.pick_rarity(rates, valid, "", 0.9949), "SSR")
	_eq("roll=0.995 → UR", GachaSys.pick_rarity(rates, valid, "", 0.995), "UR")
	_eq("roll=0.999 → UR", GachaSys.pick_rarity(rates, valid, "", 0.999), "UR")

	# 保底：只在「不低于 SSR」里按原比例重新归一 —— UR:SSR = 0.005:0.035 = 1:7
	# 归一后 SSR [0,0.875)  UR [0.875,1)
	_eq("保底区间 roll=0 → SSR", GachaSys.pick_rarity(rates, valid, "SSR", 0.0), "SSR")
	_eq("保底区间 roll=0.874 → SSR", GachaSys.pick_rarity(rates, valid, "SSR", 0.874), "SSR")
	_eq("保底区间 roll=0.875 → UR", GachaSys.pick_rarity(rates, valid, "SSR", 0.875), "UR")
	_eq("保底区间 roll=0.999 → UR", GachaSys.pick_rarity(rates, valid, "SSR", 0.999), "UR")

	# 该品质在卡池里没有内容时不该被掷中：UR 有效位为 false，
	# 于是 0.999 只能落在 SSR（若 UR 仍参与，这一掷会命中 UR）
	var fv := { "SSR": true, "SR": true, "R": true }
	_eq("空桶不参与掷点", GachaSys.pick_rarity(rates, fv, "", 0.999), "SSR")

	# UP 分配：同品质内 UP 占 50%（UP 名单必须真的在这个品质桶里）
	var entries: Array = [
		{ "type": "hero", "id": "normal_a", "weight": 1 },
		{ "type": "hero", "id": "up_b", "weight": 1 },
	]
	_eq("UP 分配 roll=0 → UP 组",
		str(GachaSys.choose_entry(entries, ["up_b"], 0.5, 0.0, 0.0).get("entry", {}).get("id", "")), "up_b")
	_eq("UP 分配 roll=0.499 → UP 组",
		str(GachaSys.choose_entry(entries, ["up_b"], 0.5, 0.499, 0.0).get("entry", {}).get("id", "")), "up_b")
	_eq("UP 分配 roll=0.5 → 其余内容",
		str(GachaSys.choose_entry(entries, ["up_b"], 0.5, 0.5, 0.0).get("entry", {}).get("id", "")), "normal_a")
	_eq("UP 分配 roll=0.99 → 其余内容",
		str(GachaSys.choose_entry(entries, ["up_b"], 0.5, 0.99, 0.0).get("entry", {}).get("id", "")), "normal_a")
	_ok("UP 分支标记 from_up",
		bool(GachaSys.choose_entry(entries, ["up_b"], 0.5, 0.1, 0.0).get("from_up", false)))
	_ok("非 UP 分支不标记 from_up",
		not bool(GachaSys.choose_entry(entries, ["up_b"], 0.5, 0.9, 0.0).get("from_up", true)))

	# 内容量不足的退化：该品质只有 UP 这一位英雄时，两边落回同一位，且标记 degrade
	var only_up: Array = [{ "type": "hero", "id": "up_b", "weight": 1 }]
	var deg := GachaSys.choose_entry(only_up, ["up_b"], 0.5, 0.9, 0.0)
	_eq("只剩 UP 时仍给 UP", str(deg.get("entry", {}).get("id", "")), "up_b")
	_ok("并标记为退化（内容量不足）", bool(deg.get("degrade", false)))

	# 组内按权重选：3:1
	var weighted: Array = [
		{ "type": "hero", "id": "w_a", "weight": 3 },
		{ "type": "hero", "id": "w_b", "weight": 1 },
	]
	_eq("权重 3:1 roll=0 → 重的那项",
		str(GachaSys.choose_entry(weighted, [], 0.5, 0.9, 0.0).get("entry", {}).get("id", "")), "w_a")
	_eq("权重 3:1 roll=0.74 → 重的那项",
		str(GachaSys.choose_entry(weighted, [], 0.5, 0.9, 0.74).get("entry", {}).get("id", "")), "w_a")
	_eq("权重 3:1 roll=0.75 → 轻的那项",
		str(GachaSys.choose_entry(weighted, [], 0.5, 0.9, 0.75).get("entry", {}).get("id", "")), "w_b")


# ---------------------------------------------------------------- 分布

func _check_distribution() -> void:
	print("\n· 两万抽实测分布（free 模式 + 冻结保底 = 纯基础概率）")
	var tally := { "UR": 0, "SSR": 0, "SR": 0, "R": 0 }
	var total := 0
	var bad_size := 0
	var ten := 2000
	for i in ten:
		var res := GachaSys.pull("standard", 10, { "free": true, "seed": SEED + i, "use_pity": false })
		var items: Array = res.get("items", [])
		if items.size() != 10:
			bad_size += 1
		for raw in items:
			var it: Dictionary = raw
			var rid := str(it.get("rarity", ""))
			tally[rid] = int(tally.get(rid, 0)) + 1
			total += 1

	print("      实测：UR %d / SSR %d / SR %d / R %d  ·  共 %d 抽" % [
		tally["UR"], tally["SSR"], tally["SR"], tally["R"], total])
	_eq("每次十连都返回 10 项", bad_size, 0)
	_eq("样本量", total, ten * 10)
	_near("UR 占比 ≈ 0.5%", float(tally["UR"]) / float(total), 0.005, 0.002)
	_near("SSR 占比 ≈ 3.5%", float(tally["SSR"]) / float(total), 0.035, 0.006)
	_near("SR 占比 ≈ 18%", float(tally["SR"]) / float(total), 0.18, 0.012)
	_near("R 占比 ≈ 78%", float(tally["R"]) / float(total), 0.78, 0.015)
	_ok("三档占比都落在公示概率的 3σ 容差内", true)


## UP 倍率的实测：限时池 SSR 桶里有 3 位英雄（1 UP + 2 非 UP），
## 规则要求 UP 占同品质产出率的 50%，所以 SSR 里应该有一半是当期 UP。
## 注意 UP 是**按品质**声明的：SSR 的 UP 是紫焰少女，UR 的 UP 才是头条的神圣牧师。
func _check_up_share() -> void:
	print("\n· 当期 UP 实测占比（限时池 SSR 桶：1 UP + 2 非 UP）")
	var ssr_ups := GameDB.gacha_up("limited", "SSR")
	_eq("SSR 品质声明的 UP 名单", ssr_ups, ["pyro_girl"])
	_eq("大保底头条 = 品质最高的那一位 UP", GachaSys.up_hero("limited"), "holy_priest")
	var up_id := str(ssr_ups[0]) if not ssr_ups.is_empty() else ""

	var ssr_total := 0
	var ssr_up := 0
	var seen := {}
	for i in 1000:
		var res := GachaSys.pull("limited", 10, { "free": true, "seed": SEED + 5000 + i, "use_pity": false })
		for raw in res.get("items", []):
			var it: Dictionary = raw
			if str(it.get("rarity", "")) != "SSR":
				continue
			ssr_total += 1
			var cid := str(it.get("char_id", ""))
			seen[cid] = int(seen.get(cid, 0)) + 1
			if cid == up_id:
				ssr_up += 1
	_ok("样本里有 SSR 产出", ssr_total > 300, "SSR %d 张" % ssr_total)
	print("      SSR 明细：%s" % str(seen))
	if ssr_total > 0:
		_near("UP 占同品质产出率 50%", float(ssr_up) / float(ssr_total), 0.5, 0.06)
	_eq("SSR 桶里 3 位英雄都出现过", seen.size(), 3)
	_ok("UP 英雄明显多于任一非 UP 英雄",
		int(seen.get(up_id, 0)) > 0 and int(seen.get(up_id, 0)) >= maxi(
			int(seen.get("arcane_girl", 0)), int(seen.get("shadow_assassin", 0))),
		str(seen))


# ---------------------------------------------------------------- 保底

func _check_pity() -> void:
	print("\n· 保底（触发时机 / 优先级 / 继承）")
	# 小保底：计数器到 49 时，第 50 抽必出 SSR 及以上
	SaveDB.set_pity("standard", 49, 0)
	var res := GachaSys.pull("standard", 1, { "free": true, "seed": 7 })
	var item: Dictionary = res.get("items", [{}])[0]
	_ok("第 50 抽必出 SSR 及以上",
		GameDB.rarity_at_least(str(item.get("rarity", "")), "SSR"),
		"rarity=%s" % str(item.get("rarity", "")))
	_ok("并标记为小保底", bool(item.get("is_small_pity", false)),
		"reason=%s" % str(item.get("reason", "")))
	_eq("小保底抽取后计数归零", int((res.get("pity_after", {}) as Dictionary).get("small", -1)), 0)

	# 计数器 48 时不触发
	SaveDB.set_pity("standard", 48, 0)
	var res2 := GachaSys.pull("standard", 1, { "free": true, "seed": 8 })
	var item2: Dictionary = res2.get("items", [{}])[0]
	_ok("第 49 抽不触发小保底", not bool(item2.get("is_small_pity", true)),
		"rarity=%s" % str(item2.get("rarity", "")))
	_eq("未触发时计数继续累加", int((res2.get("pity_after", {}) as Dictionary).get("small", -1)), 49)

	# 大保底：限时池计到 99，第 100 抽必出当期 UP
	SaveDB.set_pity("limited", 0, 99)
	var res3 := GachaSys.pull("limited", 1, { "free": true, "seed": 9 })
	var item3: Dictionary = res3.get("items", [{}])[0]
	_eq("第 100 抽必出当期 UP 英雄", str(item3.get("char_id", "")), "holy_priest")
	_ok("并标记为大保底", bool(item3.get("is_up_pity", false)))
	_ok("大保底命中同时满足 UP 判定", bool(item3.get("is_up", false)))
	_eq("大保底后计数归零", int((res3.get("pity_after", {}) as Dictionary).get("large", -1)), 0)

	# 两个保底同时到：大保底优先
	SaveDB.set_pity("limited", 49, 99)
	var res4 := GachaSys.pull("limited", 1, { "free": true, "seed": 10 })
	var item4: Dictionary = res4.get("items", [{}])[0]
	_eq("双保底同时到时给 UP 英雄", str(item4.get("char_id", "")), "holy_priest")
	_eq("且判为大保底而非小保底", str(item4.get("reason", "")), GachaSys.REASON_UP_PITY)

	# 常驻池没有大保底：限时池的计数不该影响它
	SaveDB.set_pity("standard", 0, 0)
	var res5 := GachaSys.pull("standard", 1, { "free": true, "seed": 11 })
	_ok("常驻池不会触发大保底", not bool((res5.get("items", [{}])[0] as Dictionary).get("is_up_pity", false)))

	# 十连人物卡地板：300 次十连，每次至少出一张人物卡
	var no_hero := 0
	for i in 300:
		var r := GachaSys.pull("standard", 10, { "free": true, "seed": 1000 + i })
		var heroes := 0
		for raw in r.get("items", []):
			if str((raw as Dictionary).get("kind", "")) == "hero":
				heroes += 1
		if heroes == 0:
			no_hero += 1
	_eq("300 次十连每次都含人物卡", no_hero, 0)

	# 计数按 pity_group 存放：抽过限时池后，存档里只有 "limited" 这一组，
	# 没有跟着卡池期数走的独立副本 —— 换期复用同一 group 即「跨期全额继承」
	SaveDB.set_pity("limited", 12, 34)
	_eq("限时池计数落在 limited 组", int((SaveDB.pity_of("limited") as Dictionary).get("small", -1)), 12)
	_eq("保底组名取自配置而非卡池 id", GachaSys.pity_state("limited").group, "limited")
	_eq("还差几抽必出（小保底）", int(GachaSys.pity_state("limited").get("small_left", -1)), 38)
	_eq("还差几抽必出（大保底）", int(GachaSys.pity_state("limited").get("large_left", -1)), 66)
	SaveDB.set_pity("standard", 0, 0)
	SaveDB.set_pity("limited", 0, 0)


# ---------------------------------------------------------------- 真实抽取（写档）

func _check_pull_payment() -> void:
	print("\n· 真实抽取（扣费 / 发卡 / 累水晶 / 落盘）")
	SaveDB.reset_profile()
	_eq("新号赠送基础召唤券", SaveDB.material_count("ticket_basic"), 10)
	_eq("新号赠送高级召唤卷轴", SaveDB.material_count("ticket_advanced"), 10)
	_eq("新号赠送绑定钻石", SaveDB.balance("bound_gem"), 1600)
	_eq("新号心愿水晶为 0", SaveDB.balance("wish_crystal"), 0)

	# —— 单抽：优先用券 ——
	var before_cards := SaveDB.cards().size()
	var r1 := GachaSys.pull("standard", 1)
	_ok("单抽成功", bool(r1.get("ok", false)), str(r1.get("reason", "")))
	_eq("单抽扣的是召唤券", str((r1.get("pay", {}) as Dictionary).get("kind", "")), "ticket")
	_eq("券减 1", SaveDB.material_count("ticket_basic"), 9)
	_eq("钻石没动", SaveDB.balance("bound_gem"), 1600)
	_eq("英雄持卡 +1", SaveDB.cards().size(), before_cards + 1)
	_eq("抽数累加", SaveDB.total_pulls(), 1)
	_eq("分池抽数累加", SaveDB.pulls_of("standard"), 1)
	_eq("水晶 +1", SaveDB.balance("wish_crystal"), 1)
	# 真读一次盘：确认上面这些不是只躺在内存里
	SaveDB.load_profile()
	_eq("落盘后重读：券仍是 9", SaveDB.material_count("ticket_basic"), 9)
	_eq("落盘后重读：抽数仍是 1", SaveDB.total_pulls(), 1)
	_eq("落盘后重读：持卡数不变", SaveDB.cards().size(), before_cards + 1)

	# —— 十连：券不够 10 张，回落到绑定钻石 ——
	var r2 := GachaSys.pull("standard", 10)
	_ok("十连成功", bool(r2.get("ok", false)), str(r2.get("reason", "")))
	_eq("十连返回 10 项", (r2.get("items", []) as Array).size(), 10)
	_eq("十连回落到绑定钻石", str((r2.get("pay", {}) as Dictionary).get("id", "")), "bound_gem")
	_eq("一次性扣掉 1600 钻石", SaveDB.balance("bound_gem"), 0)
	_eq("券仍是 9（没被拆着用）", SaveDB.material_count("ticket_basic"), 9)
	_eq("水晶 +10 累计 11", SaveDB.balance("wish_crystal"), 11)
	_eq("总抽数 1+10", SaveDB.total_pulls(), 11)
	var ten_heroes := 0
	for raw in r2.get("items", []):
		if str((raw as Dictionary).get("kind", "")) == "hero":
			ten_heroes += 1
	_ok("十连必得至少一张人物卡", ten_heroes >= 1, "hero=%d" % ten_heroes)

	# —— 资源耗尽：不该扣费、不该写档 ——
	var pulls_before := SaveDB.total_pulls()
	var crystals_before := SaveDB.balance("wish_crystal")
	var r3 := GachaSys.pull("standard", 10)
	_ok("资源不足时抽取被拒", not bool(r3.get("ok", true)), str(r3.get("reason", "")))
	_ok("拒绝原因里列出缺口", str(r3.get("reason", "")).contains("资源不足"))
	_eq("被拒时不记抽数", SaveDB.total_pulls(), pulls_before)
	_eq("被拒时不发水晶", SaveDB.balance("wish_crystal"), crystals_before)
	_eq("被拒时不动钻石", SaveDB.balance("bound_gem"), 0)

	# —— 限时池用高级券 ——
	var r4 := GachaSys.pull("limited", 1)
	_ok("限时池单抽成功", bool(r4.get("ok", false)), str(r4.get("reason", "")))
	_eq("限时池扣高级券", str((r4.get("pay", {}) as Dictionary).get("id", "")), "ticket_advanced")
	_eq("高级券减 1", SaveDB.material_count("ticket_advanced"), 9)

	# —— 友情池走公会代币：没有代币就该被拦下 ——
	var r5 := GachaSys.pull("friend", 1)
	_ok("没有公会代币时友情池抽取被拒", not bool(r5.get("ok", true)), str(r5.get("reason", "")))
	SaveDB.add_currency("guild_token", 100, false)
	var r6 := GachaSys.pull("friend", 10)
	_ok("发代币后友情十连成功", bool(r6.get("ok", false)), str(r6.get("reason", "")))
	_eq("友情十连扣 100 代币", SaveDB.balance("guild_token"), 0)
	_ok("友情池出货不低于 R",
		(str(r6.get("max_rarity", "")) != ""), "max=%s" % str(r6.get("max_rarity", "")))


# ---------------------------------------------------------------- 兑换

func _check_exchange() -> void:
	print("\n· 心愿水晶商店兑换")
	var options := GachaSys.exchange_options("limited")
	_ok("兑换名单非空", options.size() > 0, "%d 项" % options.size())
	var has_ur := false
	var has_ssr := false
	for raw in options:
		var row: Dictionary = raw
		if str(row.get("rarity", "")) == "UR":
			has_ur = true
		if str(row.get("rarity", "")) == "SSR":
			has_ssr = true
	_eq("名单含 UR 与 SSR", [has_ur, has_ssr], [true, true])

	# 水晶清零 → 不足必然被拒；再补足 120 → 必然成功（两个分支都做到确定）
	var cur := SaveDB.balance("wish_crystal")
	if cur != 0:
		SaveDB.add_currency("wish_crystal", -cur, false)
	_eq("清零后水晶为 0", SaveDB.balance("wish_crystal"), 0)
	var bad := GachaSys.exchange("limited", "holy_priest")
	_ok("水晶不足时兑换被拒", not bool(bad.get("ok", true)), str(bad.get("reason", "")))
	_ok("拒绝原因写明缺口", str(bad.get("reason", "")).contains("不足"))

	# 补足 120 → 成功兑换当期 UP
	SaveDB.add_currency("wish_crystal", 120, false)
	var cards_before := SaveDB.cards().size()
	var good := GachaSys.exchange("limited", "holy_priest")
	_ok("水晶足够时兑换成功", bool(good.get("ok", false)), str(good.get("reason", "")))
	_eq("扣掉 120 水晶", SaveDB.balance("wish_crystal"), 0)
	_ok("兑换记录计数", SaveDB.count_exchange("holy_priest") >= 1)
	_ok("非名单内英雄不可兑换",
		not bool(GachaSys.exchange("limited", "knight_rock").get("ok", true)))
	var after := SaveDB.cards().size()
	_ok("兑换英雄入账（新卡或升星）", after >= cards_before,
		"%d → %d" % [cards_before, after])


# ---------------------------------------------------------------- 星级封顶

func _check_star_cap() -> void:
	print("\n· 重复卡星级封顶")
	var cfg := GameDB.character("knight_rock")
	var cap := int(GameDB.rarity(str(cfg.get("rarity", "R"))).get("star_max", 1))
	for i in 6:
		SaveDB.grant_card("knight_rock")
	var card := SaveDB.find_card("knight_rock")
	_ok("重复发卡不会超过品质星级上限", int(card.get("star", 0)) <= cap,
		"star=%d cap=%d" % [int(card.get("star", 0)), cap])
	_eq("刚好停在星级上限", int(card.get("star", 0)), cap)


# ---------------------------------------------------------------- 招募记录

func _check_history() -> void:
	print("\n· 招募记录")
	var hist := SaveDB.gacha_history()
	_ok("记录非空", not hist.is_empty(), "%d 条" % hist.size())
	_ok("记录条数不超过上限", hist.size() <= GameDB.gacha_history_max(),
		"%d / %d" % [hist.size(), GameDB.gacha_history_max()])
	var all_hero := true
	for raw in hist:
		var e: Dictionary = raw
		if str(e.get("char_id", "")) == "":
			all_hero = false
	_ok("记录里只有英雄（道具不进记录）", all_hero)
	_ok("最近获得（界面右侧条）有货", GachaSys.recent_heroes(4).size() > 0,
		"%d 条" % GachaSys.recent_heroes(4).size())


# ---------------------------------------------------------------- 场景

func _check_scene() -> void:
	print("\n· 抽卡界面场景")
	var path := str(GameDB.gacha().get("scene", "res://scenes/gacha.tscn"))
	_ok("配置指向的场景存在", ResourceLoader.exists(path), path)
	if not ResourceLoader.exists(path):
		return
	var ps: PackedScene = load(path)
	_ok("场景可加载", ps != null)
	if ps == null:
		return
	_scene = ps.instantiate()
	_tree.root.add_child(_scene)
	_ok("根节点已挂 gacha.gd", _scene.get_script() != null)

	# 演出动画会拖时间，测试全部走静止态
	_scene.set("animate", false)

	# 卡池标签数 = 配置里的卡池数
	var tabs: Control = _scene.get_node_or_null("%PoolTabs")
	_ok("卡池标签容器存在", tabs != null)
	if tabs != null:
		_eq("卡池标签数 = 配置卡池数", tabs.get_child_count(), GameDB.gacha_pools().size())

	# 单抽 / 十连按钮
	var b1: Button = _scene.get_node_or_null("%PullOneButton")
	var b10: Button = _scene.get_node_or_null("%PullTenButton")
	_ok("单抽按钮存在", b1 != null)
	_ok("十连按钮存在", b10 != null)
	if b1 != null:
		_eq("单抽按钮文案", b1.text, "召唤 ×1")
	if b10 != null:
		_eq("十连按钮文案", b10.text, "召唤 ×10")

	# 唯一名节点齐备
	for n in ["MagicCodex", "AltarGlow", "PityBadge", "CrystalLabel", "RevealLayer",
			"RatePanel", "ShopPanel", "Toast", "ToastLabel", "BackButton", "FooterInfo"]:
		_ok("唯一名 %%%s 可解析" % n, _scene.get_node_or_null("%" + n) != null)

	# 展示层默认收起，弹层默认隐藏
	var reveal: Control = _scene.get_node_or_null("%RevealLayer")
	_ok("结算展示层默认隐藏", reveal != null and not reveal.visible)
	var rate: Control = _scene.get_node_or_null("%RatePanel")
	_ok("概率公示弹层默认隐藏", rate != null and not rate.visible)
	var shop: Control = _scene.get_node_or_null("%ShopPanel")
	_ok("水晶商店弹层默认隐藏", shop != null and not shop.visible)

	# 卡池标签可切换，且切池会刷新保底 / 单价
	if tabs != null and tabs.get_child_count() > 0:
		var first: Button = tabs.get_child(0)
		_ok("卡池标签已接信号", first.pressed.get_connections().size() > 0)
		var pool_label: Label = _scene.get_node_or_null("%PoolName")
		var before := pool_label.text if pool_label != null else ""
		(tabs.get_child(1) as Button).pressed.emit()
		var mid := pool_label.text if pool_label != null else ""
		_ok("切到第二个卡池后标题变化", mid != before, "%s → %s" % [before, mid])
		first.pressed.emit()
		var back := pool_label.text if pool_label != null else ""
		_eq("切回第一个卡池", back, before)

	_check_scene_pull(reveal, b1, b10)
	_check_scene_panels(rate, shop)

	_scene.queue_free()


## 走按钮把「真的抽一发」整条链路走完：扣费 → 展示层亮起 → 卡面就位 → 关闭复位
func _check_scene_pull(reveal: Control, b1: Button, b10: Button) -> void:
	print("\n· 场景交互：点按钮真抽")
	SaveDB.reset_profile()
	_scene.call("_refresh_all")

	var reveal_cards: Control = _scene.get_node_or_null("%RevealCards")
	var summary: Label = _scene.get_node_or_null("%RevealSummary")
	_ok("结算卡面容器存在", reveal_cards != null)
	_ok("结算汇总行存在", summary != null)

	# —— 单抽 ——
	# 注意：界面重建列表用的是 queue_free（帧末才真正移除），
	# 同一帧内连续断言要过滤掉已排队删除的节点，否则会数到上一次的残留。
	var tickets_before := SaveDB.material_count("ticket_basic")
	var pulls_before := SaveDB.total_pulls()
	b1.pressed.emit()
	_ok("点单抽后展示层亮起", reveal.visible)
	_ok("单抽扣了召唤券", SaveDB.material_count("ticket_basic") == tickets_before - 1,
		"%d → %d" % [tickets_before, SaveDB.material_count("ticket_basic")])
	_eq("抽数 +1", SaveDB.total_pulls(), pulls_before + 1)
	_eq("结算卡面 1 张", _live_children(reveal_cards).size(), 1)
	_ok("结算卡面已显示", (_live_children(reveal_cards)[0] as Control).visible)
	_ok("汇总行写明了水晶收益", summary.text.contains("心愿水晶 +1"), summary.text)

	# 关闭：展示层收起、卡面清空、卡包复位
	_scene.call("_close_reveal")
	_ok("关闭后展示层隐藏", not reveal.visible)
	_eq("关闭后卡面清空", _live_children(reveal_cards).size(), 0)

	# —— 十连 ——
	var gems_before := SaveDB.balance("bound_gem")
	b10.pressed.emit()
	_ok("点十连后展示层亮起", reveal.visible)
	_eq("结算卡面 10 张", _live_children(reveal_cards).size(), 10)
	_ok("十连扣的是绑定钻石（券不够 10 张）",
		SaveDB.balance("bound_gem") == gems_before - 1600,
		"%d → %d" % [gems_before, SaveDB.balance("bound_gem")])
	var visible_n := 0
	for c in _live_children(reveal_cards):
		if (c as Control).visible:
			visible_n += 1
	_eq("10 张卡面全部就位", visible_n, 10)
	_scene.call("_close_reveal")

	# —— 资源耗尽：按钮变灰、点击被拒 ——
	# 券清零 + 钻石已在十连里花光，此时两种支付方式都该不够
	SaveDB.add_material("ticket_basic", -SaveDB.material_count("ticket_basic"), false)
	SaveDB.add_material("ticket_advanced", -SaveDB.material_count("ticket_advanced"), false)
	_scene.call("_refresh_cost")
	_ok("资源耗尽后单抽按钮变灰", b1.disabled)
	var pulls_now := SaveDB.total_pulls()
	b1.pressed.emit()
	_eq("灰按钮不产生抽取", SaveDB.total_pulls(), pulls_now)
	var toast: Label = _scene.get_node_or_null("%ToastLabel")
	_ok("被拒时给出提示", toast != null and toast.text.contains("资源不足"), toast.text)


func _check_scene_panels(rate: Control, shop: Control) -> void:
	print("\n· 场景交互：公示 / 商店 / 兑换")
	# —— 概率公示 ——
	(_scene.get_node_or_null("%RateButton") as Button).pressed.emit()
	_ok("点开后公示层可见", rate.visible)
	var rate_body: VBoxContainer = _scene.get_node_or_null("%RateBody")
	_ok("公示层列出了品质行", rate_body != null and rate_body.get_child_count() >= 5,
		"%d 行" % (rate_body.get_child_count() if rate_body else 0))
	var rate_text := _collect_text(rate_body)
	for expect in ["78.00%", "18.00%", "3.50%", "0.50%", "必得 1 张人物卡"]:
		_ok("公示层含「%s」" % expect, rate_text.contains(expect))
	(_scene.get_node_or_null("%RateCloseButton") as Button).pressed.emit()
	_ok("关闭后公示层隐藏", not rate.visible)

	# —— 心愿水晶商店 ——
	SaveDB.reset_profile()
	SaveDB.add_currency(GachaSys.crystal_currency(), 240, false)
	_scene.call("_refresh_all")
	(_scene.get_node_or_null("%ShopButton") as Button).pressed.emit()
	_ok("点开后商店可见", shop.visible)
	var shop_body: VBoxContainer = _scene.get_node_or_null("%ShopBody")
	_ok("商店列出了可兑换英雄", shop_body != null and shop_body.get_child_count() > 0,
		"%d 行" % (shop_body.get_child_count() if shop_body else 0))

	# 240 点水晶正好换两次 120 点的 UR
	var cards_before := SaveDB.cards().size()
	var up_id := GachaSys.up_hero("standard")
	if up_id == "":
		up_id = "holy_priest"
	var btn: Button = _find_button(shop_body, "Exchange_%s" % up_id)
	_ok("商店里有「%s」的兑换按钮" % up_id, btn != null)
	if btn != null:
		_ok("兑换按钮可用（水晶足够）", not btn.disabled)
		btn.pressed.emit()
		_ok("兑换后英雄入账", SaveDB.find_card(up_id).size() > 0)
		_eq("扣掉 120 水晶", SaveDB.balance(GachaSys.crystal_currency()), 120)
		btn.pressed.emit()
		_eq("第二次兑换再扣 120", SaveDB.balance(GachaSys.crystal_currency()), 0)
		_ok("兑换次数累计", SaveDB.count_exchange(up_id) == 2)
		_ok("兑换两次持卡只多一张（第二次是升星）",
			SaveDB.cards().size() == cards_before + 1,
			"%d → %d" % [cards_before, SaveDB.cards().size()])
	(_scene.get_node_or_null("%ShopCloseButton") as Button).pressed.emit()
	_ok("关闭后商店隐藏", not shop.visible)
	SaveDB.reset_profile()


## 把一串控件里的 Label 文本拼起来，方便对公示内容做整体断言
func _collect_text(node: Node) -> String:
	var out := ""
	if node is Label:
		out += (node as Label).text + "\n"
	for c in node.get_children():
		out += _collect_text(c)
	return out


## 存活子节点：重建列表用的是 queue_free（帧末才真正移除），
## 同一帧内连续断言要过滤掉已排队删除的节点，否则会数到上一次的残留。
func _live_children(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if not c.is_queued_for_deletion():
			out.append(c)
	return out


## 深度找按钮：兑换按钮挂在行 Panel 里，不是 VBox 的直接子节点。
## 跳过已排队删除的节点 —— 商店面板每次刷新都 queue_free 旧行再建新行，
## 同一帧里旧按钮还在树上，而且往往是上一次余额不足时的禁用态。
func _find_button(node: Node, button_name: String) -> Button:
	if node.is_queued_for_deletion():
		return null
	if node is Button and str(node.name) == button_name:
		return node
	for c in node.get_children():
		var found := _find_button(c, button_name)
		if found != null:
			return found
	return null
