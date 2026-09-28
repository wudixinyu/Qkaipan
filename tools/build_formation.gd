extends SceneTree
## build_formation.gd —— 程序化构建「卡牌选择与编队」场景
##
## 用法（headless）：
##   Godot --headless --path <项目> --script res://tools/build_formation.gd
##
## 产出：res://scenes/formation.tscn
##
## 设计约定（与 build_stage_select / build_main_menu 同构）：
##   1. 本脚本不依赖任何 autoload —— --script 模式下 autoload 全局名不可见，
##      所以配置直接读 res://data/game_data.json。
##   2. 静态布局全部用「锚点 + 偏移」写死，换分辨率不会错位。
##      **像素常量只写在这里**，formation.gd 只负责填内容与接线。
##   3. 动态内容（卡牌陈列、3x3 棋盘格、卡库缩略图、筛选/排序弹层里的选项）
##      只留空容器，运行时由 formation.gd 按配置填充。
##   4. 文案全部取自 game_data.json 的 formation 段，场景里不写死。
##
## 版面（1920x1080）：
##   ┌ 顶部操作栏（选择 / 筛选 / 排序 + 搜索框）              队伍战力 ┐
##   │           选择你的英雄 / 组成你的冒险小队                      │
##   │                卡牌陈列区（2.5D 扇形）                         │
##   ├ 编队棋盘 ┬ 备选英雄库 ┬ 战术信息 2x2 ┬ 阵容预设 / 指令 ┤
##   └ 返回主界面                                    提示条        ┘

const UI := preload("res://tools/ui_kit.gd")
const GROWTH := preload("res://scripts/growth_core.gd")
const CardFanScript := preload("res://scripts/card_fan.gd")

## formation.gd 引用了 autoload（GameDB / SaveDB / RealmDB），而 autoload 全局标识符
## 要等主循环起来才注册，所以这里只能延迟 load()，否则场景根部挂不上脚本。
const FORMATION_SCRIPT_PATH := "res://scripts/formation.gd"

const DATA_PATH := "res://data/game_data.json"
const OUT_PATH := "res://scenes/formation.tscn"
const BG_PATH := "res://assets/art/bg/bg_stage_select.png"
const BASE := Vector2(1920, 1080)

## 运行时用 %Name 直取的节点
const UNIQUE_NAMES := [
	"Background", "WarmTint",
	"BackButton",
	"TopBar", "SearchBox", "SearchEdit", "SearchIcon",
	"TitleLabel", "SubTitle",
	"CardStage",
	"PowerBadge", "PowerLabel", "PowerValue", "PowerParts",
	"BoardPanel", "BoardTitle", "BoardCount", "BoardGrid", "BoardHint",
	"LibraryPanel", "LibraryTitle", "LibraryCount", "LibraryScroll", "LibraryGrid",
	"TacticalPanel",
	"CommandPanel", "PresetTitle", "PresetBar", "PresetHint",
	"QuickFillButton", "ClearButton", "DeployButton", "RemoveButton",
	"ConfirmButton", "ConfirmSub",
	"Toast", "ToastLabel",
	"PopupLayer", "FilterPanel", "FilterTitle", "FilterGroups",
	"FilterResetButton", "FilterApplyButton",
	"SortPanel", "SortTitle", "SortOptions",
]

# ---------------------------------------------------------------- 版面常量

const PANEL_BG := Color(0.09, 0.07, 0.13, 0.80)
const PANEL_BG_SOFT := Color(0.09, 0.07, 0.13, 0.66)
const PANEL_BORDER := Color(1.0, 0.85, 0.45, 0.45)
const PANEL_BORDER_SOFT := Color(1.0, 0.85, 0.45, 0.28)

const TOP_BAR := Rect2(316, 20, 1424, 68)
const TAB_SIZE := Vector2(128, 44)
const TAB_GAP := 12.0
const SEARCH_BOX := Rect2(1330, 30, 382, 48)

