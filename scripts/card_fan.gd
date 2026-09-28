class_name CardFan
extends Control
## CardFan —— 主界面卡牌扇形陈列容器
##
## 负责把 N 张卡按配置的旋转 / 纵向偏移 / 缩放 / 层级一字排开。
## 排布参数来自 game_data.json 的 menu.fan，因此改布局不用碰代码。
## 与 CardView 一样不依赖 autoload，配置经 configure() 注入。
##
## 左右滚动（编队页 8 名英雄，卡排比陈列区宽时启用）：
##   * 按住卡排横向拖拽，松手带惯性滑行；
##   * 悬停在卡排上滚动滚轮，横移一格；
##   * focus_card() 把指定卡滚回中线（点选卡库 / 棋盘格 / 卡牌时由界面调用）。
## 内容装得下时滚动自动失效（主界面 4 张卡不受影响），不需要额外开关。

signal card_pressed(char_id: String)

const CardViewScript := preload("res://scripts/card_view.gd")

## 拖拽判定阈值（px）：位移小于它算点击，不打断点选
const DRAG_THRESHOLD := 8.0
## 滚轮一格对应的滚动距离（px）
const WHEEL_STEP := 260.0
## 惯性：松手瞬间速度 × 系数 = 滑行距离
const GLIDE_RATIO := 0.12
## 低于这个速度（px/s）不滑行，直接停住
const GLIDE_MIN_VEL := 60.0

var cards: Array = []

# —— 滚动状态（configure 时按内容宽度重算）——
var _scroll := 0.0        ## 加到每张卡 base.x 上的偏移：>0 露出左端，<0 露出右端
var _scroll_min := 0.0    ## 下限：内容右缘贴陈列区右缘
var _scroll_max := 0.0    ## 上限：内容左缘贴陈列区左缘
var _slot_x: Array = []   ## 每张卡的基准轴线 x（未加滚动），focus_card 用
var _base_pos: Array = [] ## 每张卡未加滚动的基准 position
var _center_x := 0.0      ## 陈列区中线（含 center_x_offset）
var _pressing := false
var _dragging := false
var _press_scroll := 0.0
var _press_pos := Vector2.ZERO
var _vel := 0.0
var _last_motion_ms := 0
var _scroll_tween: Tween


## items : [{ char_id, config, card, stats }, ...]
## ctx   : { "rarities": <table>, "elements": <table> }
func configure(items: Array, ctx: Dictionary, card_box: Vector2, fan_cfg: Dictionary) -> void:
	clear()
	if items.is_empty():
		return

	var rarities: Dictionary = ctx.get("rarities", {})
	var elements: Dictionary = ctx.get("elements", {})
	var per_list: Array = fan_cfg.get("per_index", [])
	# 整体缩放系数：卡面里的字号 / 徽章 / 三围条都是绝对像素，只改卡框宽度
	# 会让文字相对变大、把三围条挤出内腔。所以缩卡只能靠节点等比缩放，
	# 让「文字 + 卡框 + 立绘」一起变小。间距与纵向错位跟随同比例，
	# 否则卡变小而间距不变，扇形会被拉散。
	var fan_scale := maxf(0.05, float(fan_cfg.get("scale", 1.0)))
	var spacing := float(fan_cfg.get("spacing_x", 296.0)) * fan_scale
	var cy := float(fan_cfg.get("center_y_offset", 0.0))
	var cx := float(fan_cfg.get("center_x_offset", 0.0))

	var n := items.size()
	var area := size if size.x > 1.0 else custom_minimum_size
	# cx 用来把扇形从"整屏居中"挪开：右侧被功能入口栏占了一条，纯几何居中会让
	# 末卡贴到入口栏边框上。留成配置项，改布局不用动代码。
	var center := Vector2(area.x * 0.5 + cx, area.y * 0.5 + cy)
	_center_x = center.x

	var content_left := INF
	var content_right := -INF

	for i in n:
		var item: Dictionary = items[i]
		var cfg: Dictionary = item.get("config", {})
		var rarity_id := str(cfg.get("rarity", "R"))
		var elem_id := str(cfg.get("element", ""))

		var cv: CardView = CardViewScript.new()
		cv.name = "Card_%s" % str(item.get("char_id", i))
		cv.custom_minimum_size = card_box
		cv.size = card_box
		add_child(cv)
		cv.setup(item, rarities.get(rarity_id, {}), elements.get(elem_id, {}), card_box)

		var per: Dictionary = per_list[i] if i < per_list.size() else {}
		var rot := float(per.get("rot_deg", 0.0))
		var dy := float(per.get("y", 0.0)) * fan_scale
		var sc := float(per.get("scale", 1.0)) * fan_scale
		var z := int(per.get("z", i))

		var slot_x := center.x + (float(i) - (n - 1) * 0.5) * spacing
		cv.position = Vector2(slot_x, center.y + dy) - card_box * 0.5
		cv.set_layout(rot, sc, z)

		_slot_x.append(slot_x)
		_base_pos.append(cv.position)
		# 视觉宽度按缩放算（缩放绕卡中心），两端留出拖入空间才贴得齐
		var half := card_box.x * sc * 0.5
		content_left = minf(content_left, slot_x - half)
		content_right = maxf(content_right, slot_x + half)

		cv.card_pressed.connect(func(id): card_pressed.emit(id))
		cards.append(cv)

	# —— 滚动范围：内容两端各自贴到陈列区对应边缘；装得下时区间为空 → 不可滚 ——
	_scroll_min = area.x - content_right
	_scroll_max = -content_left
	_pressing = false
	_dragging = false
	_kill_scroll_tween()
	_scroll = clampf(_scroll, _scroll_min, _scroll_max)
	if not scrollable():
		_scroll = 0.0
	_apply_scroll()


