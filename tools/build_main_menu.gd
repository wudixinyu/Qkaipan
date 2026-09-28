extends SceneTree
## build_main_menu.gd —— 程序化构建主界面场景
##
## 用法（headless）：
##   Godot --headless --path <项目> --script res://tools/build_main_menu.gd
##
## 产出：res://scenes/main_menu.tscn
##
## 设计约定：
##   1. 本脚本不依赖任何 autoload —— autoload 在 --script 模式下不保证存在，
##      所以配置直接读 res://data/game_data.json。
##   2. 静态布局全部用「锚点 + 偏移」写死，因此换分辨率不会错位；
##      只有卡牌扇形排布用中心点数学，随视口宽度自适应。
##   3. 卡牌节点会带一份预览数据写进场景，方便在编辑器里直接看到效果；
##      运行时会由 main_menu.gd 用 RealmDB 的真实数据整批重建。

const UI := preload("res://tools/ui_kit.gd")
const GROWTH := preload("res://scripts/growth_core.gd")
const CardFanScript := preload("res://scripts/card_fan.gd")

## 注意：main_menu.gd 里引用了 autoload（GameDB / SaveDB / RealmDB / StaminaSys），
## 而 autoload 的全局标识符在 --script 模式下要等主循环起来才注册。
## 所以这里不能用 preload，必须延迟到第一帧用 load()，否则编译失败会导致
## 场景根部挂不上脚本。
const MAIN_MENU_SCRIPT_PATH := "res://scripts/main_menu.gd"

const DATA_PATH := "res://data/game_data.json"
const OUT_PATH := "res://scenes/main_menu.tscn"
const BASE := Vector2(1920, 1080)

## 这些节点在场景里标记为「唯一名」，运行时用 %Name 直接取，避免路径漂移
const UNIQUE_NAMES := [
	"PlayerName", "PlayerLevel", "AvatarTex", "ExpBar", "GoldLabel", "GemLabel",
	"StaminaValue", "StaminaNext", "Toast", "ToastLabel", "CardFan", "TeamSlots",
	"TeamPowerLabel", "StartButton", "FooterInfo",
]

var _root: Control
var _data: Dictionary = {}
var _done := false


## 不用 _initialize()：那个阶段 autoload 还没实例化，
## 拿不到 GameDB / SaveDB，也没法编译引用它们的脚本。
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
	_root.name = "MainMenu"
	var mm_script: Script = load(MAIN_MENU_SCRIPT_PATH)
	if mm_script == null:
		push_error("[build] 无法加载 %s" % MAIN_MENU_SCRIPT_PATH)
	_root.set_script(mm_script)
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
	_build_right_rail(hud)
	_build_toast(hud)
	var preview_count := _build_card_fan(hud)
	_build_team_bar(hud)
	_build_start_button(hud)
	_build_footer(hud)

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
	var bg := UI.picture("res://assets/art/bg/bg_islands.png", TextureRect.STRETCH_KEEP_ASPECT_COVERED)
	bg.name = "Background"
	UI.fill(bg)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mk(_root, bg, "Background")

	var tint := ColorRect.new()
	tint.name = "WarmTint"
	tint.color = Color(0.18, 0.08, 0.24, 0.12)
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

	var exp_max := float(_player().get("exp_max", 800))
	var bar := ProgressBar.new()
	bar.name = "ExpBar"
	bar.max_value = exp_max
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
	var group := _mk(hud, Control.new(), "TitleGroup")
	UI.anchor_top_center(group, 760, 208, 12)

	var stars := HBoxContainer.new()
	stars.name = "StarRow"
	stars.add_theme_constant_override("separation", 6)
	var widths := [30.0, 36.0, 44.0, 36.0, 30.0]
	var total := 0.0
	for w in widths:
		total += w
	total += 6.0 * 4.0
	UI.place(stars, (760.0 - total) / 2.0, 2, total, 46)
	for w in widths:
		var s := UI.icon("res://assets/icons/icon_star.svg", w, Color("#FFD45E"))
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		stars.add_child(s)
	group.add_child(stars)

	var title: Control = UI.label_shadow(str(_meta().get("title", "卡牌大冒险")), 96,
		Color("#FFE9A8"), 16, Color("#6B3A16"), Vector2(0, 9), Color("#4A2408"),
		Vector2(760, 124))
	title.name = "Title"
	UI.place(title, 0, 44, 760, 124)
	group.add_child(title)

	var sub := UI.label(str(_meta().get("subtitle", "")), 26, Color("#FFD98A"), 7,
		Color(0.28, 0.14, 0.03, 0.85))
	sub.name = "Subtitle"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.place(sub, 0, 166, 760, 34)
	group.add_child(sub)


