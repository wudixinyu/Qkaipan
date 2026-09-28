class_name CardView
extends Control
## CardView —— 主界面立体卡牌控件
##
## 叠层自下而上：品质辉光 → 投影 → 卡底 → 立绘(裁切于内腔) → 卡框 → 信息带
## 内部坐标全部由 rarity_cfg.inner_rect 反推，所以 R / SR / SSR / UR 四种卡框
## 的开口差异不会让元素徽章、品质字、星级、名牌、三围条跑出内腔。
##
## 刻意不依赖任何 autoload：配置与数据全部经 setup() 注入，这样场景构建脚本
## （无 autoload 环境）也能预置一份可视化预览。

signal card_pressed(char_id: String)

const UI := preload("res://tools/ui_kit.gd")

const PORTRAIT_ZOOM := 1.10
const PORTRAIT_BOTTOM_BIAS := 0.03

var char_id: String = ""
var rarity_id: String = "R"
var config: Dictionary = {}
var card: Dictionary = {}
var stats: Dictionary = {}
var box: Vector2 = Vector2(336, 520)

var _rarity: Dictionary = {}
var _element: Dictionary = {}

var _base_scale: Vector2 = Vector2.ONE
var _base_pos: Vector2 = Vector2.ZERO
var _rest_z_index: int = 0
var _hovered: bool = false
var _selected: bool = false
var _select_mult: float = 1.0
var _tween: Tween
var _tween_moves_pos := false  ## 当前补间是否在动 position（hover 抬升/回落）

var _portrait_holder: Control
var _portrait: TextureRect
var _frame: TextureRect
var _ring: Control


## item   : { char_id, config, card, stats }
## rarity : rarities.table 里的一项（含 inner_rect / color / frame …）
## element: elements.table 里的一项（含 color / icon）
func setup(item: Dictionary, rarity: Dictionary, element: Dictionary, card_box: Vector2) -> void:
	char_id = str(item.get("char_id", ""))
	config = item.get("config", {})
	card = item.get("card", {})
	stats = item.get("stats", {})
	rarity_id = str(config.get("rarity", rarity.get("id", "R")))
	_rarity = rarity
	_element = element
	box = card_box
	_build()
	if is_inside_tree():
		_hook_hover()


func _build() -> void:
	custom_minimum_size = box
	size = box
	pivot_offset = box / 2.0
	mouse_filter = Control.MOUSE_FILTER_STOP

	for c in get_children():
		remove_child(c)
		c.free()

	var inner := inner_px()
	var accent := Color(str(_rarity.get("color", "#FFFFFF")))
	var glow_color := Color(str(_rarity.get("glow", _rarity.get("color", "#FFFFFF"))))

	if bool(_rarity.get("frame_glow", false)):
		var glow := UI.glow_rect(glow_color, 0.40)
		glow.position = Vector2(-box.x * 0.16, -box.y * 0.12)
		glow.size = box + Vector2(box.x * 0.32, box.y * 0.24)
		_add(glow)

	var shadow := UI.panel(Color(0, 0, 0, 0.32), 26)
	shadow.position = Vector2(0, 12)
	shadow.size = box
	_add(shadow)

	var bed := UI.panel(Color(str(_rarity.get("bed_tint", "#222222"))), 20)
	bed.size = box
	_add(bed)

	_portrait_holder = Control.new()
	_portrait_holder.position = inner.position
	_portrait_holder.size = inner.size
	_portrait_holder.clip_contents = true
	_add(_portrait_holder)

	_portrait = UI.picture(str(config.get("portrait", "")), TextureRect.STRETCH_SCALE)
	_portrait_holder.add_child(_portrait)
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layout_portrait()

	_frame = UI.picture(str(_rarity.get("frame", "")), TextureRect.STRETCH_SCALE)
	_frame.size = box
	_add(_frame)

	_build_info_band(inner, accent)
	_build_element_badge(inner)
	_build_rarity_marks(inner)
	_build_selection_ring(accent)
	if _selected:
		_apply_selection()


# ---------------------------------------------------------------- 子块

