extends Control
## Formation —— 卡牌选择与编队（Hero Selection & Formation）
##
## 场景骨架由 tools/build_formation.gd 程序化生成；本脚本只做三件事：
## 把配置与存档接到界面、把交互接起来、做入场动效。
##
## 数据流向：GameDB（配置）+ SaveDB（编队 / 预设）→ RealmDB（属性 / 羁绊 / 克制）→ 界面
##
## 分工约定：
##   * 静态版面像素全部在 build_formation.gd 里（本脚本只按节点尺寸摆动态元素）；
##   * 规则（上阵上限 / 同名限制 / 羁绊条件 / 克制表）一律读配置，不在代码里写死；
##   * 写档只走 SaveDB，本脚本不碰 FileAccess；编队改动即时落盘（见 _persist）。

const UI := preload("res://tools/ui_kit.gd")
const FALLBACK_BATTLE_SCENE := "res://scenes/battle.tscn"

## 冒烟测试要把「确认选择 → 扣体力 → 写档 → 交接给战斗」验完，但不希望真的切场景，
## 于是把切场景这一步做成开关：测试里置 false，跑完断言再退出。
var auto_transition := true
## 由配置覆盖（formation.battle_scene）
var battle_scene := FALLBACK_BATTLE_SCENE

# —— 与 build_formation.gd 的常量必须同值：棋盘格与卡库缩略图都是运行时 new 出来的
const BOARD_CELL := Vector2(76, 76)
const BOARD_GAP := 10.0
const BOARD_GUTTER := 52.0
const BOARD_CELLS := 9
const THUMB := Vector2(220, 80)
const CHIP := Vector2(86, 40)
## 单个战术格子的宽度（= build_formation.gd 的 (TAC_W - PAD*2 - GAP) / 2），
## 用来估算「两行能装多少字」，改版面时要跟着改。
const TAC_BOX_W := 249.0

@onready var _card_stage: CardFan = %CardStage
@onready var _board_grid: Control = %BoardGrid
@onready var _board_count: Label = %BoardCount
@onready var _library_grid: GridContainer = %LibraryGrid
@onready var _library_count: Label = %LibraryCount
@onready var _tactical: Control = %TacticalPanel
@onready var _power_value: Label = %PowerValue
@onready var _power_parts: Label = %PowerParts
@onready var _preset_bar: HBoxContainer = %PresetBar
@onready var _preset_hint: Label = %PresetHint
@onready var _quick_fill: Button = %QuickFillButton
@onready var _clear_btn: Button = %ClearButton
@onready var _deploy_btn: Button = %DeployButton
@onready var _remove_btn: Button = %RemoveButton
@onready var _confirm: Button = %ConfirmButton
@onready var _save_btn: Button = %SaveButton
@onready var _back: Button = %BackButton
@onready var _search: LineEdit = %SearchEdit
@onready var _toast: Panel = %Toast
@onready var _toast_label: Label = %ToastLabel
@onready var _filter_panel: Control = %FilterPanel
@onready var _filter_groups: Control = %FilterGroups
@onready var _sort_panel: Control = %SortPanel
@onready var _sort_options: Control = %SortOptions

var _all_items: Array = []          ## 已持有英雄（存档里有的卡；未持有的不进编队卡池，与图鉴口径一致）
var _view: Array = []               ## 筛选 + 排序后的列表
var _team: Array = []               ## 工作编队 [{ slot, char_id }]
var _report: Dictionary = {}        ## RealmDB.formation_report(_team)
var _selected_id := ""
var _preset_id := ""
var _query := ""
var _sort_id := "default"
var _filters := {"rarity": [], "element": [], "role": []}
var _tab_buttons: Dictionary = {}
var _chips: Array = []
var _sort_buttons: Array = []
var _toast_tween: Tween
var _intro_done := false
## _ready 期间的选择（配置的 default_selected）不触发陈列滚动回中，
## 保留策划调好的初始版面；之后的用户点选才把看中的卡滚到中线。
var _boot_ready := false


func _ready() -> void:
	battle_scene = str(GameDB.formation().get("battle_scene", FALLBACK_BATTLE_SCENE))
	# 卡池只收已持有的卡：新号 = 默认三卡，与主界面默认陈列/图鉴已获取完全对齐；
	# 未持有的英雄在图鉴里看剪影，抽到后才进编队。
	_all_items = RealmDB.all_heroes().filter(
		func(item: Dictionary) -> bool: return not SaveDB.find_card(str(item.get("char_id", ""))).is_empty())
	_preset_id = SaveDB.active_preset()
	_team = SaveDB.resolved_team()

	_build_tabs()
	_build_preset_bar()
	_build_filter_groups()
	_build_sort_options()
	_bind_inputs()

	_refresh_view()
	if not _view.is_empty():
		_selected_id = str(_view[0].get("char_id", ""))
	_refresh_team()
	# 配置指定了「进场默认看谁」就切过去：概念稿里高亮的是 SSR，不是列表第一张
	var preset_pick := str(GameDB.formation().get("default_selected", ""))
	if preset_pick != "" and not _item_of(preset_pick).is_empty():
		_select(preset_pick)
	_boot_ready = true
	_play_intro()


# ---------------------------------------------------------------- 配置快捷取

func _fsec(key: String) -> Dictionary:
	var v: Variant = GameDB.formation().get(key, {})
	return v if typeof(v) == TYPE_DICTIONARY else {}


func _t(key: String, fallback: String = "") -> String:
	return str(_fsec("toast").get(key, fallback))


func _fan_cfg() -> Dictionary:
	var v: Variant = GameDB.formation().get("fan", {})
	if typeof(v) == TYPE_DICTIONARY and not (v as Dictionary).is_empty():
		return v
	return GameDB.menu().get("fan", {})


func _card_box() -> Vector2:
	var box: Dictionary = GameDB.menu().get("card_box", {})
	return Vector2(float(box.get("w", 336)), float(box.get("h", 520)))