# ---------------------------------------------------------------- 右上：功能入口

func _build_top_right(hud: Control) -> void:
	var entries: Array = _menu().get("top_right_entries", [])
	var n := entries.size()
	if n == 0:
		return
	var ew := 82.0
	var gap := 16.0
	var w := ew * n + gap * (n - 1)
	var box := _mk(hud, Control.new(), "TopRight")
	UI.anchor_top_right(box, 26, 20, w, 108)

	for i in n:
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


# ---------------------------------------------------------------- 右侧：玩法入口

## 竖栏 = 玩法模式（modes，占位）+ 分隔线 + 系统入口（menu.system_entries，真的能进）。
## 两组共用同一套外观与节奏，只有「点击行为」不同：mode 弹待接入提示，system 按 route 切场景。
const RAIL_EH := 68.0
const RAIL_GAP := 14.0
const RAIL_W := 232.0
const RAIL_DIVIDER_H := 2.0


func _rail_block_h(count: int) -> float:
	if count <= 0:
		return 0.0
	return RAIL_EH * float(count) + RAIL_GAP * float(count - 1)


func _build_right_rail(hud: Control) -> void:
	var modes: Array = _data.get("modes", [])
	var systems: Array = _menu().get("system_entries", [])
	if modes.is_empty() and systems.is_empty():
		return

	# 只有两组都有东西时才画分隔线，否则它会孤零零挂在顶上或底下
	var divider := RAIL_DIVIDER_H + RAIL_GAP * 2.0 if (not modes.is_empty() and not systems.is_empty()) else 0.0
	var h := _rail_block_h(modes.size()) + divider + _rail_block_h(systems.size())

	var rail := _mk(hud, Control.new(), "RightRail")
	UI.anchor_right_center(rail, RAIL_W, h, 26)

	var y := 0.0
	for i in modes.size():
		rail.add_child(_make_rail_entry(modes[i], "Mode", i, y))
		y += RAIL_EH + RAIL_GAP

	if divider > 0.0:
		var line := ColorRect.new()
		line.name = "RailDivider"
		line.color = Color(1, 1, 1, 0.16)
		UI.place(line, 12, y + RAIL_GAP, RAIL_W - 24, RAIL_DIVIDER_H)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rail.add_child(line)
		y += divider

	for i in systems.size():
		rail.add_child(_make_rail_entry(systems[i], "Sys", i, y))
		y += RAIL_EH + RAIL_GAP


