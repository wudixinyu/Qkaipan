extends SceneTree
## build_stage_select.gd —— 程序化构建「冒险关卡选择」场景
##
## 用法（headless）：
##   Godot --headless --path <项目> --script res://tools/build_stage_select.gd
##
## 产出：res://scenes/stage_select.tscn
##
## 设计约定（与 build_main_menu.gd 同构）：
##   1. 本脚本不依赖任何 autoload —— --script 模式下 autoload 全局名不可见，
##      所以配置直接读 res://data/game_data.json。
##   2. 静态布局全部用「锚点 + 偏移」写死，换分辨率不会错位。
##   3. 地图上的关卡节点 / 装饰浮岛 / 引导线属动态内容，只留空容器
##      （DecorLayer / GuideLayer / NodeLayer），运行时由 stage_select.gd
##      按 adventure.select_map 的锚点填充。
##   4. 文案（标题 / 按钮 / 队伍角标）全部取自配置，不写死在场景里。

const UI := preload("res://tools/ui_kit.gd")

## stage_select.gd 引用了 autoload（GameDB / SaveDB / StaminaSys），
## 而 autoload 全局标识符要等主循环起来才注册，所以这里只能延迟 load()。
const STAGE_SELECT_SCRIPT_PATH := "res://scripts/stage_select.gd"

const DATA_PATH := "res://data/game_data.json"
const OUT_PATH := "res://scenes/stage_select.tscn"
## 选关页背景 = 概念稿的纯净底图，由 tools/prep_stage_select_bg.py 预处理成 1920x1080。
## 与主界面共用的 bg_islands.png 分开存，改这张不会波及主界面。
const BG_PATH := "res://assets/art/bg/bg_stage_select.png"
const BASE := Vector2(1920, 1080)

## 运行时用 %Name 直取的节点，避免路径漂移
const UNIQUE_NAMES := [
	"PlayerName", "PlayerLevel", "AvatarTex", "ExpBar", "GoldLabel", "GemLabel",
	"StaminaValue", "StaminaNext", "TitleLabel",
	"DecorLayer", "GuideLayer", "NodeLayer", "TeamSlots", "TeamLabel",
	"EnterButton", "EnterSub", "BackButton", "FooterInfo", "Toast", "ToastLabel",
]

var _root: Control
var _data: Dictionary = {}
var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	if not _load_data():
		quit(1)
		return true
	_build()
	_save()
	quit(0)
	return true


func _load_data() -> bool:
	if not FileAccess.file_exists(DATA_PATH):
		push_error("[build] 缺少 %s" % DATA_PATH)
		return false
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[build] game_data.json 解析失败")
		return false
	_data = parsed
	return true


# ---------------------------------------------------------------- 组装

func _build() -> void:
	_root = Control.new()
	_root.name = "StageSelect"
	var script: Script = load(STAGE_SELECT_SCRIPT_PATH)
	if script == null:
		push_error("[build] 无法加载 %s" % STAGE_SELECT_SCRIPT_PATH)
	_root.set_script(script)
	# 先定尺寸再改锚点：锚点不等时 Godot 会警告 size 将在 _ready 后被覆盖
	_root.custom_minimum_size = BASE
	_root.size = BASE
	_root.anchor_left = 0.0
	_root.anchor_top = 0.0
	_root.anchor_right = 1.0
	_root.anchor_bottom = 1.0
	_root.offset_left = 0.0
	_root.offset_top = 0.0
	_root.offset_right = 0.0
	_root.offset_bottom = 0.0

	_build_background()
	var hud := _mk(_root, Control.new(), "Hud")
	UI.fill(hud)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_build_player_plate(hud)
	_build_stamina_badge(hud)
	_build_title(hud)
	_build_top_right(hud)
	_build_map_layer(hud)
	_build_toast(hud)
	_build_team_panel(hud)
	_build_enter_button(hud)
	_build_back_button(hud)
	_build_footer(hud)

	for child in _root.get_children():
		UI.set_owner_recursive(child, _root)
	_mark_unique()

	print("[build] 节点树组装完成，共 %d 个节点" % _count(_root))


