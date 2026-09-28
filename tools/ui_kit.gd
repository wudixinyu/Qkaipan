class_name UIKit
extends RefCounted
## UIKit —— 程序化搭 UI 的工具箱
##
## 只提供无状态的构造帮助函数，不持有任何节点引用。
## 场景构建脚本与运行时控件都通过它来统一观感（圆角、描边、阴影、渐变）。

const FONT_MAIN := "res://assets/fonts/ui_font.tres"

# ---------------------------------------------------------------- 颜色

const INK := Color("#2A1F17")
const INK_SOFT := Color("#5A4636")
const CREAM := Color("#FFF6E2")
const GOLD := Color("#FFC94A")
const GOLD_DEEP := Color("#B8791F")
const GOLD_LIGHT := Color("#FFE9A8")
const PANEL_BG := Color(0.11, 0.09, 0.16, 0.82)
const PANEL_BORDER := Color(1.0, 0.85, 0.45, 0.55)


# ---------------------------------------------------------------- StyleBox

static func style(bg: Color, radius: int = 14, border_w: int = 0,
		border_color: Color = Color.TRANSPARENT,
		shadow_size: int = 0, shadow_color: Color = Color(0, 0, 0, 0.35)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if border_w > 0:
		sb.set_border_width_all(border_w)
		sb.border_color = border_color
	if shadow_size > 0:
		sb.shadow_size = shadow_size
		sb.shadow_color = shadow_color
		sb.shadow_offset = Vector2(0, max(2, shadow_size / 2))
	sb.anti_aliasing = true
	return sb


static func panel(bg: Color, radius: int = 14, border_w: int = 0,
		border_color: Color = Color.TRANSPARENT,
		shadow_size: int = 0, shadow_color: Color = Color(0, 0, 0, 0.35)) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel",
		style(bg, radius, border_w, border_color, shadow_size, shadow_color))
	return p


static func panel_with(sb: StyleBoxFlat) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", sb)
	return p


# ---------------------------------------------------------------- 纹理

static func gradient_tex(from: Color, to: Color, vertical: bool = true,
		mid: Color = Color(0, 0, 0, 0), has_mid: bool = false) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, from)
	g.set_color(1, to)
	if has_mid:
		g.add_point(0.5, mid)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 16
	t.height = 256 if vertical else 16
	t.fill_from = Vector2(0.0, 0.0)
	t.fill_to = Vector2(0.0, 1.0) if vertical else Vector2(1.0, 0.0)
	return t


static func radial_tex(inner: Color, outer: Color) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, inner)
	g.set_color(1, outer)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 256
	t.height = 256
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t


static func gradient_rect(from: Color, to: Color, vertical: bool = true) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = gradient_tex(from, to, vertical)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


static func glow_rect(color: Color, inner_alpha: float = 0.55) -> TextureRect:
	var c_in := color
	c_in.a = inner_alpha
	var c_out := color
	c_out.a = 0.0
	var tr := TextureRect.new()
	tr.texture = radial_tex(c_in, c_out)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


static func icon(path: String, size: float, tint: Color = Color.WHITE) -> TextureRect:
	var tr := TextureRect.new()
	if ResourceLoader.exists(path):
		tr.texture = load(path)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = Vector2(size, size)
	tr.modulate = tint
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


static func picture(path: String, stretch: TextureRect.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED) -> TextureRect:
	var tr := TextureRect.new()
	if ResourceLoader.exists(path):
		tr.texture = load(path)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = stretch
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


# ---------------------------------------------------------------- 文本

