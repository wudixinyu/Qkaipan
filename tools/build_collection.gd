extends SceneTree
## build_collection.gd —— 程序化构建卡片图鉴（全部卡片：已获取 / 未获取）场景
##
## 用法（headless）：
##   Godot --headless --path <项目> --script res://tools/build_collection.gd
##
## 产出：res://scenes/collection.tscn
##
## 版面：
##   顶栏是标题 + 收集进度 + 三档筛选（全部 / 已获取 / 未获取）；
##   中部是 4×2 卡牌网格区（运行期由 collection.gd 按 GameDB 全卡目录重建，
##   未获取的卡走 CardView 剪影态并叠锁章）；
##   详情弹层左卡面右信息（定位 / 三围 / 技能文案），默认隐藏。
##
## 与其它 build_*.gd 同一套约定：
##   1. 不依赖 autoload —— 配置直接读 res://data/game_data.json；
##   2. 静态布局全部用「锚点 + 偏移」写死，换分辨率不错位；
##   3. 网格与详情卡面各留一份编辑器预览，运行时整批重建。

const UI := preload("res://tools/ui_kit.gd")
const CardViewScript := preload("res://scripts/card_view.gd")

## collection.gd 引用了 autoload，全局名在 --script 模式下要等主循环才注册，
## 所以这里必须用延迟 load()，不能 preload。
const COLLECTION_SCRIPT_PATH := "res://scripts/collection.gd"

const DATA_PATH := "res://data/game_data.json"
const OUT_PATH := "res://scenes/collection.tscn"
const BG_PATH := "res://assets/art/bg/bg_islands.png"
const BASE := Vector2(1920, 1080)

const PANEL_BG := Color(0.09, 0.07, 0.13, 0.78)
const PANEL_BORDER := Color(1.0, 0.85, 0.45, 0.45)

## —— 版面常量：与 collection.gd 同一口径 ——
const CARD_BOX := Vector2(286, 412)
const GRID_COLUMNS := 4
const COL_GAP := 50.0
const ROW_GAP := 40.0
const GRID_CENTER_Y := 568.0

const TOP_PANEL := Rect2(260, 18, 1400, 96)
## 顶栏内「左进度 / 中标题 / 右筛选」三段式：全部收进 1400 宽内，按钮不再溢出屏幕右缘
## 标题在顶栏水平居中（顶栏中心 = 屏幕中心 960）
const TITLE_BOX := Rect2(520, 14, 360, 50)
const COLLECT_BOX := Rect2(28, 32, 300, 32)
## 3 按钮右对齐：起点 898 + 2×(150+12) + 150 = 1372（相对），留 28 右边距
const FILTER_X0 := 898.0
const FILTER_W := 150.0
const FILTER_H := 58.0
const FILTER_GAP := 12.0
const FILTER_Y := 19.0

const GRID_PANEL := Rect2(260, 134, 1400, 868)
const BACK_BUTTON := Rect2(20, 1010, 220, 58)
const FOOTER_STAT_BOX := Rect2(1258, 1032, 280, 30)
const FOOTER_BOX := Rect2(1258, 1054, 640, 24)
const TOAST := Rect2(660, 946, 600, 56)

const DETAIL_PANEL := Rect2(260, 100, 1400, 880)
const DETAIL_CARD_HOLDER := Rect2(40, 40, 336, 520)
const DETAIL_LOCK := Rect2(118, 460, 180, 40)
const D_TITLE := Rect2(440, 34, 760, 56)
const D_TAGS := Rect2(442, 98, 760, 36)
const D_STATE := Rect2(1210, 40, 150, 32)
const D_POWER := Rect2(1210, 76, 150, 32)
const D_STATS_HEAD := Rect2(442, 150, 300, 34)
const D_STATS := Rect2(442, 190, 560, 132)
const D_SKILLS_HEAD := Rect2(442, 338, 300, 34)
const D_SKILLS := Rect2(442, 378, 918, 336)
const D_ACQUIRE := Rect2(442, 726, 918, 32)
const D_NAV_W := 150.0
const D_NAV_H := 62.0
const D_NAV_Y := 792.0
const D_PREV := Rect2(442, D_NAV_Y, D_NAV_W, D_NAV_H)
const D_NEXT := Rect2(792, D_NAV_Y, D_NAV_W, D_NAV_H)
const D_CLOSE := Rect2(1142, D_NAV_Y, 218, D_NAV_H)