func _name_of(char_id: String) -> String:
	return str(GameDB.character(char_id).get("name", char_id))


func _cfg_of(char_id: String) -> Dictionary:
	return GameDB.character(char_id)


func _item_of(char_id: String) -> Dictionary:
	for item in _all_items:
		if str(item.get("char_id", "")) == char_id:
			return item
	return {}


# ---------------------------------------------------------------- 顶部：标签页

func _build_tabs() -> void:
	for raw in GameDB.formation_list("top_tabs"):
		var t: Dictionary = raw
		var tid := str(t.get("id", "tab"))
		var btn := get_node_or_null("Hud/TopBar/Tab_%s" % tid) as Button
		if btn == null:
			continue
		btn.pressed.connect(_on_tab_pressed.bind(tid))
		_tab_buttons[tid] = btn
	_paint_tabs()


func _paint_tabs() -> void:
	for key in _tab_buttons.keys():
		var btn: Button = _tab_buttons[key]
		var on := false
		if key == "filter":
			on = _filter_panel.visible
		elif key == "sort":
			on = _sort_panel.visible
		else:
			on = not _filter_panel.visible and not _sort_panel.visible
		btn.add_theme_stylebox_override("normal", UI.style(
			Color(0.24, 0.17, 0.06, 0.94) if on else Color(0.13, 0.10, 0.18, 0.86), 20,
			3 if on else 2, UI.GOLD if on else _panel_border(), 0))
		btn.add_theme_color_override("font_color",
			Color("#FFE9A8") if on else UI.CREAM)


func _panel_border() -> Color:
	return Color(1.0, 0.85, 0.45, 0.28)


func _on_tab_pressed(id: String) -> void:
	if id == "filter":
		_filter_panel.visible = not _filter_panel.visible
		_sort_panel.visible = false
	elif id == "sort":
		_sort_panel.visible = not _sort_panel.visible
		_filter_panel.visible = false
	else:
		_filter_panel.visible = false
		_sort_panel.visible = false
	_paint_tabs()


# ---------------------------------------------------------------- 阵容预设

func _build_preset_bar() -> void:
	for c in _preset_bar.get_children():
		_preset_bar.remove_child(c)
		c.queue_free()
	for raw in GameDB.presets():
		var p: Dictionary = raw
		var pid := str(p.get("id", ""))
		var on := pid == _preset_id
		var btn := UI.text_button(str(p.get("name", pid)), 20,
			Color(0.22, 0.16, 0.06, 0.95) if on else Color(0.10, 0.08, 0.14, 0.82),
			UI.GOLD if on else Color(1, 1, 1, 0.26),
			Color("#FFE9A8") if on else Color(1, 1, 1, 0.78), 16)
		btn.name = "PresetBtn_%s" % pid
		btn.custom_minimum_size = Vector2(120, 50)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.tooltip_text = "%s · %d 人" % [str(p.get("name", pid)),
			SaveDB.preset_entries(pid).size()]
		btn.pressed.connect(_on_preset_pressed.bind(pid))
		_preset_bar.add_child(btn)
	_refresh_preset_hint()


func _refresh_preset_hint() -> void:
	_preset_hint.text = "当前「%s」· %d / %d 人" % [
		str(GameDB.preset_cfg(_preset_id).get("name", _preset_id)),
		_team.size(), GameDB.team_max()]


func _on_preset_pressed(pid: String) -> void:
	if pid == _preset_id:
		return
	var name_text := str(GameDB.preset_cfg(pid).get("name", pid))
	# 先把手上的工作阵容存回旧预设，再载入新预设 —— 不然切一下就白编了
	SaveDB.save_preset(_preset_id, _team)
	_team = SaveDB.normalize_team(SaveDB.switch_preset(pid))
	_preset_id = pid
	if _team.is_empty():
		_show_toast(_t("preset_empty", "「%s」还没有阵容，先编好队再切换") % name_text)
	else:
		_show_toast(_t("preset_loaded", "已切换到「%s」（%d 人）") % [name_text, _team.size()])
	_build_preset_bar()
	_refresh_team()


# ---------------------------------------------------------------- 筛选 / 排序弹层

func _build_filter_groups() -> void:
	_clear_children(_filter_groups)
	_chips.clear()
	for raw in GameDB.filter_groups():
		var g: Dictionary = raw
		var gid := str(g.get("id", ""))
		var box := VBoxContainer.new()
		box.name = "Group_%s" % gid
		box.add_theme_constant_override("separation", 6)
		_filter_groups.add_child(box)

		var head := UI.label(str(g.get("name", gid)), 20, Color("#FFD98A"), 5)
		head.custom_minimum_size = Vector2(0, 28)
		box.add_child(head)

		var flow := HFlowContainer.new()
		flow.name = "Chips"
		flow.add_theme_constant_override("h_separation", 8)
		flow.add_theme_constant_override("v_separation", 8)
		flow.custom_minimum_size = Vector2(0, 84)
		box.add_child(flow)

		for opt in _filter_options(gid):
			var chip := _make_chip(gid, str(opt.get("id", "")), str(opt.get("label", "")))
			flow.add_child(chip)
			_chips.append(chip)
	_paint_chips()


## 候选项来自「哪张表」由配置的 source 决定，这里只做映射
func _filter_options(gid: String) -> Array:
	var out: Array = []
	match gid:
		"rarity":
			for r in GameDB.rarities():
				out.append({"id": str(r.get("id", "")), "label": str(r.get("id", ""))})
		"element":
			for e in GameDB.elements():
				out.append({"id": str(e.get("id", "")), "label": str(e.get("name", ""))})
		"role":
			var table := GameDB.section("roles")
			for key in table.keys():
				out.append({"id": str(key), "label": str(table[key].get("name", key))})
	return out


