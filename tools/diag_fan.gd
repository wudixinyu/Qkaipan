extends SceneTree
## diag_fan.gd —— 扇形叠压诊断（窗口模式运行，视口必须是真实 1920x1080）
##
## 冒烟测试只能验证「卡面内部布局相对卡框是否合法」，验证不了「左卡右半
## 是否被右卡盖住」——那是跨节点的遮挡关系。这里把每张卡的三围条四个角
## 换算到画布全局坐标，再逐对求交，直接算出被吃掉的比例。
##
## 用法：
##   Godot.exe --path . --resolution 1920x1080 --script res://tools/diag_fan.gd
##
## 刻意不用 await：--script 的 SceneTree 在 _initialize 里挂起协程不可靠，
## 沿用 shot_main_menu.gd 那种 _process(delta)->bool 的状态机写法。

const SCENE_PATH := "res://scenes/main_menu.tscn"

## 入场动画约 0.6s，等 1.5s 保证位置已静止
const SETTLE_SECONDS := 1.5
const TIMEOUT_SECONDS := 20.0

var _stage := 0
var _elapsed := 0.0


func _process(delta: float) -> bool:
	if _stage == 0:
		_stage = 1
		return false

	if _stage == 1:
		var packed: PackedScene = load(SCENE_PATH)
		if packed == null:
			push_error("[diag] 场景加载失败：" + SCENE_PATH)
			quit(1)
			return true
		get_root().add_child(packed.instantiate())
		_stage = 2
		return false

	_elapsed += delta
	if _stage == 2 and _elapsed >= SETTLE_SECONDS:
		_stage = 3
		_report()
		quit(0)
		return true

	if _elapsed >= TIMEOUT_SECONDS:
		push_error("[diag] 超时")
		quit(1)
		return true

	return false


func _report() -> void:
	print("\n========== 扇形叠压诊断 ==========")
	var scene: Node = get_root().get_child(get_root().get_child_count() - 1)
	var fan: Node = scene.get_node_or_null("%CardFan")
	if fan == null:
		print("[diag] 找不到 %CardFan")
		return

	print("视口 = %s" % str(get_root().get_visible_rect().size))
	print("CardFan 全局矩形 = %s" % _fmt((fan as Control).get_global_rect()))

	var rows: Array = []
	for child in fan.get_children():
		if not (child is Control):
			continue
		var card: Control = child
		if not (card is CardView):
			continue
		var card_global: Rect2 = card.get_global_rect()
		var row: Control = card.get_node_or_null("StatRow")
		var row_global := Rect2()
		var vals: Array = []
		if row != null:
			row_global = row.get_global_rect()
			for i in range(3):
				var lb: Label = row.get_node_or_null("StatValue%d" % i)
				if lb != null:
					vals.append({ "i": i, "text": lb.text, "rect": lb.get_global_rect() })
		print("\n· %s" % card.char_id)
		print("    card  global = %s  rot=%.1f scale=%.2f z=%d" % [
			_fmt(card_global), card.rotation_degrees, card.scale.x, card.z_index])
		print("    stat  global = %s" % _fmt(row_global))
		for v in vals:
			print("      val%d %-6s global = %s" % [v.i, v.text, _fmt(v.rect)])

		# 除三围条外，名牌 / 等级 / 元素徽章同样不能被邻卡压住
		var extras: Array = []
		for spec in [["NamePlate", "名牌"], ["LevelLabel", "等级"], ["ElementBadge", "元素徽章"]]:
			var n: Control = card.get_node_or_null(spec[0])
			if n != null:
				extras.append({ "i": -1, "text": spec[1], "rect": n.get_global_rect() })

		rows.append({ "id": card.char_id, "z": card.z_index, "card": card_global,
			"row": row_global, "vals": vals + extras })

	print("\n---- 遮挡分析（z 大者盖 z 小者；只统计三围条/名牌/等级/元素徽章） ----")
	var worst := 0.0
	var worst_desc := ""
	for i in range(rows.size()):
		for j in range(rows.size()):
			if i == j:
				continue
			var a: Dictionary = rows[i]
			var b: Dictionary = rows[j]
			if int(b.z) <= int(a.z):
				continue
			var inter: Rect2 = (a.row as Rect2).intersection(b.card)
			if inter.size.x > 0.0 and inter.size.y > 0.0:
				var row_area: float = maxf(1.0, (a.row as Rect2).size.x * (a.row as Rect2).size.y)
				print("  %s 三围条 被 %s 盖 %.0f%%" % [
					a.id, b.id, inter.size.x * inter.size.y / row_area * 100.0])
			for v in a.vals:
				var vi: Rect2 = (v.rect as Rect2).intersection(b.card)
				var vtotal: float = maxf(1.0, (v.rect as Rect2).size.x * (v.rect as Rect2).size.y)
				var vp: float = vi.size.x * vi.size.y / vtotal * 100.0
				if vp > worst:
					worst = vp
					worst_desc = "%s 的 %s 被 %s 盖" % [a.id, v.text, b.id]
				if vp > 2.0:
					print("      [遮挡] %-10s 被盖 %.0f%%" % [v.text, vp])

	print("\n最大信息块遮挡比例 = %.0f%%   (%s)" % [worst, worst_desc])


func _fmt(r: Rect2) -> String:
	return "[%.0f,%.0f %.0fx%.0f]" % [r.position.x, r.position.y, r.size.x, r.size.y]