const FILTERS := [
	{ "id": "all", "name": "全部" },
	{ "id": "owned", "name": "已获取" },
	{ "id": "unowned", "name": "未获取" },
]

const UNIQUE_NAMES := [
	"TopPanel", "CollectLabel", "Filt_all", "Filt_owned", "Filt_unowned",
	"GridPanel", "GridHolder", "CardSlot0", "DetailLayer", "DetailBackdrop",
	"DetailPanel", "DetailCardHolder", "DetailLockPanel", "DetailTitle",
	"DetailTags", "DetailState", "DetailPower", "DetailStats", "DetailSkills",
	"DetailAcquire", "DetailPrevButton", "DetailNextButton", "DetailCloseButton",
	"BackButton", "FooterInfo", "FooterStat", "Toast", "ToastLabel",
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
	_root.name = "Collection"
	var script: Script = load(COLLECTION_SCRIPT_PATH)
	if script == null:
		push_error("[build] 无法加载 %s" % COLLECTION_SCRIPT_PATH)
	_root.set_script(script)
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

	_build_top_panel(hud)
	_build_grid_area(hud)
	_build_back_button(hud)
	_build_footer(hud)
	_build_toast(hud)
	_build_detail_layer(hud)

	# CardView 内部 new 出的子节点带不上 owner，必须统一补一遍才会写进场景
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
	UI.fill(bg)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mk(_root, bg, "Background")

	# 图鉴要压住背景亮度，让卡框品质色成为主角
	var tint := ColorRect.new()
	tint.color = Color(0.06, 0.04, 0.12, 0.52)
	UI.fill(tint)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mk(_root, tint, "DarkTint")


# ---------------------------------------------------------------- 顶栏

func _build_top_panel(hud: Control) -> void:
	var top := _mk(hud, Control.new(), "TopPanel")
	UI.place(top, TOP_PANEL.position.x, TOP_PANEL.position.y, TOP_PANEL.size.x, TOP_PANEL.size.y)

	var bg := UI.panel(PANEL_BG, 20, 2, PANEL_BORDER, 10)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	top.add_child(bg)

	var title := UI.label_shadow("卡片图鉴", 46, UI.GOLD_LIGHT, 8,
		Color(0.22, 0.12, 0.02, 0.9), Vector2(0, 4), Color(0.35, 0.2, 0.04, 0.85),
		Vector2(TITLE_BOX.size.x, TITLE_BOX.size.y))
	UI.place(title, TITLE_BOX.position.x, TITLE_BOX.position.y, TITLE_BOX.size.x, TITLE_BOX.size.y)
	top.add_child(title)

	var sub := UI.label("COLLECTION CODEX", 17, Color(0.9, 0.88, 0.96, 0.55), 4)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.place(sub, TITLE_BOX.position.x, 66, TITLE_BOX.size.x, 22)
	top.add_child(sub)

	var collect := UI.label("已收集 0 / 0", 26, UI.GOLD_LIGHT, 5)
	collect.name = "CollectLabel"
	UI.place(collect, COLLECT_BOX.position.x, COLLECT_BOX.position.y, COLLECT_BOX.size.x, COLLECT_BOX.size.y)
	top.add_child(collect)

	for i in FILTERS.size():
		var f: Dictionary = FILTERS[i]
		var btn := UI.text_button(str(f.get("name", "")), 26,
			Color(0.10, 0.08, 0.15, 0.9), PANEL_BORDER, UI.CREAM, 14)
		btn.name = "Filt_%s" % str(f.get("id", ""))
		var x := FILTER_X0 + float(i) * (FILTER_W + FILTER_GAP)
		UI.place(btn, x, FILTER_Y, FILTER_W, FILTER_H)
		btn.tooltip_text = "筛选：%s" % str(f.get("name", ""))
		top.add_child(btn)


# ---------------------------------------------------------------- 卡牌网格

func _build_grid_area(hud: Control) -> void:
	var panel := UI.panel(Color(0.07, 0.05, 0.11, 0.55), 24, 2,
		Color(1.0, 0.85, 0.45, 0.22), 12)
	panel.name = "GridPanel"
	UI.place(panel, GRID_PANEL.position.x, GRID_PANEL.position.y,
		GRID_PANEL.size.x, GRID_PANEL.size.y)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mk(hud, panel, "GridPanel")

	var grid := Control.new()
	grid.name = "GridHolder"
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mk(hud, grid, "GridHolder")
	# 铺满 Hud：先锚点再归零 offset，只改 anchor 不会带着 size 一起变
	grid.set_anchors_preset(Control.PRESET_FULL_RECT)
	UI.fill(grid)
	# 只留一个占位格（带预览卡面），运行期按筛选结果整批重建
	var slot := Control.new()
	slot.name = "CardSlot0"
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_child(slot)
	slot.position = _slot_pos(0, _preview_count())
	slot.add_child(_preview_card())


func _slot_pos(i: int, total: int) -> Vector2:
	var columns := mini(GRID_COLUMNS, total)
	var row := i / columns
	var col := i % columns
	var rows := int(ceil(float(total) / float(columns)))
	var in_row := mini(columns, total - row * columns)
	var width := float(in_row) * (CARD_BOX.x + COL_GAP) - COL_GAP
	var height := float(rows) * (CARD_BOX.y + ROW_GAP) - ROW_GAP
	return Vector2(
		(BASE.x - width) * 0.5 + float(col) * (CARD_BOX.x + COL_GAP),
		GRID_CENTER_Y - height * 0.5 + float(row) * (CARD_BOX.y + ROW_GAP))


func _characters() -> Array:
	var v: Variant = _data.get("characters", [])
	return v if v is Array else []


func _preview_count() -> int:
	return mini(_characters().size(), GRID_COLUMNS * 2)


## 编辑器预览卡：第一张配置卡，运行时会换成真实数据（含未获取剪影态）
func _preview_card() -> Control:
	var list := _characters()
	if list.is_empty():
		var ph := UI.panel(Color(0.1, 0.09, 0.14, 0.6), 18, 2, PANEL_BORDER)
		ph.size = CARD_BOX
		return ph
	var cfg: Dictionary = list[0]
	var rarity: Dictionary = _rarity_table().get(str(cfg.get("rarity", "R")), {})
	var element: Dictionary = _element_table().get(str(cfg.get("element", "")), {})
	var view: CardView = CardViewScript.new()
	view.name = "Card_%s" % str(cfg.get("id", "preview"))
	view.setup({
		"char_id": str(cfg.get("id", "")), "config": cfg,
		"card": { "char_id": str(cfg.get("id", "")),
			"level": int(cfg.get("demo_level", 1)), "star": int(cfg.get("demo_star", 1)) },
		"stats": cfg.get("base", {}),
	}, rarity, element, CARD_BOX)
	return view


# ---------------------------------------------------------------- 返回 / 底栏 / Toast

func _build_back_button(hud: Control) -> void:
	var btn := UI.text_button("返回", 28, Color(0.10, 0.08, 0.15, 0.88),
		PANEL_BORDER, UI.CREAM, 16)
	btn.name = "BackButton"
	UI.place(btn, BACK_BUTTON.position.x, BACK_BUTTON.position.y,
		BACK_BUTTON.size.x, BACK_BUTTON.size.y)
	btn.tooltip_text = "返回主界面"
	_mk(hud, btn, "BackButton")


func _build_footer(hud: Control) -> void:
	var stat := UI.label("", 19, Color(0.95, 0.9, 0.75, 0.8), 4)
	stat.name = "FooterStat"
	stat.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UI.place(stat, FOOTER_STAT_BOX.position.x, FOOTER_STAT_BOX.position.y,
		FOOTER_STAT_BOX.size.x, FOOTER_STAT_BOX.size.y)
	_mk(hud, stat, "FooterStat")

	var info := UI.label("", 17, Color(0.9, 0.88, 0.96, 0.6), 4)
	info.name = "FooterInfo"
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UI.place(info, FOOTER_BOX.position.x, FOOTER_BOX.position.y,
		FOOTER_BOX.size.x, FOOTER_BOX.size.y)
	_mk(hud, info, "FooterInfo")


func _build_toast(hud: Control) -> void:
	var toast := UI.panel(Color(0.06, 0.05, 0.09, 0.92), 16, 2, UI.GOLD, 10)
	toast.name = "Toast"
	UI.place(toast, TOAST.position.x, TOAST.position.y, TOAST.size.x, TOAST.size.y)
	toast.visible = false

	var lb := UI.label("", 24, UI.CREAM, 5)
	lb.name = "ToastLabel"
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lb.set_anchors_preset(Control.PRESET_FULL_RECT)
	toast.add_child(lb)
	_mk(hud, toast, "Toast")


# ---------------------------------------------------------------- 详情弹层

func _build_detail_layer(hud: Control) -> void:
	var layer := _mk(hud, Control.new(), "DetailLayer")
	UI.fill(layer)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.visible = false

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.03, 0.02, 0.06, 0.62)
	UI.fill(backdrop)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_mk(layer, backdrop, "DetailBackdrop")

	var panel := UI.panel(Color(0.08, 0.06, 0.12, 0.96), 26, 3, PANEL_BORDER, 18)
	panel.name = "DetailPanel"
	UI.place(panel, DETAIL_PANEL.position.x, DETAIL_PANEL.position.y,
		DETAIL_PANEL.size.x, DETAIL_PANEL.size.y)
	layer.add_child(panel)

	var holder := Control.new()
	holder.name = "DetailCardHolder"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(holder)
	UI.place(holder, DETAIL_CARD_HOLDER.position.x, DETAIL_CARD_HOLDER.position.y,
		DETAIL_CARD_HOLDER.size.x, DETAIL_CARD_HOLDER.size.y)
	# 编辑器预览：放一张完整卡面，运行期换成被查看的卡
	holder.add_child(_preview_detail_card())

	# 未获取时盖在卡面下方的提示牌
	var lock := UI.panel(Color(0.05, 0.04, 0.09, 0.88), 14, 2,
		Color(1.0, 0.6, 0.6, 0.5), 6)
	lock.name = "DetailLockPanel"
	UI.place(lock, DETAIL_LOCK.position.x, DETAIL_LOCK.position.y,
		DETAIL_LOCK.size.x, DETAIL_LOCK.size.y)
	lock.visible = false
	panel.add_child(lock)
	var lock_txt := UI.label("未获得 · 展演态预览", 20, Color(0.95, 0.85, 0.85, 0.9), 4)
	lock_txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lock_txt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lock_txt.set_anchors_preset(Control.PRESET_FULL_RECT)
	lock.add_child(lock_txt)

	_add_label(panel, "DetailTitle", "", 42, UI.GOLD_LIGHT, 6, D_TITLE,
		HORIZONTAL_ALIGNMENT_LEFT)
	_add_label(panel, "DetailTags", "", 24, Color(0.9, 0.88, 0.96, 0.85), 4, D_TAGS,
		HORIZONTAL_ALIGNMENT_LEFT)
	_add_label(panel, "DetailState", "", 22, Color("#FFE9A8"), 4, D_STATE,
		HORIZONTAL_ALIGNMENT_RIGHT)
	_add_label(panel, "DetailPower", "", 22, Color("#7BE0FF"), 4, D_POWER,
		HORIZONTAL_ALIGNMENT_RIGHT)

	_add_label(panel, "StatsHead", "属性", 26, UI.GOLD, 5,
		Rect2(D_STATS_HEAD.position.x, D_STATS_HEAD.position.y,
			D_STATS_HEAD.size.x, D_STATS_HEAD.size.y), HORIZONTAL_ALIGNMENT_LEFT)
	_add_label(panel, "DetailStats", "", 24, UI.CREAM, 0, D_STATS, HORIZONTAL_ALIGNMENT_LEFT)
	_add_label(panel, "SkillsHead", "技能", 26, UI.GOLD, 5,
		Rect2(D_SKILLS_HEAD.position.x, D_SKILLS_HEAD.position.y,
			D_SKILLS_HEAD.size.x, D_SKILLS_HEAD.size.y), HORIZONTAL_ALIGNMENT_LEFT)

	var skills := _add_label(panel, "DetailSkills", "", 22, Color(0.94, 0.92, 0.98, 0.92),
		0, D_SKILLS, HORIZONTAL_ALIGNMENT_LEFT)
	skills.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Godot 4 的 Label 没有 line_spacing 属性，行距由字号与空行控制

	var acquire := _add_label(panel, "DetailAcquire", "", 21,
		Color(0.9, 0.88, 0.96, 0.75), 0, D_ACQUIRE, HORIZONTAL_ALIGNMENT_LEFT)
	acquire.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_add_sep(panel, 150.0)
	_add_sep(panel, 320.0)
	_add_sep(panel, 706.0)

	_add_nav_button(panel, "DetailPrevButton", "◀ 上一张", D_PREV)
	_add_nav_button(panel, "DetailNextButton", "下一张 ▶", D_NEXT)
	var close := _add_nav_button(panel, "DetailCloseButton", "关 闭", D_CLOSE)
	close.add_theme_stylebox_override("normal",
		UI.style(Color(0.24, 0.14, 0.06, 0.92), 14, 3, UI.GOLD_DEEP, 10))
	close.add_theme_stylebox_override("hover",
		UI.style(Color(0.32, 0.19, 0.08, 0.95), 14, 3, UI.GOLD, 12))