func _make_chip(gid: String, value: String, label_text: String) -> Button:
	var btn := UI.text_button(label_text, 19, Color(0.11, 0.09, 0.15, 0.9),
		Color(1, 1, 1, 0.22), Color(1, 1, 1, 0.82), 14)
	btn.name = "Chip_%s_%s" % [gid, value]
	btn.custom_minimum_size = CHIP
	btn.set_meta("group", gid)
	btn.set_meta("value", value)
	btn.pressed.connect(_on_chip_pressed.bind(gid, value))
	return btn


func _paint_chips() -> void:
	for chip in _chips:
		var gid := str(chip.get_meta("group", ""))
		var value := str(chip.get_meta("value", ""))
		var sel: Array = _filters.get(gid, [])
		var on := value in sel
		chip.add_theme_stylebox_override("normal", UI.style(
			Color(0.30, 0.21, 0.06, 0.95) if on else Color(0.11, 0.09, 0.15, 0.9), 14,
			3 if on else 2, UI.GOLD if on else Color(1, 1, 1, 0.22), 0))
		chip.add_theme_color_override("font_color",
			Color("#FFE9A8") if on else Color(1, 1, 1, 0.82))


func _on_chip_pressed(gid: String, value: String) -> void:
	var sel: Array = _filters.get(gid, [])
	var out: Array = []
	for v in sel:
		if str(v) != value:
			out.append(str(v))
	if not (value in sel):
		out.append(value)
	_filters[gid] = out
	_paint_chips()
	_refresh_view()


func _build_sort_options() -> void:
	_clear_children(_sort_options)
	_sort_buttons.clear()
	for raw in GameDB.sort_options():
		var s: Dictionary = raw
		var sid := str(s.get("id", ""))
		var btn := UI.text_button(str(s.get("name", sid)), 21,
			Color(0.11, 0.09, 0.15, 0.9), Color(1, 1, 1, 0.22), UI.CREAM, 16)
		btn.name = "Sort_%s" % sid
		btn.custom_minimum_size = Vector2(0, 46)
		btn.pressed.connect(_on_sort_pressed.bind(sid))
		_sort_options.add_child(btn)
		_sort_buttons.append(btn)
	_paint_sorts()


func _paint_sorts() -> void:
	for i in _sort_buttons.size():
		var btn: Button = _sort_buttons[i]
		var s: Dictionary = GameDB.sort_options()[i]
		var on := str(s.get("id", "")) == _sort_id
		btn.add_theme_stylebox_override("normal", UI.style(
			Color(0.30, 0.21, 0.06, 0.95) if on else Color(0.11, 0.09, 0.15, 0.9), 16,
			3 if on else 2, UI.GOLD if on else Color(1, 1, 1, 0.22), 0))
		btn.add_theme_color_override("font_color",
			Color("#FFE9A8") if on else UI.CREAM)


func _on_sort_pressed(sid: String) -> void:
	_sort_id = sid
	_paint_sorts()
	_refresh_view()


func _on_search_changed(text: String) -> void:
	_query = text.strip_edges().to_lower()
	_refresh_view()


# ---------------------------------------------------------------- 交互接线

func _bind_inputs() -> void:
	_card_stage.card_pressed.connect(_select)
	_search.text_changed.connect(_on_search_changed)
	_search.text_submitted.connect(func(_t2): _search.release_focus())
	_quick_fill.pressed.connect(_on_quick_fill)
	_clear_btn.pressed.connect(_on_clear)
	_deploy_btn.pressed.connect(_on_deploy_pressed)
	_remove_btn.pressed.connect(_on_remove_pressed)
	_confirm.pressed.connect(_on_confirm)
	_save_btn.pressed.connect(_on_save)
	_back.pressed.connect(_on_back)

	var reset_btn: Button = get_node_or_null("Hud/PopupLayer/FilterPanel/FilterResetButton")
	if reset_btn != null:
		reset_btn.pressed.connect(_on_filter_reset)
	var apply_btn: Button = get_node_or_null("Hud/PopupLayer/FilterPanel/FilterApplyButton")
	if apply_btn != null:
		apply_btn.pressed.connect(_on_filter_apply)

	var qf: Dictionary = _fsec("quick_fill")
	_quick_fill.tooltip_text = str(qf.get("note", ""))
	_deploy_btn.tooltip_text = str(_fsec("quick_deploy").get("note", ""))
	_search.tooltip_text = str(_fsec("search").get("hint", ""))
	_save_btn.tooltip_text = str(_fsec("save_button").get("note", ""))
	if reset_btn != null:
		reset_btn.tooltip_text = "清空全部筛选条件"
	if apply_btn != null:
		apply_btn.tooltip_text = "收起筛选面板（筛选实时生效）"
	_refresh_buttons()


func _on_filter_reset() -> void:
	_filters = {"rarity": [], "element": [], "role": []}
	_paint_chips()
	_refresh_view()


func _on_filter_apply() -> void:
	_filter_panel.visible = false
	_paint_tabs()


# ---------------------------------------------------------------- 列表：筛选 / 排序

func _refresh_view() -> void:
	_view = []
	for item in _all_items:
		if _matches(item):
			_view.append(item)
	_sort_items(_view)
	if _view.is_empty():
		_selected_id = ""
	elif _item_of(_selected_id).is_empty() or not _in_view(_selected_id):
		_selected_id = str(_view[0].get("char_id", ""))
	_rebuild_fan()
	# 筛选 / 排序 / 搜索后列表换了，把选中的卡瞬时对位到可视范围（不动画）
	if _boot_ready:
		_card_stage.focus_card(_selected_id, false)
	_rebuild_library()
	_refresh_tactical()
	_refresh_buttons()


func _in_view(char_id: String) -> bool:
	for item in _view:
		if str(item.get("char_id", "")) == char_id:
			return true
	return false


