extends SceneTree
## diag_battle.gd —— 战斗内核诊断（跑几场，打印战报与结果）
##
## 用法：
##   Godot --headless --path <项目> --script res://tools/diag_battle.gd
##   Godot --headless --path <项目> --script res://tools/diag_battle.gd -- 1003 12345   # 指定关卡与种子
##
## 为什么要有这个脚本：
##   BattleCore 的数值平衡靠战报才看得出问题（谁先死、Boss 第几拍放大招、
##   治疗是否过量）。冒烟测试只断言不变量，这个脚本给的是「打得像不像话」。
##   与界面完全解耦，改倍率后跑一遍几十毫秒，不用开窗口。

const CORE_PATH := "res://scripts/battle_core.gd"
const SUITE_ORDER := [1001, 1002, 1003, 1004, 1006, 1008, 1009, 1010]
const SEED := 20260927


func _process(_delta: float) -> bool:
	var args := OS.get_cmdline_user_args()
	var ids: Array = []
	var seed := SEED
	if args.size() >= 1:
		for a in args:
			if int(a) > 0:
				if ids.is_empty():
					ids.append(int(a))
				else:
					seed = int(a)

	var core_script: Script = load(CORE_PATH)
	if core_script == null:
		push_error("[diag] 无法加载 %s" % CORE_PATH)
		quit(1)
		return true

	var all: Array = ids if not ids.is_empty() else SUITE_ORDER
	print("\n========== 战斗内核诊断（种子 %d）==========" % seed)
	print("我方阵容战力：%d\n" % _player_power())

	for sid in all:
		_run(core_script, int(sid), seed)

	quit(0)
	return true


func _player_power() -> int:
	var total := 0
	for e in _entries():
		var st: Dictionary = e.get("stats", {})
		total += int(round(float(st.get("hp", 0)) * 0.12 + float(st.get("atk", 0)) * 2.4
			+ float(st.get("def", 0)) * 1.6 + float(st.get("mres", 0)) * 1.1
			+ float(st.get("spd", 0)) * 2.0 + float(st.get("crit", 0.0)) * 600.0))
	return total


func _entries() -> Array:
	var core_script: Script = load(CORE_PATH)
	return core_script.player_entries()


func _run(core_script: Script, stage_id: int, seed: int) -> void:
	var core: RefCounted = core_script.new()
	core.setup(stage_id, core_script.player_entries(), {"seed": seed})
	if core.units.size() <= core.team_of("player").size():
		print("· 关卡 %d：非战斗节点，跳过\n" % stage_id)
		return

	var stage: Dictionary = core.stage
	print("—— #%d %s（%s）建议战力 %d ｜ 敌方战力 %d ｜ power_scale %.3f"
		% [stage_id, str(stage.get("name", "")), str(stage.get("kind", "")),
			int(stage.get("recommend_power", 0)), core.team_power("enemy"),
			float(stage.get("power_scale", 0.0))])

	core.run_all()
	var lines: Array = core.log_lines
	# 关键事件单独拎出来看：大招、控制、Boss 特性这些往往夹在几十行普攻里，
	# 只打印首尾会完全看不到，而它们才是平衡问题的所在。
	print("   -- 关键事件 --")
	var keys := ["★", "震晕", "护甲", "使用【", "附加护盾", "环境效果", "⭐"]
	var hits := 0
	for l in lines:
		for k in keys:
			if str(l).contains(k):
				print("      " + str(l))
				hits += 1
				break
	if hits == 0:
		print("      （无）")
	var show := mini(lines.size(), 10)
	print("   -- 战报开头 --")
	for i in show:
		print("   " + str(lines[i]))
	if lines.size() > show:
		print("   …… 共 %d 行" % lines.size())

	print("   >>> 结果：%s（%s）｜ 行动 %d 拍 ｜ 我方残血 %.0f%% / 敌方残血 %.0f%%"
		% [str(core.winner), str(core.end_reason), core.action_count,
			core.hp_ratio("player") * 100.0, core.hp_ratio("enemy") * 100.0])
	for u in core.units:
		print("      %-10s %-5s hp %5d/%-5d 行动 %2d  怒气 %3d  大招=%s" %
			[str(u.name), str(u.side), int(u.hp), int(u.max_hp), int(u.actions),
				int(u.energy), "有" if not (u.ult as Dictionary).is_empty() else "无"])
	print("")