## 一条竖栏入口：图标 + 名称 + 角标。
## prefix=="Mode" 的是玩法占位（尚无 route）：整条降亮 + 右上角挂一枚「待开放」徒章，
## 让“能进的”（Sys_）与“占位的”（Mode_）一眼可分。徒章是按钮的子节点，
## 不会新增竖栏直接子节点（不影响分隔线计数）；且加在名称 Label 之后（不影响取文案）。
func _make_rail_entry(cfg: Dictionary, prefix: String, index: int, y: float) -> Button:
	var placeholder := prefix == "Mode"
	var accent := Color(str(cfg.get("color", "#FFC94A")))
	var btn := Button.new()
	btn.name = "%s_%s" % [prefix, str(cfg.get("id", index))]
	btn.tooltip_text = str(cfg.get("hint", ""))
	var bg_a := 0.42 if placeholder else 0.66
	var border := accent.darkened(0.25) if not placeholder else accent.darkened(0.45)
	btn.add_theme_stylebox_override("normal",
		UI.style(Color(0.09, 0.07, 0.13, bg_a), 18, 2, border, 8))
	btn.add_theme_stylebox_override("hover",
		UI.style(Color(0.14, 0.11, 0.19, 0.80), 18, 2, accent.lightened(0.15), 12))
	btn.add_theme_stylebox_override("pressed",
		UI.style(Color(0.07, 0.05, 0.10, 0.80), 18, 2, accent, 4))
	btn.add_theme_stylebox_override("focus", UI.style(Color(0, 0, 0, 0), 18))
	btn.focus_mode = Control.FOCUS_NONE
	UI.place(btn, 0, y, RAIL_W, RAIL_EH)

	var ic := UI.icon(str(cfg.get("icon", "")), 36.0, accent)
	if placeholder:
		ic.modulate = Color(1, 1, 1, 0.5)
	UI.place(ic, 14, 16, 36, 36)
	btn.add_child(ic)

	var nm := UI.label(str(cfg.get("name", "")), 24, UI.CREAM, 6)
	if placeholder:
		nm.modulate = Color(1, 1, 1, 0.72)
	UI.place(nm, 60, 8, 164, 30)
	btn.add_child(nm)

	var tag := UI.label(str(cfg.get("tag", "")), 16, accent.lightened(0.25), 5)
	if placeholder:
		tag.modulate = Color(1, 1, 1, 0.6)
	UI.place(tag, 60, 38, 164, 22)
	btn.add_child(tag)

	if placeholder:
		var soon_bg := UI.panel(Color(0.30, 0.26, 0.36, 0.92), 10, 1, Color(1, 1, 1, 0.22))
		UI.place(soon_bg, RAIL_W - 78, 7, 68, 22)
		btn.add_child(soon_bg)
		var soon := UI.label("待开放", 14, Color(1, 1, 1, 0.82), 4)
		soon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		soon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		UI.place(soon, RAIL_W - 78, 7, 68, 22)
		btn.add_child(soon)

	return btn


# ---------------------------------------------------------------- 提示条

func _build_toast(hud: Control) -> void:
	# 放在左侧空白列（卡牌扇形左边界在 x=348 之外），不与卡牌抢位置
	var toast := _mk(hud, UI.panel(Color(0.09, 0.07, 0.13, 0.82), 22, 2, Color(1.0, 0.85, 0.45, 0.5), 10), "Toast")
	UI.anchor_bottom_left(toast, 26, 344, 108, 300)
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


# ---------------------------------------------------------------- 中央：卡牌陈列

func _build_card_fan(hud: Control) -> int:
	var box: Dictionary = _menu().get("card_box", {})
	var card_box := Vector2(float(box.get("w", 336)), float(box.get("h", 520)))
	var fan: CardFan = CardFanScript.new()
	fan.name = "CardFan"
	fan.custom_minimum_size = BASE
	fan.size = BASE
	UI.fill(fan)
	# 扇形容器铺满整屏且叠在右侧竖栏之上：默认 STOP 会吞掉整屏点击，
	# 让竖栏按钮（召集 / 卡牌 / 玩法模式）点不动。改 IGNORE 让空白处穿透，
	# 卡面子节点各自是 STOP，卡牌点击不受影响。
	fan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mk(hud, fan, "CardFan", true)

	# —— 编辑器预览用的一份数据（运行时会被 main_menu.gd 用 RealmDB 真值覆盖）
	# 预览取 demo_team_slots（与底部出战阵容栏同一批），而非 demo_lineup，
	# 这样编辑器里看到的扇形 = 运行时「大卡跟随出战阵容」的效果。
	var rarities: Dictionary = _section("rarities").get("table", {})
	var elements: Dictionary = _section("elements").get("table", {})
	var items: Array = []
	for char_id in _menu().get("demo_team_slots", []):
		var cfg := _character(str(char_id))
		if cfg.is_empty():
			continue
		var level := int(cfg.get("demo_level", 1))
		var star := int(cfg.get("demo_star", 1))
		items.append({
			"char_id": str(char_id),
			"config": cfg,
			"card": { "char_id": str(char_id), "level": level, "star": star,
				"exp": 0, "equipment": [] },
			"stats": _preview_stats(cfg, level, star),
		})
	fan.configure(items, { "rarities": rarities, "elements": elements },
		card_box, _menu().get("fan", {}))
	return items.size()