func _matches(item: Dictionary) -> bool:
	var cfg: Dictionary = item.get("config", {})
	if not _passes(_filters.get("rarity", []), str(cfg.get("rarity", ""))):
		return false
	if not _passes(_filters.get("element", []), str(cfg.get("element", ""))):
		return false
	if not _passes(_filters.get("role", []), str(cfg.get("role", ""))):
		return false
	if _query == "":
		return true
	return _search_blob(item).contains(_query)


func _passes(sel: Variant, value: String) -> bool:
	if not (sel is Array) or (sel as Array).is_empty():
		return true
	return value in sel


## 模糊匹配的范围：名称 / 称号 / 品质（id + 中文名）/ 元素 / 职业
func _search_blob(item: Dictionary) -> String:
	var cfg: Dictionary = item.get("config", {})
	var rarity_id := str(cfg.get("rarity", ""))
	var parts: Array = [
		str(cfg.get("name", "")), str(cfg.get("title", "")),
		rarity_id, str(GameDB.rarity(rarity_id).get("name", "")),
		GameDB.element_name(str(cfg.get("element", ""))),
		str(GameDB.role(str(cfg.get("role", ""))).get("name", "")),
	]
	return " ".join(parts).to_lower()


func _sort_items(items: Array) -> void:
	match _sort_id:
		"power":
			items.sort_custom(func(a, b):
				return int(a.get("power", 0)) > int(b.get("power", 0)))
		"level":
			items.sort_custom(func(a, b):
				return int(a.get("card", {}).get("level", 1)) > int(b.get("card", {}).get("level", 1)))
		"rarity":
			var r_order := _order_index(GameDB.rarities())
			items.sort_custom(func(a, b):
				return int(r_order.get(str(a.get("config", {}).get("rarity", "")), 0)) \
					> int(r_order.get(str(b.get("config", {}).get("rarity", "")), 0)))
		"element":
			var e_order := _order_index(GameDB.elements())
			items.sort_custom(func(a, b):
				return int(e_order.get(str(a.get("config", {}).get("element", "")), 0)) \
					< int(e_order.get(str(b.get("config", {}).get("element", "")), 0)))
		"name":
			items.sort_custom(func(a, b):
				return str(a.get("config", {}).get("name", "")) < str(b.get("config", {}).get("name", "")))
		_:
			pass


func _order_index(table: Array) -> Dictionary:
	var out := {}
	for i in table.size():
		out[str(table[i].get("id", ""))] = i
	return out


# ---------------------------------------------------------------- 卡牌陈列

func _rebuild_fan() -> void:
	_card_stage.configure(_view, {
		"rarities": GameDB.rarity_table(),
		"elements": GameDB.element_table(),
	}, _card_box(), _fan_cfg())
	_refresh_fan_selection()


func _refresh_fan_selection() -> void:
	var mult := float(_fan_cfg().get("selected_scale", 1.12))
	for cv in _card_stage.cards:
		if is_instance_valid(cv):
			cv.set_selected(str(cv.char_id) == _selected_id, mult)


# ---------------------------------------------------------------- 卡库

func _rebuild_library() -> void:
	_clear_children(_library_grid)
	var lib := _fsec("library")
	var cols := maxi(1, int(lib.get("columns", 2)))
	var rows := maxi(1, int(lib.get("rows", 3)))
	_library_count.text = str(lib.get("count_text", "%d / %d 名")) \
		% [_view.size(), _all_items.size()]

	if _view.is_empty():
		var none := UI.label(str(lib.get("empty_result", "没有符合条件的英雄")), 20,
			Color(1, 1, 1, 0.62), 5)
		none.custom_minimum_size = Vector2(
			THUMB.x * float(cols) + 12.0 * float(cols - 1), 80)
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		none.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_library_grid.add_child(none)
		return

	for item in _view:
		_library_grid.add_child(_make_thumb(item))
	# 用「空位」补齐到整屏栅格，免得只有 4 张卡时右下空一大块
	var i := _view.size()
	while i < cols * rows:
		_library_grid.add_child(_make_thumb_empty(str(lib.get("empty_text", "空位"))))
		i += 1