const BACK_BUTTON := Rect2(20, 1010, 260, 60)

const TITLE_BOX := Vector2(900, 96)
const TITLE_Y := 72.0
const SUBTITLE_Y := 168.0

const STAGE := Rect2(300, 240, 1320, 432)

const POWER_BADGE := Rect2(1450, 96, 440, 76)

const ZONE_Y := 682.0
const ZONE_H := 328.0
const BOARD_X := 20.0
const BOARD_W := 352.0
const LIB_X := 386.0
const LIB_W := 498.0
const TAC_X := 898.0
const TAC_W := 526.0
const CMD_X := 1438.0
const CMD_W := 462.0

const BOARD_CELL := 76.0
const BOARD_GAP := 10.0
const BOARD_GUTTER := 52.0
const BOARD_GRID_Y := 48.0

const LIB_PAD := 16.0
const LIB_GRID_Y := 52.0

const TAC_PAD := 8.0
const TAC_GAP := 12.0

const TOAST := Rect2(620, 1012, 680, 58)

const POPUP_TOP := 96.0
const FILTER_PANEL := Rect2(330, 96, 680, 500)
const SORT_PANEL := Rect2(640, 96, 420, 420)

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
	_root.name = "Formation"
	var script: Script = load(FORMATION_SCRIPT_PATH)
	if script == null:
		push_error("[build] 无法加载 %s" % FORMATION_SCRIPT_PATH)
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

	var preview_count := _build_card_stage(hud)
	_build_top_bar(hud)
	_build_title(hud)
	_build_power_badge(hud)
	_build_board_panel(hud)
	_build_library_panel(hud)
	_build_tactical_panel(hud)
	_build_command_panel(hud)
	_build_back_button(hud)
	_build_toast(hud)
	_build_popups(hud)

	# CardFan.configure() 内部会 new 出 CardView 及其全部子节点，
	# 这些节点带不上 owner，必须统一补一遍，否则不会写进场景。
	for child in _root.get_children():
		UI.set_owner_recursive(child, _root)
	_mark_unique()

	print("[build] 节点树组装完成，共 %d 个节点" % _count(_root))
	print("[build] 写入编辑器预览卡牌 %d 张" % preview_count)


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

	# 编队页比选关页多了四块底栏，底图亮度要压得更低，
	# 否则天空区的橙黄天光会把半透明面板里的白字糊掉。
	var tint := ColorRect.new()
	tint.name = "WarmTint"
	tint.color = Color(0.10, 0.06, 0.18, 0.30)
	UI.fill(tint)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mk(_root, tint, "WarmTint")


# ---------------------------------------------------------------- 顶部操作栏