func _mark_unique() -> void:
	for n in _walk(_root):
		if str(n.name) in UNIQUE_NAMES:
			n.unique_name_in_owner = true


func _walk(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		out.append(c)
		out.append_array(_walk(c))
	return out


func _save() -> Error:
	var packed := PackedScene.new()
	var err := packed.pack(_root)
	if err != OK:
		push_error("[build] 场景打包失败：%s" % error_string(err))
		return err
	err = ResourceSaver.save(packed, OUT_PATH)
	if err != OK:
		push_error("[build] 场景保存失败：%s" % error_string(err))
		return err
	print("[build] 已写出 %s" % OUT_PATH)
	return OK


# ---------------------------------------------------------------- 背景

func _build_background() -> void:
	var bg := UI.picture(BG_PATH, TextureRect.STRETCH_KEEP_ASPECT_COVERED)
	bg.name = "Background"
	UI.fill(bg)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mk(_root, bg, "Background")

	# 压一层极淡的暖紫：新背景是概念稿底图，本身已经偏亮，
	# 压太重会把它压脏；只要让白色标签在天空区也能站住就够了。
	var tint := ColorRect.new()
	tint.name = "WarmTint"
	tint.color = Color(0.12, 0.07, 0.20, 0.08)
	UI.fill(tint)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mk(_root, tint, "WarmTint")


# ---------------------------------------------------------------- 左上：玩家信息

func _build_player_plate(hud: Control) -> void:
	var plate := _mk(hud, Control.new(), "PlayerPlate")
	UI.anchor_top_left(plate, 26, 18, 500, 152)

	var bg := UI.panel(Color(0.09, 0.07, 0.13, 0.62), 20, 2, Color(1.0, 0.85, 0.45, 0.45), 10)
	UI.place(bg, 0, 10, 500, 142)
	plate.add_child(bg)

	var frame := UI.panel(Color(0.06, 0.05, 0.09, 0.85), 26, 3, UI.GOLD, 8, Color(0, 0, 0, 0.5))
	UI.place(frame, 16, 22, 106, 106)
	plate.add_child(frame)

	var avatar := UI.picture(_player_avatar(), TextureRect.STRETCH_KEEP_ASPECT_COVERED)
	avatar.name = "AvatarTex"
	UI.place(avatar, 23, 29, 92, 92)
	plate.add_child(avatar)

	var name_label := UI.label(str(_player().get("name", "云上旅人")), 30, UI.CREAM, 6)
	name_label.name = "PlayerName"
	UI.place(name_label, 136, 26, 260, 40)
	plate.add_child(name_label)

	var pill := UI.panel(UI.GOLD, 14, 2, UI.GOLD_DEEP)
	UI.place(pill, 136, 72, 78, 28)
	plate.add_child(pill)
	var lv := UI.label("Lv.%d" % int(_player().get("level", 1)), 20, UI.INK, 0)
	lv.name = "PlayerLevel"
	lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lv.set_anchors_preset(Control.PRESET_FULL_RECT)
	pill.add_child(lv)

	var bar := ProgressBar.new()
	bar.name = "ExpBar"
	bar.max_value = float(_player().get("exp_max", 800))
	bar.value = float(_player().get("exp", 0))
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", UI.style(Color(0, 0, 0, 0.5), 8, 2, Color(0, 0, 0, 0.35)))
	bar.add_theme_stylebox_override("fill", UI.style(Color("#5BD6A6"), 8))
	UI.place(bar, 224, 78, 152, 16)
	plate.add_child(bar)

	_build_currency_row(plate, 136, 108, "coin", "GoldLabel", int(_player().get("gold", 0)))
	_build_currency_row(plate, 306, 108, "gem", "GemLabel", int(_player().get("gem", 0)))


func _build_currency_row(parent: Control, x: float, y: float, icon_name: String,
		label_name: String, amount: int) -> void:
	var ic := UI.icon("res://assets/icons/icon_%s.svg" % icon_name, 26.0,
		Color("#FFC94A") if icon_name == "coin" else Color("#7BE0FF"))
	UI.place(ic, x, y, 26, 26)
	parent.add_child(ic)

	var l := UI.label(UI.fmt_num(amount), 23, UI.CREAM, 6)
	l.name = label_name
	UI.place(l, x + 32, y - 2, 150, 30)
	parent.add_child(l)


# ---------------------------------------------------------------- 左上：体力

func _build_stamina_badge(hud: Control) -> void:
	var badge := _mk(hud, Control.new(), "StaminaBadge")
	UI.anchor_top_left(badge, 26, 182, 268, 48)

	var bg := UI.panel(Color(0.09, 0.07, 0.13, 0.60), 24, 2, Color(0.35, 0.85, 0.75, 0.5), 8)
	UI.place(bg, 0, 0, 268, 48)
	badge.add_child(bg)

	var ic := UI.icon("res://assets/icons/icon_stamina.svg", 26.0, Color("#7BE0A8"))
	UI.place(ic, 14, 11, 26, 26)
	badge.add_child(ic)

	var val := UI.label("--/--", 22, Color("#B8F5D8"), 6)
	val.name = "StaminaValue"
	UI.place(val, 48, 10, 96, 28)
	badge.add_child(val)

	var next := UI.label("", 18, Color(0.86, 0.92, 0.88, 0.72), 5)
	next.name = "StaminaNext"
	UI.place(next, 152, 14, 104, 24)
	badge.add_child(next)


# ---------------------------------------------------------------- 顶部中央：标题

func _build_title(hud: Control) -> void:
	var text := str(_select_map().get("title", "冒险关卡选择"))
	var holder: Control = UI.label_shadow(text, 76, Color("#FFE9A8"), 14,
		Color("#6B3A16"), Vector2(0, 7), Color("#4A2408"), Vector2(700, 104))
	holder.name = "TitleGroup"
	UI.anchor_top_center(holder, 700, 104, 18)
	_mk(hud, holder, "TitleGroup")

	# label_shadow 内部是「底层深色 + 顶层亮色」两层，顶层才是可见文字
	if holder.get_child_count() >= 2:
		holder.get_child(1).name = "TitleLabel"


# ---------------------------------------------------------------- 右上：功能入口

func _build_top_right(hud: Control) -> void:
	var entries: Array = _menu().get("top_right_entries", [])
	if not entries.is_empty():
		var ew := 82.0
		var gap := 16.0
		var w := ew * entries.size() + gap * (entries.size() - 1)
		var box := _mk(hud, Control.new(), "TopRight")
		UI.anchor_top_right(box, 26, 20, w, 108)

		for i in entries.size():
			var e: Dictionary = entries[i]
			var item := Control.new()
			item.name = "Entry_%s" % str(e.get("id", i))
			UI.place(item, float(i) * (ew + gap), 0, ew, 108)
			box.add_child(item)

			var btn := UI.icon_button(str(e.get("icon", "")), ew,
				Color(0.13, 0.10, 0.18, 0.78), Color(1.0, 0.85, 0.45, 0.65))
			btn.name = "Btn_%s" % str(e.get("id", i))
			UI.place(btn, 0, 0, ew, ew)
			item.add_child(btn)

			var l := UI.label(str(e.get("name", "")), 20, UI.CREAM, 6)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			UI.place(l, 0, ew + 6, ew, 26)
			item.add_child(l)

	_build_promo(hud)


## 参考图右上的悬浮礼物盒「活动」入口
func _build_promo(hud: Control) -> void:
	var promo: Dictionary = _select_map().get("promo_entry", {})
	if promo.is_empty():
		return
	var box := _mk(hud, Control.new(), "PromoEntry")
	UI.anchor_top_right(box, 26, 158, 96, 124)

	var glow := UI.glow_rect(Color("#FFC94A"), 0.45)
	UI.place(glow, -16, -16, 128, 128)
	box.add_child(glow)

	var btn := UI.icon_button(str(promo.get("icon", "")), 88,
		Color(0.16, 0.11, 0.20, 0.85), Color(1.0, 0.85, 0.45, 0.75))
	btn.name = "Btn_%s" % str(promo.get("id", "promo"))
	UI.place(btn, 4, 4, 88, 88)
	box.add_child(btn)

	var l := UI.label(str(promo.get("name", "活动")), 20, UI.CREAM, 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.place(l, 0, 92, 96, 26)
	box.add_child(l)


# ---------------------------------------------------------------- 地图容器

func _build_map_layer(hud: Control) -> void:
	var map := _mk(hud, Control.new(), "MapLayer")
	UI.fill(map)
	map.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 绘制顺序 = 子节点顺序：装饰浮岛 -> 引导线 -> 关卡节点
	var decor := _mk(map, Control.new(), "DecorLayer")
	UI.fill(decor)
	decor.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var guide := _mk(map, Control.new(), "GuideLayer")
	UI.fill(guide)
	guide.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var nodes := _mk(map, Control.new(), "NodeLayer")
	UI.fill(nodes)
	nodes.mouse_filter = Control.MOUSE_FILTER_IGNORE


# ---------------------------------------------------------------- 提示条

func _build_toast(hud: Control) -> void:
	var toast := _mk(hud, UI.panel(Color(0.09, 0.07, 0.13, 0.86), 22, 2, Color(1.0, 0.85, 0.45, 0.5), 10), "Toast")
	UI.anchor_bottom_left(toast, 26, 344, 112, 300)
	toast.visible = false

	var l := UI.label("", 21, UI.CREAM, 6)
	l.name = "ToastLabel"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.offset_left = 14
	l.offset_right = -14
	toast.add_child(l)


# ---------------------------------------------------------------- 队伍预览条

## 概念稿里这块是「3x3 3」小标签 + 三个头像框，宽度与下面的进入按钮基本齐平，
## 两件东西竖着叠成一条中轴，所以位置与尺寸都抄了稿子的实测值。
func _build_team_panel(hud: Control) -> void:
	var tp: Dictionary = _select_map().get("team_panel", {})

	var tag := UI.label(str(tp.get("label", "3x3 3")), 26, Color("#FFD98A"), 6)
	tag.name = "TeamLabel"
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UI.fill(tag)

	# 「3x3 3」在稿子里是个压在面板顶边上的小徽章，不是浮在空中的一行字，
	# 所以给它一个底衬并让它盖住面板上沿 10px。
	var badge := _mk(hud, UI.panel(Color(0.09, 0.07, 0.13, 0.88), 18, 2,
		Color(1.0, 0.85, 0.45, 0.5), 8), "TeamBadge")
	UI.anchor_bottom_center(badge, 204, 40, 275)
	badge.add_child(tag)
	tag.owner = _root

	var bar := _mk(hud, UI.panel(Color(0.09, 0.07, 0.13, 0.72), 26, 2,
		Color(1.0, 0.85, 0.45, 0.5), 12), "TeamPanel")
	UI.anchor_bottom_center(bar, 290, 97, 188)

	var slots := HBoxContainer.new()
	slots.name = "TeamSlots"
	slots.add_theme_constant_override("separation", 22)
	UI.place(slots, 15, 12, 260, 72)
	bar.add_child(slots)


# ---------------------------------------------------------------- 底部：进入关卡

func _build_enter_button(hud: Control) -> void:
	var cfg: Dictionary = _select_map().get("enter_button", {})
	var btn := Button.new()
	btn.name = "EnterButton"
	btn.text = str(cfg.get("text", "进入关卡"))
	btn.add_theme_font_override("font", load(UI.FONT_MAIN))
	btn.add_theme_font_size_override("font_size", 44)
	btn.add_theme_color_override("font_color", Color("#4A2408"))
	btn.add_theme_color_override("font_hover_color", Color("#3A1B05"))
	btn.add_theme_color_override("font_pressed_color", Color("#5C320F"))
	btn.add_theme_constant_override("outline_size", 0)
	btn.add_theme_stylebox_override("normal",
		UI.style(Color("#FFC94A"), 26, 5, Color("#B8791F"), 18, Color(0, 0, 0, 0.45)))
	btn.add_theme_stylebox_override("hover",
		UI.style(Color("#FFD975"), 26, 5, Color("#C98A2A"), 24, Color(0, 0, 0, 0.5)))
	btn.add_theme_stylebox_override("pressed",
		UI.style(Color("#E8AF33"), 26, 5, Color("#9C6413"), 8, Color(0, 0, 0, 0.45)))
	btn.add_theme_stylebox_override("focus", UI.style(Color(0, 0, 0, 0), 26))
	btn.focus_mode = Control.FOCUS_NONE
	UI.anchor_bottom_center(btn, 300, 130, 32)
	_mk(hud, btn, "EnterButton", true)

	var sub := UI.label(str(cfg.get("sub_text", "START LEVEL")), 20,
		Color(0.36, 0.20, 0.05, 0.85), 0)
	sub.name = "EnterSub"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# 主文案由 Button 自己垂直居中，副标题钉在底部，中间留出主文案的字高
	UI.place(sub, 0, 92, 300, 26)
	btn.add_child(sub)


# ---------------------------------------------------------------- 左下：返回

func _build_back_button(hud: Control) -> void:
	var btn := UI.text_button("返回", 24, Color(0.10, 0.08, 0.14, 0.74),
		Color(1.0, 0.85, 0.45, 0.5), UI.CREAM, 18)
	btn.name = "BackButton"
	UI.anchor_bottom_left(btn, 26, 150, 56, 30)
	_mk(hud, btn, "BackButton", true)


# ---------------------------------------------------------------- 右下：状态

## 统计行靠右下角：这一行的内容会随「累计星级 / 材料仓」增长，
## 原来放左下（x=200 起、宽 520）时长文案会向右溢出，正好压到底部中央的
## 「进入关卡」按钮下面。改成右下右对齐后，无论文案多长都不会撞按钮。
func _build_footer(hud: Control) -> void:
	var info := UI.label("", 17, Color(1, 1, 1, 0.84), 5)
	info.name = "FooterInfo"
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	info.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	UI.anchor_bottom_right(info, 24, 700, 30, 44)
	_mk(hud, info, "FooterInfo", true)


# ---------------------------------------------------------------- 工具

func _mk(parent: Node, node: Node, name: String, unique: bool = false) -> Node:
	node.name = name
	parent.add_child(node)
	node.owner = _root
	if unique and node is Node:
		(node as Node).unique_name_in_owner = true
	return node


func _count(node: Node) -> int:
	var n := 1
	for c in node.get_children():
		n += _count(c)
	return n


func _section(key: String) -> Dictionary:
	var v: Variant = _data.get(key, {})
	return v if typeof(v) == TYPE_DICTIONARY else {}


func _menu() -> Dictionary:
	return _section("menu")


func _select_map() -> Dictionary:
	var adv := _section("adventure")
	var v: Variant = adv.get("select_map", {})
	return v if typeof(v) == TYPE_DICTIONARY else {}


func _player() -> Dictionary:
	return _menu().get("player", {})


func _player_avatar() -> String:
	return str(_player().get("avatar", "res://assets/art/characters/char_knight.png"))
