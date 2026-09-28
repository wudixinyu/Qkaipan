extends SceneTree
## diag_gacha.gd —— 抽卡分布诊断（只打印事实，不做断言）
##
##   Godot --headless --path <项目> --script res://tools/diag_gacha.gd
##
## 用途：改了概率表 / UP 名单 / 保底尺之后，先看这里再改测试 ——
## 冒烟测试断言「规则对不对」，这个脚本回答「数值长什么样」。
##
## 注意：--script 的入口脚本在编译期看不到 autoload 全局名，所以全程走
## get_node_or_null("/root/X") + call()，不能直接写 GameDB / GachaSys。

var _frames := 0
var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	# 主循环起来后再取 autoload；等几帧纯粹是为了跟 smoke_*.gd 一个节奏
	_frames += 1
	if _frames < 4:
		return false
	_done = true

	var game_db: Node = root.get_node_or_null("GameDB")
	var gacha: Node = root.get_node_or_null("GachaSys")
	if game_db == null or gacha == null:
		push_error("[diag] autoload 未就绪：GameDB=%s GachaSys=%s" % [game_db, gacha])
		quit(1)
		return true

	var rng := RandomNumberGenerator.new()
	rng.seed = 20260927
	var vals: Array = []
	for i in 12:
		vals.append(snappedf(rng.randf(), 0.001))
	print("同一种子连续 12 个 randf：%s" % str(vals))

	# 逐种子取样：第 2 个随机值就是「UP 分支」的判定值
	var branch: Array = []
	var below := 0
	for i in 40:
		rng.seed = 5000 + i
		rng.randf()
		var v := rng.randf()
		branch.append(snappedf(v, 0.01))
		if v < 0.5:
			below += 1
	print("40 个个体的第 2 个随机值：%s" % str(branch))
	print("  其中 < 0.5 的有 %d / %d" % [below, branch.size()])

	var entries: Array = game_db.call("gacha_pool_entries", "limited", "SSR")
	var ups: Array = game_db.call("gacha_up", "limited", "SSR")
	var up_rate: float = game_db.call("gacha_up_rate", "limited")
	print("limited SSR 桶：%s" % str(entries))
	print("limited SSR UP 名单：%s   up_rate=%.2f" % [str(ups), up_rate])

	var tally := {}
	rng.seed = 777
	for i in 3000:
		var pick: Dictionary = gacha.call("choose_entry", entries, ups, up_rate,
			rng.randf(), rng.randf())
		var e: Dictionary = pick.get("entry", {})
		var key := "%s%s" % [str(e.get("id", "?")), " (up)" if bool(pick.get("from_up", false)) else ""]
		tally[key] = int(tally.get(key, 0)) + 1
	print("choose_entry × 3000：%s" % str(tally))

	var by_rarity := {}
	var ssr_by_char := {}
	for i in 1000:
		var res: Dictionary = gacha.call("pull", "limited", 10,
			{ "free": true, "seed": 9000 + i, "use_pity": false })
		for raw in res.get("items", []):
			var it: Dictionary = raw
			var rid := str(it.get("rarity", ""))
			by_rarity[rid] = int(by_rarity.get(rid, 0)) + 1
			if rid == "SSR":
				var cid := str(it.get("char_id", ""))
				ssr_by_char[cid] = int(ssr_by_char.get(cid, 0)) + 1
	print("一万抽品质分布：%s" % str(by_rarity))
	print("其中 SSR 明细：%s" % str(ssr_by_char))
	quit(0)
	return true