func _build_top_bar(hud: Control) -> void:
	var bar := _mk(hud, UI.panel(PANEL_BG_SOFT, 26, 2, PANEL_BORDER_SOFT, 14), "TopBar")
	UI.place(bar, TOP_BAR.position.x, TOP_BAR.position.y, TOP_BAR.size.x, TOP_BAR.size.y)

	var tabs: Array = _formation().get("top_tabs", [])
	var tab_x := 24.0
	var y := (TOP_BAR.size.y - TAB_SIZE.y) * 0.5
	for raw in tabs:
		var t: Dictionary = raw
		var btn := UI.text_button(str(t.get("name", "")), 27,
			Color(0.13, 0.10, 0.18, 0.86), PANEL_BORDER_SOFT, UI.CREAM, 20)
		btn.name = "Tab_%s" % str(t.get("id", "tab"))
		btn.tooltip_text = str(t.get("hint", ""))
		UI.place(btn, tab_x, y, TAB_SIZE.x, TAB_SIZE.y)
		bar.add_child(btn)
		tab_x += TAB_SIZE.x + TAB_GAP

	# ---- 搜索框 ----
	var box := _mk(bar, Control.new(), "SearchBox")
	UI.place(box, SEARCH_BOX.position.x - TOP_BAR.position.x,
		SEARCH_BOX.position.y - TOP_BAR.position.y, SEARCH_BOX.size.x, SEARCH_BOX.size.y)

	var box_bg := UI.panel(Color(0.05, 0.04, 0.08, 0.86), 22, 2, PANEL_BORDER_SOFT)
	box_bg.name = "SearchBoxBg"
	UI.fill(box_bg)
	box.add_child(box_bg)

	var ic := UI.icon("res://assets/icons/icon_search.svg", 24.0, Color(1, 1, 1, 0.55))
	ic.name = "SearchIcon"
	UI.place(ic, 14, 12, 24, 24)
	box.add_child(ic)

	var search: Dictionary = _formation().get("search", {})
	var edit := LineEdit.new()
	edit.name = "SearchEdit"
	edit.placeholder_text = str(search.get("placeholder", "搜索英雄名称..."))
	edit.tooltip_text = str(search.get("hint", ""))
	edit.add_theme_font_override("font", load(UI.FONT_MAIN))
	edit.add_theme_font_size_override("font_size", 23)
	edit.add_theme_color_override("font_color", UI.CREAM)
	edit.add_theme_color_override("font_placeholder_color", Color(1, 1, 1, 0.42))
	edit.add_theme_color_override("caret_color", UI.GOLD)
	edit.add_theme_stylebox_override("normal", UI.style(Color(0, 0, 0, 0), 20))
	edit.add_theme_stylebox_override("focus", UI.style(Color(0, 0, 0, 0), 20))
	UI.place(edit, 48, 8, SEARCH_BOX.size.x - 62, 32)
	box.add_child(edit)


# ---------------------------------------------------------------- 标题

func _build_title(hud: Control) -> void:
	var holder: Control = UI.label_shadow(str(_formation().get("title", "选择你的英雄")),
		74, Color("#FFE9A8"), 14, Color("#6B3A16"), Vector2(0, 7), Color("#4A2408"),
		TITLE_BOX)
	holder.name = "TitleGroup"
	UI.anchor_top_center(holder, TITLE_BOX.x, TITLE_BOX.y, TITLE_Y)
	_mk(hud, holder, "TitleGroup")
	if holder.get_child_count() >= 2:
		holder.get_child(1).name = "TitleLabel"

	var sub := UI.label(str(_formation().get("subtitle", "")), 32, UI.CREAM, 8,
		Color("#43220A"))
	sub.name = "SubTitle"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.anchor_top_center(sub, 800, 44, SUBTITLE_Y)
	_mk(hud, sub, "SubTitle", true)


# ---------------------------------------------------------------- 卡牌陈列

func _build_card_stage(hud: Control) -> int:
	var fan: CardFan = CardFanScript.new()
	fan.name = "CardStage"
	UI.place(fan, STAGE.position.x, STAGE.position.y, STAGE.size.x, STAGE.size.y)
	_mk(hud, fan, "CardStage", true)

	# —— 编辑器预览用的一份数据（运行时会被 formation.gd 用 RealmDB 真值整批重建）
	var items: Array = []
	for char_id in _lineup_order():
		var cfg := _character(char_id)
		if cfg.is_empty():
			continue
		var level := int(cfg.get("demo_level", 1))
		var star := int(cfg.get("demo_star", 1))
		items.append({
			"char_id": str(char_id),
			"config": cfg,
			"card": {"char_id": str(char_id), "level": level, "star": star,
				"exp": 0, "equipment": []},
			"stats": _preview_stats(cfg, level, star),
		})
	fan.configure(items, {
		"rarities": _section("rarities").get("table", {}),
		"elements": _section("elements").get("table", {}),
	}, _card_box(), _fan_cfg())
	return items.size()


# ---------------------------------------------------------------- 队伍战力（右上角）