func _make_thumb_empty(text: String) -> Control:
	var box := UI.panel(Color(0.06, 0.05, 0.09, 0.34), 16, 2, Color(1, 1, 1, 0.10))
	box.custom_minimum_size = THUMB
	box.size = THUMB
	var l := UI.label(text, 18, Color(1, 1, 1, 0.24), 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UI.fill(l)
	box.add_child(l)
	return box


func _make_thumb(item: Dictionary) -> Button:
	var char_id := str(item.get("char_id", ""))
	var cfg: Dictionary = item.get("config", {})
	var card: Dictionary = item.get("card", {})
	var rarity := GameDB.rarity(str(cfg.get("rarity", "R")))
	var accent := Color(str(rarity.get("color", "#FFFFFF")))
	var slot := RealmDB.slot_of(_team, char_id)
	var deployed := slot > 0
	var picked := char_id == _selected_id

	var base := Color(0.17, 0.12, 0.07, 0.94) if deployed else Color(0.10, 0.08, 0.14, 0.92)
	var border := UI.GOLD if picked else (accent if deployed else accent.darkened(0.4))
	var width := 4 if picked else 2

	var btn := Button.new()
	btn.name = "Hero_%s" % char_id
	btn.custom_minimum_size = THUMB
	btn.size = THUMB
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_stylebox_override("normal", UI.style(base, 16, width, border, 0))
	btn.add_theme_stylebox_override("hover",
		UI.style(base.lightened(0.12), 16, width, border.lightened(0.25), 8, Color(0, 0, 0, 0.4)))
	btn.add_theme_stylebox_override("pressed", UI.style(base.darkened(0.12), 16, width, border, 0))
	btn.add_theme_stylebox_override("focus", UI.style(Color(0, 0, 0, 0), 16))
	btn.pressed.connect(_select.bind(char_id))

	var frame := UI.panel(Color(0.05, 0.04, 0.08, 0.9), 12, 2, accent)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.place(frame, 8, 10, 62, 62)
	btn.add_child(frame)

	var pic := UI.picture(str(cfg.get("portrait", "")), TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	UI.place(pic, 8, 10, 62, 62)
	btn.add_child(pic)

	var nm := UI.label(str(cfg.get("name", "")), 20, UI.CREAM, 5)
	UI.place(nm, 76, 8, 124, 26)
	btn.add_child(nm)

	var sub := UI.label("%s · Lv.%d" % [str(cfg.get("rarity", "")), int(card.get("level", 1))],
		16, Color(1, 1, 1, 0.66), 4)
	UI.place(sub, 76, 34, 124, 22)
	btn.add_child(sub)

	if deployed:
		var tag_text := str(_fsec("library").get("deployed_tag", "已上阵"))
		var tag := UI.label("%s · %d" % [tag_text, slot], 15, Color("#FFD98A"), 4)
		UI.place(tag, 76, 58, 124, 20)
		btn.add_child(tag)
	else:
		var hint := UI.label("%s" % GameDB.row_name(GameDB.row_of_slot(
			int(cfg.get("prefer_slot", 1)))), 15, Color(1, 1, 1, 0.42), 4)
		UI.place(hint, 76, 58, 124, 20)
		btn.add_child(hint)

	var elem := UI.icon(GameDB.element_icon(str(cfg.get("element", ""))), 22.0, accent)
	UI.place(elem, 190, 52, 22, 22)
	btn.add_child(elem)
	return btn


# ---------------------------------------------------------------- 3x3 编队棋盘

func _rebuild_board() -> void:
	_clear_children(_board_grid)
	_board_count.text = str(_fsec("team").get("count_text", "上阵 %d/%d")) \
		% [_team.size(), GameDB.team_max()]

	# 行标签（前 / 中 / 后）：棋盘上前排在上，正对敌方
	var rows: Array = _fsec("team").get("row_order", ["front", "middle", "back"])
	for r in rows.size():
		var lb := UI.label(GameDB.row_name(str(rows[r])).substr(0, 1), 18,
			Color(1, 1, 1, 0.46), 4)
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		UI.place(lb, 0, float(r) * (BOARD_CELL.y + BOARD_GAP),
			BOARD_GUTTER - 8.0, BOARD_CELL.y)
		_board_grid.add_child(lb)

	# 格子位置直接读 slot_to_cell：UI 不做第二套坐标，与战斗九宫格永远是同一套
	for slot in range(1, BOARD_CELLS + 1):
		var cell := _make_board_cell(slot)
		var at := GameDB.slot_cell("player", slot)
		var col := clampi(at.x, 0, 2)
		var row := clampi(at.y - 3, 0, 2)
		UI.place(cell, BOARD_GUTTER + float(col) * (BOARD_CELL.x + BOARD_GAP),
			float(row) * (BOARD_CELL.y + BOARD_GAP), BOARD_CELL.x, BOARD_CELL.y)
		_board_grid.add_child(cell)


func _slot_owner(slot: int) -> String:
	for raw in _team:
		if raw is Dictionary and int(raw.get("slot", 0)) == slot:
			return str(raw.get("char_id", ""))
	return ""


func _make_board_cell(slot: int) -> Button:
	var char_id := _slot_owner(slot)
	var occupied := char_id != ""
	var picked := occupied and char_id == _selected_id

	var accent := Color(0.42, 0.36, 0.28, 0.9)
	if occupied:
		accent = GameDB.rarity_color(str(_cfg_of(char_id).get("rarity", "R")))
	var border := UI.GOLD if picked else (accent if occupied else Color(1, 1, 1, 0.12))
	var width := 4 if picked else 3

	var btn := Button.new()
	btn.name = "BoardCell_%d" % slot
	btn.custom_minimum_size = BOARD_CELL
	btn.size = BOARD_CELL
	btn.focus_mode = Control.FOCUS_NONE
	var bg := Color(0.16, 0.12, 0.07, 0.86) if occupied else Color(0.06, 0.05, 0.09, 0.34)
	btn.add_theme_stylebox_override("normal", UI.style(bg, 16, width, border, 0))
	btn.add_theme_stylebox_override("hover",
		UI.style(bg.lightened(0.12), 16, width, border.lightened(0.25), 8, Color(0, 0, 0, 0.4)))
	btn.add_theme_stylebox_override("pressed", UI.style(bg.darkened(0.12), 16, width, border, 0))
	btn.add_theme_stylebox_override("focus", UI.style(Color(0, 0, 0, 0), 16))
	btn.pressed.connect(_on_board_cell_pressed.bind(slot))

	if occupied:
		var pic := UI.picture(str(_cfg_of(char_id).get("portrait", "")),
			TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
		UI.place(pic, 6, 4, BOARD_CELL.x - 12.0, BOARD_CELL.y - 22.0)
		btn.add_child(pic)

		var band := UI.panel(Color(0, 0, 0, 0.60), 0)
		band.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UI.place(band, 3, BOARD_CELL.y - 22.0, BOARD_CELL.x - 6.0, 19.0)
		btn.add_child(band)

		var nm := UI.label(_name_of(char_id), 14, UI.CREAM, 4)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		UI.fill(nm)
		band.add_child(nm)
	else:
		var plus := UI.label("+", 30, Color(1, 1, 1, 0.26), 0)
		plus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		plus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		UI.fill(plus)
		btn.add_child(plus)

		var num := UI.label(str(slot), 14, Color(1, 1, 1, 0.30), 0)
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UI.place(num, 0, 4, BOARD_CELL.x, 18)
		btn.add_child(num)
	return btn


func _on_board_cell_pressed(slot: int) -> void:
	var owner_id := _slot_owner(slot)
	if owner_id == "":
		if _selected_id == "":
			_show_toast(_t("no_select", "先在卡牌陈列或英雄库里选一张卡"))
			return
		_deploy(_selected_id, slot)
		return
	if owner_id == _selected_id:
		_undeploy(owner_id)
	else:
		_select(owner_id)


# ---------------------------------------------------------------- 编队操作

func _slot_of(char_id: String) -> int:
	return RealmDB.slot_of(_team, char_id)


func _deploy(char_id: String, slot: int = 0) -> bool:
	if char_id == "":
		return false
	if _slot_of(char_id) > 0:
		_show_toast(_t("dup", "%s 已在阵中") % _name_of(char_id))
		return false
	if _team.size() >= GameDB.team_max():
		_show_toast(_t("team_full", "上阵已满 %d 人，请先下阵") % GameDB.team_max())
		return false
	var target := slot
	if target <= 0:
		target = RealmDB.free_slot_for(_team, char_id)
	if target <= 0 or _slot_owner(target) != "":
		_show_toast(_t("board_locked", "该槽位已被占用"))
		return false

	_team.append({"slot": target, "char_id": char_id})
	_team = SaveDB.normalize_team(_team)
	_persist()
	_refresh_team()
	_show_toast(_t("deployed", "已上阵 %s（%s · 槽位 %d）")
		% [_name_of(char_id), GameDB.row_name(GameDB.row_of_slot(target)), target])
	return true


func _undeploy(char_id: String) -> void:
	var out: Array = []
	var hit := false
	for raw in _team:
		if raw is Dictionary and str(raw.get("char_id", "")) == char_id:
			hit = true
			continue
		out.append(raw)
	if not hit:
		return
	_team = out
	_persist()
	_refresh_team()
	_show_toast(_t("removed", "已下阵 %s") % _name_of(char_id))


func _on_deploy_pressed() -> void:
	if _selected_id == "":
		_show_toast(_t("no_select", "先在卡牌陈列或英雄库里选一张卡"))
		return
	_deploy(_selected_id)


func _on_remove_pressed() -> void:
	if _selected_id == "" or _slot_of(_selected_id) <= 0:
		return
	_undeploy(_selected_id)


func _on_clear() -> void:
	if _team.is_empty():
		return
	_team = []
	_persist()
	_refresh_team()
	_show_toast(_t("cleared", "已清空编队（改动已保存）"))


## 一键上阵：按「战力 + 本关克制收益」排序，填满到上限
func _on_quick_fill() -> void:
	var enemy := GameDB.stage_enemy_units(int(BattleCtx.stage_id))
	# 不把打分写回 item 本身（_all_items 里是共享字典），另起一份排名表更干净
	var ranked: Array = []
	for item in _all_items:
		ranked.append({"score": _fill_score(item, enemy), "item": item})
	ranked.sort_custom(func(a, b): return int(a.get("score", 0)) > int(b.get("score", 0)))

	var picked: Array = []
	for raw in ranked:
		if picked.size() >= GameDB.team_max():
			break
		var item: Dictionary = raw.get("item", {})
		var char_id := str(item.get("char_id", ""))
		var slot := RealmDB.free_slot_for(picked, char_id)
		if slot <= 0:
			continue
		picked.append({"slot": slot, "char_id": char_id})

	_team = SaveDB.normalize_team(picked)
	_persist()
	_refresh_team()
	_show_toast(_t("auto_filled", "一键上阵：%d 人 · 队伍战力 %s")
		% [_team.size(), UI.fmt_num(int(_report.get("total_power", 0)))])


## 打分：战力为主，命中属性克制与职业克制再额外加权
func _fill_score(item: Dictionary, enemy_units: Array) -> int:
	var score := int(item.get("power", 0))
	var rep := RealmDB.counter_report(item, enemy_units)
	score += int(rep.get("hits", 0)) * 6000 + int(rep.get("pct", 0)) * 150
	return score


# ---------------------------------------------------------------- 刷新

func _refresh_team() -> void:
	_team = SaveDB.normalize_team(_team)
	_report = RealmDB.formation_report(_team)
	_rebuild_board()
	_rebuild_library()
	_refresh_power()
	_refresh_tactical()
	_refresh_preset_hint()
	_refresh_buttons()
	_refresh_fan_selection()


func _refresh_power() -> void:
	_power_value.text = UI.fmt_num(int(_report.get("total_power", 0)))
	var parts: Dictionary = _fsec("team").get("power_parts", {})
	_power_parts.text = "%s %s　｜　%s +%s　｜　上阵 %d/%d" % [
		str(parts.get("base", "基础")), UI.fmt_num(int(_report.get("base_power", 0))),
		str(parts.get("synergy", "羁绊")), UI.fmt_num(int(_report.get("synergy_power", 0))),
		int(_report.get("count", 0)), GameDB.team_max(),
	]


func _refresh_buttons() -> void:
	var has_pick := _selected_id != ""
	var deployed := has_pick and _slot_of(_selected_id) > 0
	var full := _team.size() >= GameDB.team_max()
	_deploy_btn.disabled = not has_pick or deployed or full
	_remove_btn.disabled = not deployed
	_clear_btn.disabled = _team.is_empty()


## 选中：只改「正在查看」的那张卡，不动编队
func _select(char_id: String) -> void:
	if char_id == "":
		return
	_selected_id = char_id
	_refresh_fan_selection()
	_rebuild_board()
	_rebuild_library()
	_refresh_tactical()
	_refresh_buttons()
	# 用户点选（卡牌 / 卡库 / 棋盘格）时把陈列滚到这张卡；进场默认选中不算
	if _boot_ready:
		_card_stage.focus_card(char_id)


func _selected_unit() -> Dictionary:
	var item := _item_of(_selected_id)
	if item.is_empty():
		return {}
	return {
		"char_id": _selected_id,
		"config": item.get("config", {}),
		"card": item.get("card", {}),
		"stats": item.get("stats", {}),
		"power": int(item.get("power", 0)),
	}


# ---------------------------------------------------------------- 战术面板

func _refresh_tactical() -> void:
	var unit := _selected_unit()
	for raw in _fsec("tactical").get("boxes", []):
		var b: Dictionary = raw
		var id := str(b.get("id", ""))
		var box: Control = _tactical.get_node_or_null("TacticBox_%s" % id)
		if box == null:
			continue
		var body: Control = box.get_node_or_null("Body")
		if body == null:
			continue
		_clear_children(body)
		match id:
			"role_counter":
				_fill_role_counter(body)
			"counter_bonus":
				_fill_counter_bonus(body, unit)
			"synergy":
				_fill_synergy(body)
			"battle_role":
				_fill_battle_role(body, unit)


## 职业克制：把配置里的克制链画成「图标 ▶ 图标」，敌方阵容里出现过的职业高亮
func _fill_role_counter(body: Control) -> void:
	var chain: Array = GameDB.role_chain()
	if chain.is_empty():
		body.add_child(_empty_label())
		return
	var stage_id := int(BattleCtx.stage_id)
	var comp := GameDB.stage_enemy_comp(stage_id)
	var enemy_roles: Dictionary = comp.get("roles", {})
	var cell := 46.0
	var arrow := 16.0
	var total := cell * float(chain.size()) + arrow * float(maxi(0, chain.size() - 1))
	var x := maxf(0.0, (body.size.x - total) * 0.5)
	for i in chain.size():
		var rid := str(chain[i])
		var r := GameDB.role(rid)
		var hit := int(enemy_roles.get(rid, 0)) > 0
		var ic := UI.icon(str(r.get("icon", "")), 30.0,
			Color("#FFD98A") if hit else Color(1, 1, 1, 0.34))
		UI.place(ic, x + (cell - 30.0) * 0.5, 4, 30, 30)
		body.add_child(ic)

		var nm := UI.label(str(r.get("name", rid)), 15,
			Color("#FFE9A8") if hit else Color(1, 1, 1, 0.42), 4)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UI.place(nm, x, 36, cell, 22)
		body.add_child(nm)

		if i < chain.size() - 1:
			var sep := UI.label("▶", 16, Color(1, 1, 1, 0.32), 0)
			sep.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			sep.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			UI.place(sep, x + cell, 0, arrow, 40)
			body.add_child(sep)
		x += cell + arrow

	# 没从选关页进来时没有敌方阵容可谈，别显示成「本关 0 个目标」误导玩家
	var tag_text := str(_fsec("tactical").get("no_stage", "未选择关卡"))
	if stage_id > 0:
		tag_text = "本关 %d 个目标 · 元素 %d 种" % [
			_count_values(comp.get("roles", {})),
			(comp.get("elements", {}) as Dictionary).size()]
	var tag := UI.label(tag_text, 15, Color(1, 1, 1, 0.55), 4)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.place(tag, 0, body.size.y - 22.0, body.size.x, 20)
	body.add_child(tag)


func _fill_counter_bonus(body: Control, unit: Dictionary) -> void:
	var tac := _fsec("tactical")
	if unit.is_empty():
		body.add_child(_empty_label())
		return
	var enemy := GameDB.stage_enemy_units(int(BattleCtx.stage_id))
	var rep := RealmDB.counter_report(unit, enemy)
	var lines: Array = rep.get("lines", [])
	_tooltip_tactic("counter_bonus", "\n".join(lines))
	if lines.is_empty():
		var none := UI.label(str(tac.get("counter_none", "本关无克制目标")), 18,
			Color(1, 1, 1, 0.70), 4)
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		none.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UI.fill(none)
		body.add_child(none)
		return
	# 最多铺两行：box 内高只有 ~102px，第三条会被裁掉，不如显式截断
	var y := 0.0
	for i in mini(2, lines.size()):
		var l := UI.label(str(lines[i]), 17, Color("#FFD98A"), 4)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UI.place(l, 0, y, body.size.x, 46.0)
		body.add_child(l)
		y += 46.0


## 羁绊框：给定「几条生效」，再展开**第一条**的具体收益（与概念稿一致）。
## 逐条铺开在 3 条以上必然溢出 —— box 内高只有 ~102px，所以只摘要 + 首条，
## 完整清单挂在格子 tooltip 上。
func _fill_synergy(body: Control) -> void:
	var tac := _fsec("tactical")
	var active: Array = _report.get("synergies", [])
	_tooltip_tactic("synergy", _synergy_tooltip(active))
	if active.is_empty():
		var hint := str(_report.get("hint", ""))
		var text := hint if hint != "" else str(tac.get("no_synergy", "当前组合未激活羁绊"))
		var l := UI.label(text, 17, Color(1, 1, 1, 0.62), 4)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UI.fill(l)
		body.add_child(l)
		return

	var head := UI.label(str(tac.get("synergy_count", "%d 条羁绊生效")) % active.size(),
		18, Color("#FFD98A"), 5)
	UI.place(head, 0, 0, body.size.x, 22)
	body.add_child(head)

	var first: Dictionary = active[0]
	var effect := UI.label("%s：%s" % [str(first.get("name", "")), str(first.get("text", ""))],
		15, Color(1, 1, 1, 0.78), 4)
	effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UI.place(effect, 0, 24, body.size.x, body.size.y - 24.0)
	body.add_child(effect)


func _synergy_tooltip(active: Array) -> String:
	if active.is_empty():
		return ""
	var lines: Array = []
	for raw in active:
		var a: Dictionary = raw
		lines.append("· %s：%s" % [str(a.get("name", "")), str(a.get("text", ""))])
	return "\n".join(lines)


## 把完整清单挂到战术格子上：格子内只放得下摘要，长文案走 tooltip
func _tooltip_tactic(id: String, text: String) -> void:
	var box: Control = _tactical.get_node_or_null("TacticBox_%s" % id)
	if box != null:
		box.tooltip_text = text


func _fill_battle_role(body: Control, unit: Dictionary) -> void:
	if unit.is_empty():
		body.add_child(_empty_label())
		return
	var cfg: Dictionary = unit.get("config", {})
	var rid := str(cfg.get("role", ""))
	var head := UI.label(_clamp(GameDB.battle_role_text(rid), 26), 20, Color("#FFE9A8"), 5)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UI.place(head, 0, 0, body.size.x, 30)
	body.add_child(head)

	var rows: Array = GameDB.role(rid).get("prefer_rows", [])
	var row_text := "—"
	if not rows.is_empty():
		row_text = GameDB.row_name(str(rows[0]))
	var skill: Dictionary = cfg.get("skill", {})
	var info := UI.label("推荐 %s　·　绝技 %s" % [row_text, str(skill.get("name", "—"))],
		16, Color(1, 1, 1, 0.72), 4)
	_tooltip_tactic("battle_role", "%s\n%s：%s" % [
		GameDB.battle_role_text(rid), str(skill.get("name", "")), str(skill.get("desc", ""))])
	UI.place(info, 0, 32, body.size.x, 24)
	body.add_child(info)

	# 技能描述长度由策划决定，这里按 box 宽度裁一刀，别让它冲出格子
	var desc := UI.label(_clamp(str(skill.get("desc", "")), _desc_limit()), 14,
		Color(1, 1, 1, 0.60), 4)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UI.place(desc, 0, 58, body.size.x, 44)
	body.add_child(desc)


## 按 box 宽度估算「两行装得下多少个汉字」，超出加省略号
func _desc_limit() -> int:
	var body_w := (TAC_BOX_W - 20.0)
	return maxi(16, int(body_w / 14.0) * 2)


func _clamp(text: String, limit: int) -> String:
	if text.length() <= limit:
		return text
	return text.substr(0, limit - 1) + "…"


func _empty_label() -> Label:
	var l := UI.label(str(_fsec("tactical").get("empty_text", "—")), 20,
		Color(1, 1, 1, 0.40), 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UI.fill(l)
	return l


func _count_values(table: Variant) -> int:
	if not (table is Dictionary):
		return 0
	var n := 0
	for k in (table as Dictionary).keys():
		n += int((table as Dictionary)[k])
	return n


# ---------------------------------------------------------------- 即时落盘

## 编队改动即时写档：同时写进「当前预设 + 出战编队（profile.team）」，
## 从主界面「编队」入口进来改完就走，不点「确认选择」也是永久的；
## 主界面阵容栏 / 扇形大卡读的正是这份档。
## 「确认选择」因此只负责扣体力与切战斗场景，不再兼任保存。
func _persist() -> void:
	SaveDB.save_preset(_preset_id, _team)
	SaveDB.set_team(_team)


## 保存按钮：改动本就即时落盘，这里再显式存一次并给确认反馈；
## 空队也允许存（清空本身就是一种编队选择）。
func _on_save() -> void:
	_persist()
	_show_toast(_t("saved", "编队已保存（%d 人）") % _team.size())


# ---------------------------------------------------------------- 确认 / 返回

func _on_confirm() -> void:
	if _team.is_empty():
		_show_toast(_t("team_empty", "至少上阵 1 名英雄再出发"))
		return
	var stage_id := int(BattleCtx.stage_id)
	if stage_id <= 0:
		_show_toast(_t("no_stage", "还没有选择关卡"))
		return
	# 体力在**这一步**扣：选关页只做校验，玩家在编队页改完阵容再真正确认出发
	var cost := GameDB.stage_stamina(stage_id)
	if cost > 0 and not StaminaSys.spend(cost):
		_show_toast(_t("no_stamina", "体力不足：需要 %d 点，当前 %d 点") \
			% [cost, StaminaSys.current(), StaminaSys.format_next()])
		return

	_persist()
	_show_toast(_t("ready", "阵容就绪 · 进入关卡 %d") \
		% [stage_id, UI.fmt_num(int(_report.get("total_power", 0)))])
	if auto_transition:
		_go_battle()


func _go_battle() -> void:
	if ResourceLoader.exists(battle_scene):
		get_tree().change_scene_to_file(battle_scene)
	else:
		_show_toast("战斗场景缺失：%s" % battle_scene)


func _on_back() -> void:
	var route := str(_fsec("back_button").get("route", "res://scenes/main_menu.tscn"))
	if ResourceLoader.exists(route):
		get_tree().change_scene_to_file(route)
	else:
		_show_toast("目标场景缺失：%s" % route)


# ---------------------------------------------------------------- 动效

func _play_intro() -> void:
	var stage: Control = %CardStage
	var target: Vector2 = stage.position
	stage.position = target + Vector2(0, 90)
	stage.modulate.a = 0.0
	var t := create_tween().set_parallel(true)
	t.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(stage, "position", target, 0.44)
	t.tween_property(stage, "modulate:a", 1.0, 0.34)

	var panels: Array = [%BoardPanel, %LibraryPanel, %TacticalPanel, %CommandPanel]
	for i in panels.size():
		var p: Control = panels[i]
		var home: Vector2 = p.position
		p.position = home + Vector2(0, 40)
		p.modulate.a = 0.0
		var pt := create_tween().set_parallel(true)
		pt.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		pt.tween_property(p, "position", home, 0.34).set_delay(0.05 * float(i))
		pt.tween_property(p, "modulate:a", 1.0, 0.28).set_delay(0.05 * float(i))
	_intro_done = true


# ---------------------------------------------------------------- 反馈与工具

func _show_toast(text: String) -> void:
	_toast_label.text = text
	_toast.visible = true
	_toast.modulate.a = 0.0
	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.14)
	_toast_tween.tween_interval(3.0)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.35)
	_toast_tween.tween_callback(func(): _toast.visible = false)


func _clear_children(node: Node) -> void:
	# 必须先 remove_child 再 queue_free：queue_free 是延迟释放，
	# 同一帧里 add_child 同名节点会被自动改名成 @XXX@2，后续按名取就取不到了。
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()