func _preview_detail_card() -> Control:
	var list := _characters()
	if list.is_empty():
		return UI.spacer(1, 1)
	var cfg: Dictionary = list[0]
	var rarity: Dictionary = _rarity_table().get(str(cfg.get("rarity", "R")), {})
	var element: Dictionary = _element_table().get(str(cfg.get("element", "")), {})
	var view: CardView = CardViewScript.new()
	view.name = "DetailCardPreview"
	view.setup({
		"char_id": str(cfg.get("id", "")), "config": cfg,
		"card": { "char_id": str(cfg.get("id", "")),
			"level": int(cfg.get("demo_level", 1)), "star": int(cfg.get("demo_star", 1)) },
		"stats": cfg.get("base", {}),
	}, rarity, element, CARD_BOX)
	return view


func _add_label(parent: Control, node_name: String, text: String, size: int,
		color: Color, outline: int, box: Rect2, align: int) -> Label:
	var lb := UI.label(text, size, color, outline)
	lb.name = node_name
	lb.horizontal_alignment = align
	UI.place(lb, box.position.x, box.position.y, box.size.x, box.size.y)
	parent.add_child(lb)
	return lb


func _add_sep(parent: Control, y: float) -> void:
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.12)
	UI.place(line, 442, y, 918, 2)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)


func _add_nav_button(parent: Control, node_name: String, text: String, box: Rect2) -> Button:
	var btn := UI.text_button(text, 24, Color(0.12, 0.10, 0.18, 0.92),
		PANEL_BORDER, UI.CREAM, 14)
	btn.name = node_name
	UI.place(btn, box.position.x, box.position.y, box.size.x, box.size.y)
	parent.add_child(btn)
	return btn


# ---------------------------------------------------------------- 工具

func _mk(parent: Node, node: Node, node_name: String) -> Node:
	node.name = node_name
	parent.add_child(node)
	node.owner = _root
	return node


func _count(node: Node) -> int:
	var n := 1
	for c in node.get_children():
		n += _count(c)
	return n


# ---------------------------------------------------------------- 配置读取

func _section(key: String) -> Dictionary:
	var v: Variant = _data.get(key, {})
	return v if typeof(v) == TYPE_DICTIONARY else {}


func _rarity_table() -> Dictionary:
	var v: Variant = _section("rarities").get("table", {})
	return v if v is Dictionary else {}


func _element_table() -> Dictionary:
	var v: Variant = _section("elements").get("table", {})
	return v if v is Dictionary else {}