func clear() -> void:
	# 不能只遍历 cards 数组：场景里可能预先烘焙了预览用的 CardView，
	# 那些节点不在本次实例的 cards 里，只清数组会留下一批幽灵卡牌。
	for c in get_children():
		if c is CardView:
			remove_child(c)
			c.queue_free()
	cards.clear()
	_slot_x.clear()
	_base_pos.clear()


## 内容是否宽过陈列区（留 1px 余量防浮点误差误判）
func scrollable() -> bool:
	return _scroll_max - _scroll_min > 1.0


## 把指定卡滚到陈列区中线（点选卡库 / 棋盘格 / 卡牌时由界面调用）。
## animate=false 用于重建列表后的瞬时对位；拖拽进行中会让路。
func focus_card(char_id: String, animate: bool = true) -> void:
	if not scrollable() or _dragging:
		return
	for i in cards.size():
		var cv: CardView = cards[i]
		if is_instance_valid(cv) and cv.char_id == char_id:
			_goto_scroll(_center_x - float(_slot_x[i]), 0.3 if animate else 0.0)
			return


# ---------------------------------------------------------------- 滚动内核

func _apply_scroll() -> void:
	for i in cards.size():
		var cv: CardView = cards[i]
		if not is_instance_valid(cv) or i >= _base_pos.size():
			continue
		var pos: Vector2 = _base_pos[i]
		pos.x += _scroll
		cv.position = pos
		# hover 的回落基准必须跟着走，否则一滚动卡片就被旧基准拽回去
		cv.set_base_pos(pos)


## 拖拽 / 惯性外的入口都走这里：先掐掉在飞的滚动补间再落位
func _set_scroll(v: float) -> void:
	_kill_scroll_tween()
	_scroll = clampf(v, _scroll_min, _scroll_max)
	_apply_scroll()


func _goto_scroll(target: float, dur: float = 0.22) -> void:
	target = clampf(target, _scroll_min, _scroll_max)
	if dur <= 0.0 or is_equal_approx(target, _scroll):
		_set_scroll(target)
		return
	_kill_scroll_tween()
	_scroll_tween = create_tween()
	_scroll_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_scroll_tween.tween_method(_step_scroll, _scroll, target, dur)


func _step_scroll(v: float) -> void:
	_scroll = clampf(v, _scroll_min, _scroll_max)
	_apply_scroll()