func _build_power_badge(hud: Control) -> void:
	var badge := _mk(hud, UI.panel(PANEL_BG, 22, 2, PANEL_BORDER, 12), "PowerBadge")
	UI.place(badge, POWER_BADGE.position.x, POWER_BADGE.position.y,
		POWER_BADGE.size.x, POWER_BADGE.size.y)

	var ic := UI.icon("res://assets/icons/icon_star.svg", 34.0, Color("#FFD45E"))
	UI.place(ic, 14, 21, 34, 34)
	badge.add_child(ic)

	var team: Dictionary = _formation().get("team", {})
	var cap := UI.label(str(team.get("power_label", "队伍战力")), 22, Color("#B8F5D8"), 5)
	cap.name = "PowerLabel"
	UI.place(cap, 58, 8, 200, 30)
	badge.add_child(cap)

	var value := UI.label("0", 36, Color("#FFE9A8"), 7)
	value.name = "PowerValue"
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UI.place(value, 180, 4, 246, 42)
	badge.add_child(value)

	var parts := UI.label("", 18, Color(1, 1, 1, 0.74), 4)
	parts.name = "PowerParts"
	parts.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UI.place(parts, 58, 44, 368, 26)
	badge.add_child(parts)


# ---------------------------------------------------------------- 左：3x3 编队棋盘

func _build_board_panel(hud: Control) -> void:
	var panel := _mk(hud, UI.panel(PANEL_BG, 22, 2, PANEL_BORDER, 12), "BoardPanel")
	UI.place(panel, BOARD_X, ZONE_Y, BOARD_W, ZONE_H)

	var team: Dictionary = _formation().get("team", {})
	var title := UI.label(str(team.get("label", "编队棋盘")), 24, UI.CREAM, 6)
	title.name = "BoardTitle"
	UI.place(title, 18, 12, 190, 34)
	panel.add_child(title)

	var count := UI.label("", 20, Color("#FFD98A"), 5)
	count.name = "BoardCount"
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UI.place(count, 180, 15, 154, 30)
	panel.add_child(count)

	var hint := UI.label(str(team.get("hint", "")), 16, Color(1, 1, 1, 0.62), 4)
	hint.name = "BoardHint"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.place(hint, 8, ZONE_H - 26, BOARD_W - 16, 22)
	panel.add_child(hint)

	# 棋盘格留空容器：行序 = 配置的 row_order（前排在上，正对敌方）
	var grid := _mk(panel, Control.new(), "BoardGrid")
	UI.place(grid, 0, BOARD_GRID_Y, BOARD_W, BOARD_CELL * 3.0 + BOARD_GAP * 2.0)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE


# ---------------------------------------------------------------- 中：备选英雄库

func _build_library_panel(hud: Control) -> void:
	var panel := _mk(hud, UI.panel(PANEL_BG, 22, 2, PANEL_BORDER, 12), "LibraryPanel")
	UI.place(panel, LIB_X, ZONE_Y, LIB_W, ZONE_H)

	var lib: Dictionary = _formation().get("library", {})
	var title := UI.label(str(lib.get("title", "备选英雄库")), 24, UI.CREAM, 6)
	title.name = "LibraryTitle"
	UI.place(title, LIB_PAD, 12, 240, 34)
	panel.add_child(title)

	var count := UI.label("", 19, Color("#FFD98A"), 5)
	count.name = "LibraryCount"
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UI.place(count, LIB_W - 250 - LIB_PAD, 15, 250, 30)
	panel.add_child(count)

	var scroll := _mk(panel, ScrollContainer.new(), "LibraryScroll")
	UI.place(scroll, LIB_PAD, LIB_GRID_Y, LIB_W - LIB_PAD * 2.0,
		ZONE_H - LIB_GRID_Y - 10.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var grid := GridContainer.new()
	grid.name = "LibraryGrid"
	grid.columns = maxi(1, int(lib.get("columns", 2)))
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)


# ---------------------------------------------------------------- 中右：战术信息 2x2