func _build_info_band(inner: Rect2, accent: Color) -> void:
	# 信息带的横向范围跟随「内腔」而不是整张卡：UR 卡框很厚，若按卡宽排布，
	# 三围条会伸到卡框外面被盖住。
	var band_left := inner.position.x + 8.0
	var band_w := inner.size.x - 16.0
	var bottom := inner.position.y + inner.size.y

	var band_top := inner.position.y + inner.size.y * 0.52
	var band := UI.gradient_rect(Color(0.05, 0.04, 0.08, 0.0), Color(0.05, 0.04, 0.08, 0.90))
	band.position = Vector2(0, band_top)
	band.size = Vector2(box.x, box.y - band_top)
	_add(band)

	# ---- 三围条 ----
	# 刻意不用 HBoxContainer：容器的 minimum_size 等于子节点最小宽之和，
	# 一旦超出给定宽度就会把行撑开，第三个数值会被卡框切掉。
	# 这里改为按 1/3 手工定位，宽度完全可控。
	var stats_h := 32.0
	var stats_y := bottom - stats_h - 6.0
	var stat_row := Control.new()
	stat_row.position = Vector2(band_left, stats_y)
	stat_row.size = Vector2(band_w, stats_h)
	_add(stat_row, "StatRow")

	var cell_w := band_w / 3.0
	var entries := [
		["res://assets/icons/icon_hp.svg", Color("#FF6B6B"), int(stats.get("hp", 0))],
		["res://assets/icons/icon_atk.svg", Color("#FFB347"), int(stats.get("atk", 0))],
		["res://assets/icons/icon_def.svg", Color("#7BC8F6"), int(stats.get("def", 0))],
	]
	for i in entries.size():
		var e: Array = entries[i]
		var ic := UI.icon(e[0], 18.0, e[1])
		var lb := UI.label(UI.fmt_num(e[2]), 18, UI.CREAM, 4)
		var lb_w: float = maxf(30.0, lb.get_minimum_size().x)
		var content := 18.0 + 3.0 + lb_w
		var x0 := float(i) * cell_w + (cell_w - content) * 0.5
		UI.place(ic, x0, (stats_h - 18.0) * 0.5, 18, 18)
		lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		UI.place(lb, x0 + 21.0, 0.0, lb_w, stats_h)
		_add_to(stat_row, ic, "StatIcon%d" % i)
		_add_to(stat_row, lb, "StatValue%d" % i)

	# ---- 名牌 ----
	var plate_h := 38.0
	var plate_y := stats_y - plate_h - 5.0
	var plate := UI.panel(Color(0.09, 0.07, 0.13, 0.68), 12, 2, accent.darkened(0.3))
	plate.position = Vector2(band_left, plate_y)
	plate.size = Vector2(band_w, plate_h)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add(plate, "NamePlate")

	var name_label := UI.label(str(config.get("name", "???")), 26, UI.CREAM, 6)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	plate.add_child(name_label)

	# ---- 等级（名牌右上方） ----
	var lv := UI.label("Lv.%d" % int(card.get("level", 1)), 21, Color("#FFE9A8"), 5)
	lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lv.position = Vector2(band_left, plate_y - 30.0)
	lv.size = Vector2(band_w, 28.0)
	_add(lv, "LevelLabel")


func _build_element_badge(inner: Rect2) -> void:
	var d := 50.0
	var badge := Control.new()
	badge.position = inner.position + Vector2(10, 10)
	badge.size = Vector2(d, d)
	_add(badge, "ElementBadge")

	var ring := UI.panel(Color(str(_element.get("color", "#888888"))).darkened(0.18),
		int(d / 2.0), 3, Color(1, 1, 1, 0.85), 6, Color(0, 0, 0, 0.45))
	ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	badge.add_child(ring)

	var ic := UI.icon(str(_element.get("icon", "")), d * 0.58, Color.WHITE)
	ic.set_anchors_preset(Control.PRESET_FULL_RECT)
	badge.add_child(ic)


func _build_rarity_marks(inner: Rect2) -> void:
	var right := inner.position.x + inner.size.x - 12.0

	var rar_label := UI.label(rarity_id, 38, Color.WHITE, 7, Color(0, 0, 0, 0.82))
	rar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rar_label.position = Vector2(right - 180.0, inner.position.y + 2.0)
	rar_label.size = Vector2(180.0, 46.0)
	_add(rar_label)

	var star := clampi(int(card.get("star", 1)), 0, int(_rarity.get("star_max", 3)))
	if star <= 0:
		return
	var star_row := HBoxContainer.new()
	star_row.add_theme_constant_override("separation", -2)
	var total: float = 22.0 * float(star) - 2.0 * float(maxi(0, star - 1))
	star_row.position = Vector2(right - total, inner.position.y + 52.0)
	star_row.size = Vector2(total, 26.0)
	_add(star_row)
	for i in star:
		_add_to(star_row, UI.icon("res://assets/icons/icon_star.svg", 22.0, Color("#FFD45E")))


## 选中态的高亮层：金色辉光 + 圆角金框，铺在卡框之上。
## 刻意只做「一个可以开关的图层」，位置与缩放交给 CardFan 的排布 ——
## 两处都改同一个属性，选中放大就会被 hover 补间抢掉。
func _build_selection_ring(accent: Color) -> void:
	_ring = Control.new()
	_ring.name = "SelectionRing"
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.visible = false
	_add(_ring)

	var glow := UI.glow_rect(Color("#FFC94A"), 0.45)
	UI.place(glow, -40, -34, box.x + 80, box.y + 68)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.add_child(glow)

	var border := UI.panel(Color(0, 0, 0, 0), 26, 7, Color("#FFD45E"), 26,
		Color(0.34, 0.18, 0.02, 0.55))
	UI.place(border, -13, -13, box.x + 26, box.y + 26)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.add_child(border)

	var inner := UI.panel(Color(0, 0, 0, 0), 20, 2, accent.lightened(0.5), 0)
	UI.place(inner, -5, -5, box.x + 10, box.y + 10)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.add_child(inner)