func _kill_scroll_tween() -> void:
	if _scroll_tween != null and _scroll_tween.is_valid():
		_scroll_tween.kill()


func _glide() -> void:
	var v := clampf(_vel, -4200.0, 4200.0)
	if absf(v) < GLIDE_MIN_VEL:
		return
	_goto_scroll(_scroll + v * GLIDE_RATIO, 0.55)


# ---------------------------------------------------------------- 输入

func _input(event: InputEvent) -> void:
	if not scrollable() or cards.is_empty():
		return
	var mb := event as InputEventMouseButton
	if mb != null:
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				# _input 比 GUI 先跑：只有按下点确实落在扇形（或它的卡牌子树）里
				# 才武装拖拽，不然在筛选/排序弹层上拖动也会滚卡排
				if _in_band(mb) and _press_in_fan():
					_pressing = true
					_dragging = false
					_press_scroll = _scroll
					var local := make_input_local(mb) as InputEventMouse
					_press_pos = local.position
					_vel = 0.0
					_last_motion_ms = Time.get_ticks_msec()
			elif _pressing:
				_pressing = false
				if _dragging:
					_dragging = false
					_glide()
		else:
			var is_wheel := mb.button_index == MOUSE_BUTTON_WHEEL_UP \
				or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN
			if mb.pressed and is_wheel and _in_band(mb):
				# 滚轮上 = 朝队首（左）翻，滚轮下 = 朝队尾（右）翻
				var step := WHEEL_STEP if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -WHEEL_STEP
				_goto_scroll(_scroll + step)
		return
	var mm := event as InputEventMouseMotion
	if mm == null or not _pressing:
		return
	var local_m := make_input_local(mm) as InputEventMouse
	var dx := local_m.position.x - _press_pos.x
	if not _dragging and absf(dx) > DRAG_THRESHOLD:
		_dragging = true
	if _dragging:
		var now := Time.get_ticks_msec()
		var dt := float(now - _last_motion_ms) / 1000.0
		if dt > 0.0:
			_vel = lerpf(_vel, mm.relative.x / dt, 0.45)
		_last_motion_ms = now
		_set_scroll(_press_scroll + dx)


## 陈列区横向条带（纵向略放宽兜住 hover 抬升）。x 不设限：
## 卡排本来就溢出到窗口两缘，边缘卡也要能按住拖。
func _in_band(event: InputEvent) -> bool:
	var local := make_input_local(event) as InputEventMouse
	if local == null:
		return false
	return local.position.y >= -40.0 and local.position.y <= size.y + 6.0


## 按下点是否落在扇形容器或它的卡牌子树里（弹层面板上的按下不算）
func _press_in_fan() -> bool:
	var hovered: Control = get_viewport().gui_get_hovered_control()
	while hovered != null:
		if hovered == self:
			return true
		hovered = hovered.get_parent() as Control
	return false


## 给主界面入场动画用：依次从下方弹入
func play_intro() -> void:
	for i in cards.size():
		var cv: CardView = cards[i]
		if not is_instance_valid(cv):
			continue
		var target: Vector2 = cv.position
		var rest_scale: Vector2 = cv.scale
		cv.position = target + Vector2(0, 260)
		cv.modulate.a = 0.0
		cv.scale = rest_scale * 0.86
		var delay := 0.06 * float(i)
		var t := cv.create_tween().set_parallel(true)
		t.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		# 注意：set_delay() 属于 Tweener，不属于 Tween，必须挂在每次 tween_property 的返回值上
		t.tween_property(cv, "position", target, 0.42).set_delay(delay)
		t.tween_property(cv, "modulate:a", 1.0, 0.30).set_delay(delay)
		t.tween_property(cv, "scale", rest_scale, 0.42).set_delay(delay)
		t.chain().tween_callback(func():
			cv.set_layout(cv.rotation_degrees, rest_scale.x, cv.z_index))


func find_card(char_id: String) -> CardView:
	for c in cards:
		if is_instance_valid(c) and c.char_id == char_id:
			return c
	return null