## 千分位格式化：1250 -> "1,250"
static func fmt_num(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out


## 大数缩写：12500 -> "1.25万"
static func fmt_compact(n: int) -> String:
	if absi(n) < 10000:
		return fmt_num(n)
	if absi(n) < 100000000:
		return "%.2f万" % (float(n) / 10000.0)
	return "%.2f亿" % (float(n) / 100000000.0)


static func label(text: String, size: int = 24, color: Color = CREAM,
		outline: int = 0, outline_color: Color = Color(0, 0, 0, 0.72)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", load(FONT_MAIN))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", outline_color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func label_shadow(text: String, size: int, color: Color, outline: int,
		outline_color: Color, shadow_offset: Vector2, shadow_color: Color,
		box_size: Vector2) -> Control:
	## 用两层叠加做立体质感标题（底层深色错位 + 顶层亮色），按给定盒子居中
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.custom_minimum_size = box_size
	holder.size = box_size

	var under := label(text, size, shadow_color, outline, shadow_color)
	under.set_anchors_preset(Control.PRESET_FULL_RECT)
	under.offset_left += shadow_offset.x
	under.offset_right += shadow_offset.x
	under.offset_top += shadow_offset.y
	under.offset_bottom += shadow_offset.y
	under.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	under.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	holder.add_child(under)

	var over := label(text, size, color, outline, outline_color)
	over.set_anchors_preset(Control.PRESET_FULL_RECT)
	over.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	over.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	holder.add_child(over)
	return holder


# ---------------------------------------------------------------- 按钮

static func icon_button(path: String, size: float, bg: Color, border: Color,
		tint: Color = Color.WHITE) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(size, size)
	b.add_theme_stylebox_override("normal", style(bg, int(size / 2.0), 3, border, 8))
	b.add_theme_stylebox_override("hover", style(bg.lightened(0.14), int(size / 2.0), 3, border.lightened(0.2), 10))
	b.add_theme_stylebox_override("pressed", style(bg.darkened(0.14), int(size / 2.0), 3, border, 4))
	b.add_theme_stylebox_override("focus", style(Color(0, 0, 0, 0), int(size / 2.0), 0))
	b.focus_mode = Control.FOCUS_NONE
	var tr := icon(path, size * 0.5, tint)
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	b.add_child(tr)
	return b


static func text_button(text: String, font_size: int, bg: Color, border: Color,
		text_color: Color, radius: int = 18) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", load(FONT_MAIN))
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", text_color)
	b.add_theme_color_override("font_hover_color", text_color.lightened(0.15))
	b.add_theme_color_override("font_pressed_color", text_color.darkened(0.15))
	b.add_theme_stylebox_override("normal", style(bg, radius, 4, border, 12, Color(0, 0, 0, 0.42)))
	b.add_theme_stylebox_override("hover", style(bg.lightened(0.10), radius, 4, border.lightened(0.2), 16, Color(0, 0, 0, 0.45)))
	b.add_theme_stylebox_override("pressed", style(bg.darkened(0.12), radius, 4, border, 6, Color(0, 0, 0, 0.42)))
	b.add_theme_stylebox_override("focus", style(Color(0, 0, 0, 0), radius, 0))
	b.focus_mode = Control.FOCUS_NONE
	return b


# ---------------------------------------------------------------- 布局

static func fill(node: Control) -> Control:
	## 注意：set_anchors_preset() 不会清零 offset。若节点此前被设过 size，
	## 会留下 offset_right/bottom，与 anchor 1.0 叠加成双倍尺寸。
	## 所以这里必须显式把四个 offset 归零，否则「铺满父节点」会变成「两倍于父节点」。
	node.set_anchors_preset(Control.PRESET_FULL_RECT)
	node.offset_left = 0.0
	node.offset_top = 0.0
	node.offset_right = 0.0
	node.offset_bottom = 0.0
	return node


## 让节点相对父容器左上角固定定位
static func place(node: Control, x: float, y: float, w: float = 0.0, h: float = 0.0) -> Control:
	node.set_anchors_preset(Control.PRESET_TOP_LEFT)
	node.position = Vector2(x, y)
	if w > 0.0 or h > 0.0:
		node.custom_minimum_size = Vector2(w, h)
		node.size = Vector2(w, h)
	return node


## 锚到父容器右侧，可指定右边距
static func anchor_right_top(node: Control, margin_right: float, y: float) -> Control:
	node.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	node.offset_right = -margin_right
	node.offset_left = -margin_right - node.custom_minimum_size.x
	node.offset_top = y
	node.offset_bottom = y + node.custom_minimum_size.y
	return node


static func centered(node: Control, parent_w: float, parent_h: float,
		y: float = -1.0) -> Control:
	node.set_anchors_preset(Control.PRESET_TOP_LEFT)
	node.position = Vector2((parent_w - node.custom_minimum_size.x) / 2.0,
		y if y >= 0.0 else (parent_h - node.custom_minimum_size.y) / 2.0)
	return node


## 水平居中钉在父容器顶部
static func anchor_top_center(node: Control, w: float, h: float, y: float) -> Control:
	node.anchor_left = 0.5
	node.anchor_right = 0.5
	node.anchor_top = 0.0
	node.anchor_bottom = 0.0
	node.offset_left = -w / 2.0
	node.offset_right = w / 2.0
	node.offset_top = y
	node.offset_bottom = y + h
	node.custom_minimum_size = Vector2(w, h)
	return node


## 水平居中钉在父容器底部，留出下边距
static func anchor_bottom_center(node: Control, w: float, h: float,
		margin_bottom: float) -> Control:
	node.anchor_left = 0.5
	node.anchor_right = 0.5
	node.anchor_top = 1.0
	node.anchor_bottom = 1.0
	node.offset_left = -w / 2.0
	node.offset_right = w / 2.0
	node.offset_bottom = -margin_bottom
	node.offset_top = -margin_bottom - h
	node.custom_minimum_size = Vector2(w, h)
	return node


## 钉在父容器右侧，垂直居中
static func anchor_right_center(node: Control, w: float, h: float,
		margin_right: float) -> Control:
	node.anchor_left = 1.0
	node.anchor_right = 1.0
	node.anchor_top = 0.5
	node.anchor_bottom = 0.5
	node.offset_right = -margin_right
	node.offset_left = -margin_right - w
	node.offset_top = -h / 2.0
	node.offset_bottom = h / 2.0
	node.custom_minimum_size = Vector2(w, h)
	return node


## 钉在父容器左上角
static func anchor_top_left(node: Control, x: float, y: float,
		w: float, h: float) -> Control:
	node.anchor_left = 0.0
	node.anchor_right = 0.0
	node.anchor_top = 0.0
	node.anchor_bottom = 0.0
	node.offset_left = x
	node.offset_top = y
	node.offset_right = x + w
	node.offset_bottom = y + h
	node.custom_minimum_size = Vector2(w, h)
	return node


## 钉在父容器右上角
static func anchor_top_right(node: Control, margin_right: float, y: float,
		w: float, h: float) -> Control:
	node.anchor_left = 1.0
	node.anchor_right = 1.0
	node.anchor_top = 0.0
	node.anchor_bottom = 0.0
	node.offset_right = -margin_right
	node.offset_left = -margin_right - w
	node.offset_top = y
	node.offset_bottom = y + h
	node.custom_minimum_size = Vector2(w, h)
	return node


## 钉在父容器左下角
static func anchor_bottom_left(node: Control, x: float, w: float,
		h: float, margin_bottom: float) -> Control:
	node.anchor_left = 0.0
	node.anchor_right = 0.0
	node.anchor_top = 1.0
	node.anchor_bottom = 1.0
	node.offset_left = x
	node.offset_right = x + w
	node.offset_bottom = -margin_bottom
	node.offset_top = -margin_bottom - h
	node.custom_minimum_size = Vector2(w, h)
	return node


## 钉在父容器右下角
static func anchor_bottom_right(node: Control, margin_right: float,
		w: float, h: float, margin_bottom: float) -> Control:
	node.anchor_left = 1.0
	node.anchor_right = 1.0
	node.anchor_top = 1.0
	node.anchor_bottom = 1.0
	node.offset_right = -margin_right
	node.offset_left = -margin_right - w
	node.offset_bottom = -margin_bottom
	node.offset_top = -margin_bottom - h
	node.custom_minimum_size = Vector2(w, h)
	return node


static func spacer(w: float = 0.0, h: float = 0.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func set_owner_recursive(node: Node, owner: Node) -> void:
	node.owner = owner
	for c in node.get_children():
		set_owner_recursive(c, owner)
