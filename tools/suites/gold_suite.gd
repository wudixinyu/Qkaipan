extends RefCounted
## gold_suite.gd —— 金币经济闭环冒烟测试套件
##
## 由 tools/smoke_gold.gd 在第一帧之后动态 load()。
## 覆盖金币的「涨」与「花」两侧，全部走真实代码路径：
##   EARN  战斗胜利 → _grant_rewards → 钱包金币增加并落盘
##   SPEND 抽卡在券 / 绑定钻石耗尽时回落到金币支付并真实扣减
##   SPEND 祭坛「祈祷」扣金币 + 下发下一场增益（可跨场景存活）
##   SPEND 祭坛「献祭」扣体力 + 发放道具碎片（不动金币）
##   GUARD 余额不足时祈祷被拒、金币不扣、增益不下发

var _passed := 0
var _failed := 0


func run(tree: SceneTree) -> int:
	print("\n========== 卡牌大冒险 · 金币经济闭环冒烟测试 ==========")
	_check_battle_earn(tree)
	_check_gacha_gold_spend()
	_check_altar_pray(tree)
	_check_altar_sacrifice(tree)
	_check_altar_insufficient(tree)
	# 收尾：回到干净新号档，别把验证残留写进玩家存档
	SaveDB.reset_profile()
	BattleCtx.reset()
	print("\n---------- 结果：通过 %d / 失败 %d ----------" % [_passed, _failed])
	return _failed


# ---------------------------------------------------------------- EARN：战斗发金币

func _check_battle_earn(tree: SceneTree) -> void:
	print("\n· 战斗胜利发金币")
	SaveDB.reset_profile()
	var gold0 := SaveDB.balance("gold")
	BattleCtx.begin_from_stage(1001, "smoke")
	var scene: Node = (load("res://scenes/battle.tscn") as PackedScene).instantiate()
	tree.root.add_child(scene)
	scene.core.winner = "player"
	scene.core.end_reason = "wipe"
	scene.core.finished = true
	scene._show_result()
	var want := 0
	for raw in scene.stage.get("rewards", []):
		if str((raw as Dictionary).get("id", "")) == "gold":
			want = int((raw as Dictionary).get("count", 0))
	_eq("金币随胜利入账（+%d）" % want, SaveDB.balance("gold"), gold0 + want)
	# 落盘核对：重新读 save.json，确认金币真的写进了磁盘
	var f2 := FileAccess.open("user://save.json", FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f2.get_as_text())
	f2.close()
	var disk_gold := int((parsed as Dictionary).get("wallet", {}).get("gold", -1))
	_eq("金币已写入 save.json", disk_gold, gold0 + want)
	tree.root.remove_child(scene)
	scene.free()


# ---------------------------------------------------------------- SPEND：抽卡金币兜底

func _check_gacha_gold_spend() -> void:
	print("\n· 抽卡金币兜底支付")
	SaveDB.reset_profile()
	SaveDB.profile["wallet"]["bound_gem"] = 0
	SaveDB.profile["wallet"]["gold"] = 20000
	for m in ["ticket_basic", "ticket_advanced"]:
		SaveDB.profile["progress"]["pending_items"][m] = 0
	SaveDB.save_profile()
	var chosen: Dictionary = GachaSys.cost("standard", 10).get("option", {})
	_eq("券/钻石耗尽时首选金币", str(chosen.get("id", "")), "gold")
	var g0 := SaveDB.balance("gold")
	var r := GachaSys.pull("standard", 10)
	_ok("金币十连成功", bool(r.get("ok", false)), str(r.get("reason", "")))
	_eq("金币十连扣 16000", SaveDB.balance("gold"), g0 - 16000)


# ---------------------------------------------------------------- SPEND：祭坛祈祷

func _check_altar_pray(tree: SceneTree) -> void:
	print("\n· 祭坛祈祷：扣金币 + 发增益")
	SaveDB.reset_profile()
	StaminaSys.fill()
	SaveDB.profile["wallet"]["gold"] = 500
	SaveDB.save_profile()
	var scene: Node = _open_altar(tree)
	var pray := _option(scene, "pray")
	var g0 := SaveDB.balance("gold")
	scene._on_event_option(pray)
	_eq("祈祷扣 100 金币", SaveDB.balance("gold"), g0 - 100)
	_ok("祈祷下发增益 atk_bonus=1.15", is_equal_approx(float(BattleCtx.atk_bonus), 1.15), str(BattleCtx.atk_bonus))
	_ok("增益名写入 BattleCtx", BattleCtx.buff_name != "", BattleCtx.buff_name)
	_close(scene, tree)


# ---------------------------------------------------------------- SPEND：祭坛献祭

func _check_altar_sacrifice(tree: SceneTree) -> void:
	print("\n· 祭坛献祭：扣体力 + 发碎片")
	SaveDB.reset_profile()
	StaminaSys.fill()
	SaveDB.profile["wallet"]["gold"] = 500
	SaveDB.save_profile()
	var scene: Node = _open_altar(tree)
	var sac := _option(scene, "sacrifice")
	var st0 := StaminaSys.current()
	var item0 := SaveDB.material_count("shard_mystic_girl")
	scene._on_event_option(sac)
	_eq("献祭扣 20 体力", StaminaSys.current(), st0 - 20)
	_eq("献祭发 5 碎片", SaveDB.material_count("shard_mystic_girl"), item0 + 5)
	_eq("献祭不动金币", SaveDB.balance("gold"), 500)
	_close(scene, tree)


# ---------------------------------------------------------------- GUARD：余额不足

func _check_altar_insufficient(tree: SceneTree) -> void:
	print("\n· 金币不足时祈祷被拒")
	SaveDB.reset_profile()
	StaminaSys.fill()
	SaveDB.profile["wallet"]["gold"] = 50
	SaveDB.save_profile()
	var scene: Node = _open_altar(tree)
	var pray := _option(scene, "pray")
	BattleCtx.consume_buff()
	scene._on_event_option(pray)
	_eq("余额不变（仍 50）", SaveDB.balance("gold"), 50)
	_ok("被拒时不下发增益", is_equal_approx(float(BattleCtx.atk_bonus), 1.0), str(BattleCtx.atk_bonus))
	_close(scene, tree)


# ---------------------------------------------------------------- 辅助

func _open_altar(tree: SceneTree) -> Node:
	BattleCtx.begin_from_stage(1005, "smoke")
	BattleCtx.consume_buff()
	var scene: Node = (load("res://scenes/battle.tscn") as PackedScene).instantiate()
	tree.root.add_child(scene)
	return scene


func _close(scene: Node, tree: SceneTree) -> void:
	tree.root.remove_child(scene)
	scene.free()


func _option(scene: Node, id: String) -> Dictionary:
	for raw in scene.stage.get("options", []):
		if str((raw as Dictionary).get("id", "")) == id:
			return raw
	return {}


func _ok(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		_passed += 1
		print("  [PASS] %s%s" % [label, ("  " + detail) if detail != "" else ""])
	else:
		_failed += 1
		print("  [FAIL] %s  %s" % [label, detail])


func _eq(label: String, got, want) -> void:
	_ok(label, got == want, "got=%s want=%s" % [str(got), str(want)])
