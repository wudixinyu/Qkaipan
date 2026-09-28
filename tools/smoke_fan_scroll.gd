extends SceneTree
## smoke_fan_scroll.gd —— CardFan 左右滚动内核冒烟测试
##
## 用法：
##   Godot --headless --path <项目> --script res://tools/smoke_fan_scroll.gd
##
## 不依赖任何 autoload：CardFan / CardView 是自包含控件，直接 new 出来测。
## 覆盖：可滚判定 / 边界钳制 / focus_card 回中 / set_base_pos 同步 /
##       装得下时自动失效（主界面形态）/ 滚轮输入路径（补间要泵帧）。

var _frames := 0
var _started := false
var _done := false
var _fails := 0
var _checks := 0


func _process(_delta: float) -> bool:
	if _done:
		return true
	_frames += 1
	if _frames < 4:
		return false
	if not _started:
		_started = true
		_run()  # async：内部会泵帧等补间
	return false


func _ok(title: String, cond: bool, extra: String = "") -> void:
	_checks += 1
	if not cond:
		_fails += 1
		print("  ✗ %s%s" % [title, ("　[" + extra + "]") if extra != "" else ""])


func _eq(title: String, got: Variant, want: Variant) -> void:
	_ok(title, got == want, "got=%s want=%s" % [str(got), str(want)])