func _build_tactical_panel(hud: Control) -> void:
	var panel := _mk(hud, Control.new(), "TacticalPanel")
	UI.place(panel, TAC_X, ZONE_Y, TAC_W, ZONE_H)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var boxes: Array = _formation().get("tactical", {}).get("boxes", [])
	var box_w := (TAC_W - TAC_PAD * 2.0 - TAC_GAP) * 0.5
	var box_h := (ZONE_H - TAC_PAD * 2.0 - TAC_GAP) * 0.5
	for i in boxes.size():
		var b: Dictionary = boxes[i]
		var col := i % 2
		var row := i / 2
		var x := TAC_PAD + float(col) * (box_w + TAC_GAP)
		var y := TAC_PAD + float(row) * (box_h + TAC_GAP)
		panel.add_child(_make_tactic_box(str(b.get("id", "box")),
			str(b.get("title", "")), x, y, box_w, box_h))


func _make_tactic_box(id: String, title_text: String, x: float, y: float,
		w: float, h: float) -> Control:
	var box := Control.new()
	box.name = "TacticBox_%s" % id
	UI.place(box, x, y, w, h)

	var bg := UI.panel(Color(0.07, 0.05, 0.11, 0.72), 18, 2, PANEL_BORDER_SOFT)
	UI.fill(bg)
	box.add_child(bg)

	var title := UI.label(title_text, 21, Color("#FFD98A"), 5)
	title.name = "Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.place(title, 8, 7, w - 16, 30)
	box.add_child(title)

	var body := Control.new()
	body.name = "Body"
	UI.place(body, 10, 40, w - 20, h - 48)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 裁掉溢出：正文是运行时按配置拼的，长度不可控，宁可截断也不能让它压到下一格
	body.clip_contents = true
	box.add_child(body)
	return box


# ---------------------------------------------------------------- 右：预设与指令

func _build_command_panel(hud: Control) -> void:
	var panel := _mk(hud, UI.panel(PANEL_BG, 22, 2, PANEL_BORDER, 12), "CommandPanel")
	UI.place(panel, CMD_X, ZONE_Y, CMD_W, ZONE_H)

	var title := UI.label(str(_formation().get("preset_label", "阵容预设")), 20,
		Color(1, 1, 1, 0.72), 4)
	title.name = "PresetTitle"
	UI.place(title, 16, 10, 220, 26)
	panel.add_child(title)

	var bar := _mk(panel, HBoxContainer.new(), "PresetBar")
	bar.add_theme_constant_override("separation", 8)
	UI.place(bar, 14, 38, CMD_W - 28, 50)

	var hint := UI.label("", 16, Color(1, 1, 1, 0.6), 4)
	hint.name = "PresetHint"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.place(hint, 14, 92, CMD_W - 28, 20)
	panel.add_child(hint)

	var half := (CMD_W - 28.0 - 10.0) * 0.5
	panel.add_child(_mk_button("QuickFillButton",
		str(_formation().get("quick_fill", {}).get("text", "一键上阵")), 16, 118, half, 48, true))
	panel.add_child(_mk_button("ClearButton",
		str(_formation().get("clear_text", "清空")), 16 + half + 10.0, 118, half, 48, false))
	panel.add_child(_mk_button("DeployButton",
		str(_formation().get("quick_deploy", {}).get("text", "上阵")), 16, 174, half, 48, false))
	panel.add_child(_mk_button("RemoveButton",
		str(_formation().get("quick_remove", {}).get("text", "下阵")), 16 + half + 10.0, 174, half, 48, false))

	# ---- 确认选择（概念稿里是右下角那块金色大按钮）----
	var cfg: Dictionary = _formation().get("confirm_button", {})
	var btn := Button.new()
	btn.name = "ConfirmButton"
	btn.text = str(cfg.get("text", "确认选择"))
	btn.add_theme_font_override("font", load(UI.FONT_MAIN))
	btn.add_theme_font_size_override("font_size", 38)
	btn.add_theme_color_override("font_color", Color("#4A2408"))
	btn.add_theme_color_override("font_hover_color", Color("#3A1B05"))
	btn.add_theme_color_override("font_pressed_color", Color("#5C320F"))
	btn.add_theme_constant_override("outline_size", 0)
	btn.add_theme_stylebox_override("normal",
		UI.style(Color("#FFC94A"), 24, 5, Color("#B8791F"), 16, Color(0, 0, 0, 0.45)))
	btn.add_theme_stylebox_override("hover",
		UI.style(Color("#FFD975"), 24, 5, Color("#C98A2A"), 22, Color(0, 0, 0, 0.5)))
	btn.add_theme_stylebox_override("pressed",
		UI.style(Color("#E8AF33"), 24, 5, Color("#9C6413"), 8, Color(0, 0, 0, 0.45)))
	btn.add_theme_stylebox_override("focus", UI.style(Color(0, 0, 0, 0), 24))
	btn.focus_mode = Control.FOCUS_NONE
	UI.place(btn, 14, 234, CMD_W - 28, 80)
	panel.add_child(btn)

	var sub := UI.label(str(cfg.get("sub_text", "FORMATION")), 19,
		Color(0.36, 0.20, 0.05, 0.85), 0)
	sub.name = "ConfirmSub"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UI.place(sub, 0, 54, CMD_W - 28, 24)
	btn.add_child(sub)