## 仅用于场景内预览的属性换算：走 GrowthCore，与运行时 RealmDB.stats_of 同一份公式
func _preview_stats(cfg: Dictionary, level: int, star: int) -> Dictionary:
	var bonus: Array = _section("growth").get("star_up", {}).get("per_star_attr_bonus", [])
	return GROWTH.stats_of(cfg, level, star, bonus)


# ---------------------------------------------------------------- 队伍预览条

func _build_team_bar(hud: Control) -> void:
	var bar := _mk(hud, UI.panel(Color(0.09, 0.07, 0.13, 0.68), 24, 2, Color(1.0, 0.85, 0.45, 0.5), 12), "TeamBar")
	# 槽位 68×68；个数与运行时同源（formation.team.max_members），不足补空槽。
	var n := maxi(1, int(_section("formation").get("team", {}).get("max_members", 5)))
	var slot_sz := 68.0
	var slot_gap := 12.0
	var slots_w := slot_sz * float(n) + slot_gap * float(n - 1)
	var info_x := 156.0 + slots_w + 12.0
	var bar_w := info_x + 164.0 + 20.0
	UI.anchor_bottom_center(bar, bar_w, 104, 152)

	var grid := UI.label("3 × 3", 30, Color("#FFD98A"), 7)
	grid.name = "GridLabel"
	grid.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UI.place(grid, 22, 0, 110, 104)
	bar.add_child(grid)

	var divider := ColorRect.new()
	divider.color = Color(1.0, 0.85, 0.45, 0.28)
	UI.place(divider, 140, 26, 2, 52)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(divider)

	# N 个 68 槽 + (N-1) 段 12 间距；容器给足宽，空槽也占位，预览永远铺满 N 格
	var slots := HBoxContainer.new()
	slots.name = "TeamSlots"
	slots.add_theme_constant_override("separation", int(slot_gap))
	UI.place(slots, 156, 18, slots_w, slot_sz)
	bar.add_child(slots)

	var hint := UI.label("出战阵容", 18, Color(0.88, 0.92, 0.98, 0.7), 5)
	hint.name = "TeamHint"
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UI.place(hint, info_x, 22, 164, 30)
	bar.add_child(hint)

	# 队伍总战力：运行时由 main_menu.gd 按当前上阵（含羁绊）刷新
	var power := UI.label("战力 —", 24, Color("#FFD45E"), 6)
	power.name = "TeamPowerLabel"
	power.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	power.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UI.place(power, info_x, 52, 164, 34)
	bar.add_child(power)


# ---------------------------------------------------------------- 底部：开始冒险

func _build_start_button(hud: Control) -> void:
	var btn := Button.new()
	btn.name = "StartButton"
	btn.text = "进入冒险"
	btn.add_theme_font_override("font", load(UI.FONT_MAIN))
	btn.add_theme_font_size_override("font_size", 48)
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
	UI.anchor_bottom_center(btn, 460, 104, 34)
	_mk(hud, btn, "StartButton", true)

	var sub := UI.label("START GAME", 20, Color(0.36, 0.20, 0.05, 0.85), 0)
	sub.name = "StartSub"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.place(sub, 0, 68, 460, 26)
	btn.add_child(sub)


# ---------------------------------------------------------------- 左下：状态

func _build_footer(hud: Control) -> void:
	var info := UI.label("", 18, Color(1, 1, 1, 0.78), 5)
	info.name = "FooterInfo"
	info.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	UI.anchor_bottom_left(info, 26, 700, 62, 22)
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


func _meta() -> Dictionary:
	return _section("meta")


func _menu() -> Dictionary:
	return _section("menu")


func _player() -> Dictionary:
	return _menu().get("player", {})


func _player_avatar() -> String:
	return str(_player().get("avatar", "res://assets/art/characters/char_knight.png"))


func _section(key: String) -> Dictionary:
	var v: Variant = _data.get(key, {})
	return v if typeof(v) == TYPE_DICTIONARY else {}


func _character(id: String) -> Dictionary:
	for c in _data.get("characters", []):
		if str(c.get("id", "")) == id:
			return c
	return {}