func _items(n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append({
			"char_id": "c%d" % i,
			"config": {"rarity": "R", "element": "fire", "name": "卡%d" % i},
			"card": {"level": 1, "star": 1},
			"stats": {"hp": 10, "atk": 1, "def": 1},
		})
	return out


func _ctx() -> Dictionary:
	return {
		"rarities": {"R": {"id": "R", "name": "普通", "color": "#FFFFFF",
			"inner_rect": [0.08, 0.08, 0.92, 0.92]}},
		"elements": {"fire": {"id": "fire", "name": "火", "color": "#FF5533", "icon": ""}},
	}


## 编队页同款排布参数（8 名英雄，spacing 385 × scale 0.68）
func _fan_cfg() -> Dictionary:
	return {
		"scale": 0.68, "spacing_x": 385.0,
		"center_x_offset": 80.0, "center_y_offset": 2.0,
		"per_index": [
			{"rot_deg": -7.0, "y": 28, "scale": 0.93, "z": 0},
			{"rot_deg": -2.0, "y": -26, "scale": 1.02, "z": 3},
			{"rot_deg": 2.0, "y": -8, "scale": 0.97, "z": 2},
			{"rot_deg": 6.5, "y": 22, "scale": 0.93, "z": 1},
		],
	}


func _make_fan(n: int, area: Vector2) -> CardFan:
	var fan: CardFan = load("res://scripts/card_fan.gd").new()
	fan.size = area
	root.add_child(fan)
	fan.configure(_items(n), _ctx(), Vector2(336, 520), _fan_cfg())
	return fan


func _pump(frames: int) -> void:
	for i in frames:
		await process_frame


func _run() -> void:
	print("\n· 可滚判定与初始版面")
	var fan := _make_fan(8, Vector2(1320, 432))
	_ok("8 张卡 + 编队页排布 = 可滚动", fan.scrollable())
	_eq("初始停在原点（保留默认版面）", float(fan.get("_scroll")), 0.0)
	var first: CardView = fan.cards[0]
	_ok("首卡向左溢出陈列区（与现版一致）", first.position.x < 0.0,
		"first.x=%.0f" % first.position.x)
	var last: CardView = fan.cards[7]
	_ok("末卡向右溢出陈列区", last.position.x + 336.0 > 1320.0,
		"right=%.0f" % (last.position.x + 336.0))

	print("\n· focus_card 回中")
	# 视觉半宽：卡带缩放（绕中心），端点卡只能「贴边」不能居中，中间卡才能真回中
	var half0 := 336.0 * (0.93 * 0.68) * 0.5   # index 0 → per_index[0]
	var half7 := 336.0 * 0.68 * 0.5            # index 7 → 超出 per_index，取默认 1.0
	fan.focus_card("c3", false)
	var mid: CardView = fan.cards[3]
	_ok("中间卡精确滚到陈列区中线", absf(mid.position.x + 168.0 - 740.0) < 1.0,
		"center=%.1f want=740.0" % (mid.position.x + 168.0))  # 1320/2 + center_x_offset 80
	_ok("滚动后 _base_pos 与 position 同步",
		(mid.get("_base_pos") as Vector2).distance_to(mid.position) < 0.01)
	fan.focus_card("c7", false)
	_ok("末卡聚焦 = 滚到下限（右缘贴陈列区右缘）",
		absf(float(fan.get("_scroll")) - float(fan.get("_scroll_min"))) < 0.5,
		"scroll=%.1f min=%.1f" % [float(fan.get("_scroll")), float(fan.get("_scroll_min"))])
	_ok("末卡视觉右缘贴边", absf(last.position.x + 168.0 + half7 - 1320.0) < 1.0,
		"right=%.1f" % (last.position.x + 168.0 + half7))
	fan.focus_card("c0", false)
	_ok("首卡聚焦 = 滚到上限（左缘贴陈列区左缘）",
		absf(float(fan.get("_scroll")) - float(fan.get("_scroll_max"))) < 0.5,
		"scroll=%.1f max=%.1f" % [float(fan.get("_scroll")), float(fan.get("_scroll_max"))])
	_ok("首卡视觉左缘贴边", absf(first.position.x + 168.0 - half0 - 0.0) < 1.0,
		"left=%.1f" % (first.position.x + 168.0 - half0))

	print("\n· 边界钳制")
	fan._set_scroll(1e9)
	_ok("滚过队首会被钳住", first.position.x + 168.0 - half0 >= -0.5,
		"left=%.1f scroll=%.1f" % [first.position.x + 168.0 - half0, float(fan.get("_scroll"))])
	fan._set_scroll(-1e9)
	_ok("滚过队尾会被钳住", last.position.x + 168.0 + half7 <= 1320.5,
		"right=%.1f" % (last.position.x + 168.0 + half7))

	print("\n· 滚轮输入路径（补间，泵帧等待）")
	fan._set_scroll(0.0)
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = Vector2(660, 220)
	wheel.global_position = wheel.position
	fan._input(wheel)
	await _pump(40)
	var after_down := float(fan.get("_scroll"))
	_ok("滚轮下 = 朝队尾滚（_scroll 变小）", after_down < 0.0, "scroll=%.1f" % after_down)
	var wheel_up := InputEventMouseButton.new()
	wheel_up.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_up.pressed = true
	wheel_up.position = Vector2(660, 220)
	wheel_up.global_position = wheel_up.position
	fan._input(wheel_up)
	await _pump(40)
	var after_up := float(fan.get("_scroll"))
	_ok("滚轮上滚回原点附近", absf(after_up) < 1.0,
		"scroll=%.1f (down=%.1f)" % [after_up, after_down])

	print("\n· 装得下时自动失效（主界面形态）")
	fan.queue_free()
	var small := _make_fan(4, Vector2(1920, 432))
	_ok("4 张卡 + 全屏陈列区 = 不可滚", not small.scrollable())
	_eq("不可滚时 _scroll 恒为 0", float(small.get("_scroll")), 0.0)
	small.focus_card("c3", false)
	_eq("focus_card 在不可滚时是空操作", float(small.get("_scroll")), 0.0)
	var c3: CardView = small.cards[3]
	_ok("卡片位置不受影响",
		(c3.get("_base_pos") as Vector2).distance_to(c3.position) < 0.01)
	small.queue_free()

	print("")
	print("[smoke] 检查 %d 项，失败 %d 项" % [_checks, _fails])
	quit(0 if _fails == 0 else 1)
	_done = true