func _mk_button(node_name: String, text: String, x: float, y: float,
		w: float, h: float, primary: bool) -> Button:
	var bg := Color(0.13, 0.10, 0.18, 0.86) if primary else Color(0.10, 0.08, 0.14, 0.80)
	var btn := UI.text_button(text, 21, bg,
		Color(1.0, 0.85, 0.45, 0.55) if primary else Color(1, 1, 1, 0.28),
		UI.CREAM if primary else Color(1, 1, 1, 0.82), 18)
	btn.name = node_name
	UI.place(btn, x, y, w, h)
	return btn


# ---------------------------------------------------------------- 返回

func _build_back_button(hud: Control) -> void:
	var cfg: Dictionary = _formation().get("back_button", {})
	var btn := UI.text_button("◀  " + str(cfg.get("text", "返回主界面")), 25,
		Color(0.10, 0.08, 0.14, 0.80), Color(1.0, 0.85, 0.45, 0.5), UI.CREAM, 18)
	btn.name = "BackButton"
	UI.place(btn, BACK_BUTTON.position.x, BACK_BUTTON.position.y,
		BACK_BUTTON.size.x, BACK_BUTTON.size.y)
	_mk(hud, btn, "BackButton", true)


# ---------------------------------------------------------------- 提示条

func _build_toast(hud: Control) -> void:
	var toast := _mk(hud, UI.panel(Color(0.09, 0.07, 0.13, 0.90), 20, 2,
		Color(1.0, 0.85, 0.45, 0.5), 12), "Toast")
	UI.place(toast, TOAST.position.x, TOAST.position.y, TOAST.size.x, TOAST.size.y)
	toast.visible = false

	var l := UI.label("", 20, UI.CREAM, 6)
	l.name = "ToastLabel"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UI.fill(l)
	l.offset_left = 16
	l.offset_right = -16
	toast.add_child(l)


# ---------------------------------------------------------------- 弹层（筛选 / 排序）