func _layout_portrait() -> void:
	if _portrait.texture == null or _portrait_holder == null:
		return
	var ts: Vector2 = _portrait.texture.get_size()
	if ts.x <= 0.0 or ts.y <= 0.0:
		return
	var holder := _portrait_holder.size
	var fit: float = min(holder.x / ts.x, holder.y / ts.y) * PORTRAIT_ZOOM
	var s := ts * fit
	_portrait.size = s
	_portrait.position = Vector2(
		(holder.x - s.x) * 0.5,
		holder.y - s.y + holder.y * PORTRAIT_BOTTOM_BIAS)


# ---------------------------------------------------------------- 对外

## 由 CardFan 注入扇形排布的旋转 / 缩放 / 层级
func set_layout(rot_deg: float, scale_mult: float, z: int) -> void:
	rotation_degrees = rot_deg
	scale = Vector2.ONE * scale_mult
	_rest_z_index = z
	z_index = _rest_z()
	_base_scale = Vector2.ONE * scale_mult
	_base_pos = position


## 选中态：显示金色高亮边框，并整体放大一档。编队页用它标出「正在查看」的那张卡。
##
## 放大不是直接写 scale，而是记成 select_mult 后走 _rest_scale() ——
## 扇形排布（set_layout）与 hover 补间都在动 scale，三处各写一次必然互相打架。
func set_selected(on: bool, mult: float = 1.10) -> void:
	_selected = on
	_select_mult = mult if on else 1.0
	_apply_selection()


func is_selected() -> bool:
	return _selected


## CardFan 横向滚动时同步基准位：hover 抬升/回落的补间目标就是它，
## 不同步的话一滚动，卡片就会被旧基准拽回滚动前的位置。
func set_base_pos(pos: Vector2) -> void:
	_base_pos = pos
	# 位置补间还在飞向旧基准时掐掉并按新基准瞬时对位，
	# 不然拖拽滚动会和补间抢 position，卡片来回抖。
	if _tween != null and _tween.is_valid() and _tween_moves_pos:
		_tween.kill()
		_tween_moves_pos = false
		position = pos + (Vector2(0, -20) if _hovered else Vector2.ZERO)
		scale = _rest_scale() * (1.06 if _hovered else 1.0)


func _rest_scale() -> Vector2:
	return _base_scale * (_select_mult if _selected else 1.0)


func _rest_z() -> int:
	return _rest_z_index + (20 if _selected else 0)


func _apply_selection() -> void:
	if _ring != null:
		_ring.visible = _selected
	z_index = _rest_z() if not _hovered else 30
	if not is_inside_tree():
		scale = _rest_scale()
		return
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween_moves_pos = false  # 选中补间只动 scale，不碰 position
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "scale", _rest_scale() * (1.06 if _hovered else 1.0), 0.18)


func inner_px() -> Rect2:
	var v: Variant = _rarity.get("inner_rect", [0.08, 0.08, 0.92, 0.92])
	var r: Array = v if v is Array and (v as Array).size() == 4 else [0.08, 0.08, 0.92, 0.92]
	return Rect2(
		float(r[0]) * box.x, float(r[1]) * box.y,
		(float(r[2]) - float(r[0])) * box.x,
		(float(r[3]) - float(r[1])) * box.y)


func _ready() -> void:
	_hook_hover()


func _hook_hover() -> void:
	if not mouse_entered.is_connected(_on_hover):
		mouse_entered.connect(_on_hover.bind(true))
		mouse_exited.connect(_on_hover.bind(false))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		card_pressed.emit(char_id)
		accept_event()


func _on_hover(on: bool) -> void:
	if _hovered == on:
		return
	_hovered = on
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween_moves_pos = true  # hover 抬升/回落会动 position，滚动时要被 set_base_pos 掐掉
	_tween = create_tween().set_parallel(true)
	_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "scale", _rest_scale() * (1.06 if on else 1.0), 0.16)
	_tween.tween_property(self, "position", _base_pos + (Vector2(0, -20) if on else Vector2.ZERO), 0.16)
	_tween.tween_property(self, "modulate", Color(1.08, 1.06, 1.0) if on else Color.WHITE, 0.16)
	z_index = 30 if on else _rest_z()


# ---------------------------------------------------------------- 内部

func _add(node: Node, node_name: String = "") -> void:
	if node_name != "":
		node.name = node_name
	add_child(node)
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE


func _add_to(parent: Node, node: Node, node_name: String = "") -> void:
	if node_name != "":
		node.name = node_name
	parent.add_child(node)
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