func _build_popups(hud: Control) -> void:
	var layer := _mk(hud, Control.new(), "PopupLayer")
	UI.fill(layer)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# ---- 筛选 ----
	var fp := _mk(layer, UI.panel(Color(0.08, 0.06, 0.12, 0.97), 22, 3, PANEL_BORDER, 20),
		"FilterPanel")
	UI.place(fp, FILTER_PANEL.position.x, FILTER_PANEL.position.y,
		FILTER_PANEL.size.x, FILTER_PANEL.size.y)
	fp.visible = false

	var ft := UI.label(str(_formation().get("filters", {}).get("title", "筛选")),
		26, Color("#FFD98A"), 6)
	ft.name = "FilterTitle"
	UI.place(ft, 20, 14, 300, 34)
	fp.add_child(ft)

	var groups := _mk(fp, VBoxContainer.new(), "FilterGroups")
	groups.add_theme_constant_override("separation", 10)
	UI.place(groups, 20, 56, FILTER_PANEL.size.x - 40, 372)

	var filters: Dictionary = _formation().get("filters", {})
	var fb_w := 190.0
	var reset_btn := UI.text_button(str(filters.get("reset_text", "重置")), 22,
		Color(0.13, 0.10, 0.18, 0.9), Color(1, 1, 1, 0.3), UI.CREAM, 18)
	reset_btn.name = "FilterResetButton"
	UI.place(reset_btn, 20, FILTER_PANEL.size.y - 68, fb_w, 52)
	fp.add_child(reset_btn)

	var apply_btn := UI.text_button(str(filters.get("apply_text", "确定")), 24,
		Color("#FFC94A"), Color("#B8791F"), Color("#4A2408"), 18)
	apply_btn.name = "FilterApplyButton"
	UI.place(apply_btn, FILTER_PANEL.size.x - 20 - fb_w, FILTER_PANEL.size.y - 68, fb_w, 52)
	fp.add_child(apply_btn)

	# ---- 排序 ----
	var sp := _mk(layer, UI.panel(Color(0.08, 0.06, 0.12, 0.97), 22, 3, PANEL_BORDER, 20),
		"SortPanel")
	UI.place(sp, SORT_PANEL.position.x, SORT_PANEL.position.y,
		SORT_PANEL.size.x, SORT_PANEL.size.y)
	sp.visible = false

	var st := UI.label("排序", 26, Color("#FFD98A"), 6)
	st.name = "SortTitle"
	UI.place(st, 20, 14, 300, 34)
	sp.add_child(st)

	var opts := _mk(sp, VBoxContainer.new(), "SortOptions")
	opts.add_theme_constant_override("separation", 8)
	UI.place(opts, 20, 58, SORT_PANEL.size.x - 40, SORT_PANEL.size.y - 76)


# ---------------------------------------------------------------- 配置读取

func _section(key: String) -> Dictionary:
	var v: Variant = _data.get(key, {})
	return v if typeof(v) == TYPE_DICTIONARY else {}


func _formation() -> Dictionary:
	return _section("formation")


func _menu() -> Dictionary:
	return _section("menu")


func _character(id: String) -> Dictionary:
	# characters 是数组不是字典，不能走 _section()（那个只认 Dictionary）
	for c in _data.get("characters", []):
		if str(c.get("id", "")) == id:
			return c
	return {}


func _lineup_order() -> Array:
	var v: Variant = _menu().get("demo_lineup", [])
	return v if v is Array else []


func _card_box() -> Vector2:
	var box: Dictionary = _menu().get("card_box", {})
	return Vector2(float(box.get("w", 336)), float(box.get("h", 520)))


func _fan_cfg() -> Dictionary:
	var v: Variant = _formation().get("fan", {})
	if typeof(v) == TYPE_DICTIONARY and not (v as Dictionary).is_empty():
		return v
	return _menu().get("fan", {})


## 仅用于场景内预览的属性换算：走 GrowthCore，与运行时 RealmDB.stats_of 同一份公式
func _preview_stats(cfg: Dictionary, level: int, star: int) -> Dictionary:
	var bonus: Array = _section("growth").get("star_up", {}).get("per_star_attr_bonus", [])
	return GROWTH.stats_of(cfg, level, star, bonus)


# ---------------------------------------------------------------- 工具

func _mk(parent: Node, node: Node, name: String, unique: bool = false) -> Node:
	node.name = name
	parent.add_child(node)
	node.owner = _root
	if unique:
		(node as Node).unique_name_in_owner = true
	return node


func _count(node: Node) -> int:
	var n := 1
	for c in node.get_children():
		n += _count(c)
	return n
