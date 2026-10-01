extends Control
## StageSelect —— 冒险关卡选择
##
## 场景骨架由 tools/build_stage_select.gd 程序化生成；
## 本脚本只做三件事：把配置里的关卡地图接到界面、把交互接起来、做入场动效。
##
## 数据流向：GameDB.adventure.select_map（地图配置）+ SaveDB（进度）→ 界面
## 地图锚点全部来自配置（1920x1080 基准像素），本脚本不硬编码任何关卡坐标。

const UI := preload("res://tools/ui_kit.gd")
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const BATTLE_SCENE := "res://scenes/battle.tscn"
## 「进入关卡」不再直接开打，而是先进编队页做最后的上阵决策（见 formation.spend_stamina_at）
const FORMATION_SCENE := "res://scenes/formation.tscn"
const STAR_ICON := "res://assets/icons/icon_star.svg"

## 冒烟测试要把「校验体力 → 记录关卡 → 交接给编队页」验完，但不希望真的切场景，
## 于是把切场景这一步做成开关：测试里置 false，跑完断言再退出。
var auto_transition := true

const NODE_BOX := Vector2(300, 400)      ## 单个关卡节点的占位盒
const ANCHOR_IN_BOX := Vector2(150, 150) ## 锚点（该关浮岛的中心）落在盒内的位置
const TAG_OFFSET := Vector2(-42, -114)   ## 「精」角标中心相对锚点的偏移（概念稿实测）
const TAG_SIZE := Vector2(54, 46)
const DEFAULT_GLOW := 250.0              ## 无叠加图标的节点，选中光晕的直径
const LABEL_LH := 44.0                   ## 名称 / 等级两行「行心」的间距
## 行盒高度。必须 ≥ 实际渲染高度（字号 38 + 描边 6 -> 约 51px），否则 Godot 会
## 把 size 撑到最小高度，行盒变大、垂直居中后文字中心就偏离 first_y 了。
const LABEL_H := 56.0
const LABEL_NAME_SIZE := 38
const LABEL_LEVEL_SIZE := 27
## 设计稿的文字是「奶白填充 + 深棕粗描边 + 下方投影」，没有底衬色块，
## 所以这里靠描边而不是靠面板来保证可读性。
const LABEL_OUTLINE := 6
const LABEL_OUTLINE_COLOR := Color("#43220A")
const SELECTED_SCALE := 1.12             ## 选中节点整体放大，对应稿里 1003 更醒目
const TEAM_SLOTS := 3                    ## 底部预览条的物理格数（概念稿固定 3 格）

@onready var _node_layer: Control = %NodeLayer
@onready var _guide_layer: Control = %GuideLayer
@onready var _decor_layer: Control = %DecorLayer
@onready var _chapter_tabs: HBoxContainer = %ChapterTabs
@onready var _section_tabs: HBoxContainer = %SectionTabs
@onready var _team_slots: HBoxContainer = %TeamSlots
@onready var _team_label: Label = %TeamLabel
@onready var _enter: Button = %EnterButton
@onready var _enter_sub: Label = %EnterSub
@onready var _back: Button = %BackButton
@onready var _toast: Panel = %Toast
@onready var _toast_label: Label = %ToastLabel
@onready var _footer: Label = %FooterInfo
@onready var _stamina_value: Label = %StaminaValue
@onready var _stamina_next: Label = %StaminaNext
@onready var _gold: Label = %GoldLabel
@onready var _gem: Label = %GemLabel
@onready var _player_name: Label = %PlayerName
@onready var _player_level: Label = %PlayerLevel
@onready var _exp_bar: ProgressBar = %ExpBar
@onready var _avatar: TextureRect = %AvatarTex

var _selected := 0
var _nodes: Dictionary = {}          # stage_id -> Button
var _chapter_btns: Dictionary = {}   # chapter_id -> Button
var _section_btns: Dictionary = {}   # section_id -> Button
var _current_section := ""           # 当前展示的小节 id
var _toast_tween: Tween
var _glow_tween: Tween
var _clock: Timer
var _intro_done := false


func _ready() -> void:
	_bind_player()
	_build_chapter_tabs()
	# 默认停在已解锁的最高小节（frontier）；打完返回时按存档重算，自然展示新解锁小节
	var order: Array = GameDB.section_order()
	if not order.is_empty():
		_current_section = str(order[_frontier_section_index()])
	_build_section_tabs()
	_build_map()
	_build_team()
	_bind_inputs()
	_select_stage(_default_stage())
	_refresh_stamina()
	_watch_stamina()
	_refresh_footer()
	_play_intro()


# ---------------------------------------------------------------- 数据接线

func _bind_player() -> void:
	var p: Dictionary = SaveDB.profile.get("player", {})
	_player_name.text = str(p.get("name", "云上旅人"))
	_player_level.text = "Lv.%d" % int(p.get("level", 1))
	# 经验条与主界面同口径：运行时以存档为准回写，不靠场景烘焙值
	var exp_max := maxi(1, int(p.get("exp_max", GameDB.player_exp_max(int(p.get("level", 1))))))
	if _exp_bar != null:
		_exp_bar.max_value = exp_max
		_exp_bar.value = clampi(int(p.get("exp", 0)), 0, exp_max)

	var av := str(p.get("avatar", ""))
	if av != "" and ResourceLoader.exists(av):
		_avatar.texture = load(av)

	_gold.text = UI.fmt_num(SaveDB.balance("gold"))
	_gem.text = UI.fmt_num(SaveDB.balance("gem"))


# ---------------------------------------------------------------- 章节切换栏

## 按 chapter_tabs 配置铺出顶部页签：当前章高亮可点，其余章置灰。
## 目前只有当前章（ch1）有地图数据，所以锁定章与非当前章都只给反馈、不重建地图。
func _build_chapter_tabs() -> void:
	_clear(_chapter_tabs)
	_chapter_btns.clear()
	var cur := GameDB.current_chapter_id()

	for raw in GameDB.chapter_tabs():
		var tab: Dictionary = raw
		var id := str(tab.get("id", ""))
		var locked := bool(tab.get("locked", id != cur))
		var is_current := id == cur

		var btn := Button.new()
		btn.name = "ChapterTab_%s" % id
		btn.text = str(tab.get("label", id))
		btn.custom_minimum_size = Vector2(240, 56)
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_override("font", load(UI.FONT_MAIN))
		btn.add_theme_font_size_override("font_size", 26)

		var bg := Color(0.09, 0.07, 0.13, 0.60)
		var border := Color(1.0, 0.85, 0.45, 0.35)
		var font := Color(1, 1, 1, 0.55)
		if is_current:
			bg = Color("#FFC94A")
			border = Color("#B8791F")
			font = Color("#4A2408")
		elif not locked:
			border = Color(1.0, 0.85, 0.45, 0.6)
			font = UI.CREAM
		btn.add_theme_stylebox_override("normal", UI.style(bg, 16, 3, border, 10, Color(0, 0, 0, 0.4)))
		btn.add_theme_stylebox_override("hover",
			UI.style(bg.lightened(0.08), 16, 3, border.lightened(0.15), 14, Color(0, 0, 0, 0.45)))
		btn.add_theme_stylebox_override("pressed", UI.style(bg.darkened(0.1), 16, 3, border, 6, Color(0, 0, 0, 0.4)))
		btn.add_theme_stylebox_override("focus", UI.style(Color(0, 0, 0, 0), 16))
		btn.add_theme_color_override("font_color", font)
		btn.add_theme_color_override("font_hover_color", font)
		btn.add_theme_color_override("font_pressed_color", font)

		var name_txt := str(tab.get("name", ""))
		btn.tooltip_text = name_txt if locked or is_current else "%s · 可切换" % name_txt
		if locked:
			btn.tooltip_text = "%s · 敬请期待" % name_txt
		btn.pressed.connect(_on_chapter_pressed.bind(id, locked, str(tab.get("label", id)), name_txt))
		_chapter_tabs.add_child(btn)
		_chapter_btns[id] = btn


func _on_chapter_pressed(id: String, locked: bool, label: String, chap_name: String) -> void:
	if id == GameDB.current_chapter_id():
		return  # 当前章：不重建，保持已选关卡
	if locked:
		_show_toast("%s（%s）尚未解锁 · 敬请期待" % [label, chap_name])
		return
	# 非锁定但尚无地图数据的章节（未来扩展位）
	_show_toast("%s（%s）地图待接入" % [label, chap_name])


# ---------------------------------------------------------------- 小节切换栏

## 按 sections 配置铺出小节页签：当前节高亮、已解锁未选中节可点、锁定节置灰。
func _build_section_tabs() -> void:
	_clear(_section_tabs)
	_section_btns.clear()
	var order: Array = GameDB.section_order()
	for i in order.size():
		var id := str(order[i])
		var cfg := GameDB.section_cfg(id)
		var unlocked := _section_unlocked(i)
		var is_current := id == _current_section

		var btn := Button.new()
		btn.name = "SectionTab_%s" % id
		btn.text = str(cfg.get("label", id))
		btn.custom_minimum_size = Vector2(200, 48)
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_override("font", load(UI.FONT_MAIN))
		btn.add_theme_font_size_override("font_size", 22)

		var bg := Color(0.09, 0.07, 0.13, 0.55)
		var border := Color(1.0, 0.85, 0.45, 0.30)
		var font := Color(1, 1, 1, 0.5)
		if is_current:
			bg = Color("#FFC94A")
			border = Color("#B8791F")
			font = Color("#4A2408")
		elif unlocked:
			border = Color(1.0, 0.85, 0.45, 0.6)
			font = UI.CREAM
		btn.add_theme_stylebox_override("normal", UI.style(bg, 14, 2, border, 9, Color(0, 0, 0, 0.4)))
		btn.add_theme_stylebox_override("hover",
			UI.style(bg.lightened(0.08), 14, 2, border.lightened(0.15), 12, Color(0, 0, 0, 0.45)))
		btn.add_theme_stylebox_override("pressed", UI.style(bg.darkened(0.1), 14, 2, border, 5, Color(0, 0, 0, 0.4)))
		btn.add_theme_stylebox_override("focus", UI.style(Color(0, 0, 0, 0), 14))
		btn.add_theme_color_override("font_color", font)
		btn.add_theme_color_override("font_hover_color", font)
		btn.add_theme_color_override("font_pressed_color", font)

		var sec_name := str(cfg.get("name", ""))
		if not unlocked:
			btn.tooltip_text = "%s · 通关上一小节解锁" % sec_name
		elif is_current:
			btn.tooltip_text = sec_name
		else:
			btn.tooltip_text = "%s · 可切换" % sec_name
		btn.pressed.connect(_on_section_pressed.bind(id, unlocked, str(cfg.get("label", id)), sec_name))
		_section_tabs.add_child(btn)
		_section_btns[id] = btn


func _on_section_pressed(id: String, unlocked: bool, label: String, sec_name: String) -> void:
	if id == _current_section:
		return  # 当前节：不重建，保持已选关卡
	if not unlocked:
		_show_toast("%s（%s）尚未解锁 · 请先通关上一小节" % [label, sec_name])
		return
	_switch_section(id)


## 切到某个小节：换当前节 → 重铺页签高亮 → 重画子地图 → 选默认关
func _switch_section(id: String) -> void:
	_current_section = id
	_build_section_tabs()
	_build_map()
	_select_stage(_default_stage())


## 第 idx 节是否解锁：首节恒开；其余需「上一节守关关」已通关（存档 stage_clears）
func _section_unlocked(idx: int) -> bool:
	if idx <= 0:
		return true
	var order: Array = GameDB.section_order()
	if idx >= order.size():
		return false
	var prev_gate := GameDB.section_gate_stage(str(order[idx - 1]))
	return prev_gate > 0 and SaveDB.stage_clear_count(prev_gate) > 0


## 已解锁的最高小节下标（frontier）：从 0 起连续解锁到的最后一节
func _frontier_section_index() -> int:
	var order: Array = GameDB.section_order()
	var frontier := 0
	for i in order.size():
		if _section_unlocked(i):
			frontier = i
		else:
			break
	return frontier


## 按配置锚点铺出地图：引导线在下，关卡节点在上
##
## 装饰浮岛（decor_islands）不渲染 —— 选关页背景 bg_stage_select.png 就是概念稿
## 底图，浮岛美术已经画在里面了，再叠一层会跟背景打架；锚点仍留在配置里，
## 换背景时可随时启用。
##
## 同理，节点的叠加图标也是可选的：icon 为空表示该关浮岛由背景自带。
## 只有 1004 的雷云在背景里不存在，才需要 stage_isle_storm.svg 补上。
func _build_map() -> void:
	_clear(_guide_layer)
	_clear(_node_layer)
	_nodes.clear()

	_draw_guides()

	for raw in GameDB.section_nodes(_current_section):
		var cfg: Dictionary = raw
		var btn := _make_stage_node(cfg)
		_nodes[int(cfg.get("stage_id", 0))] = btn
		_node_layer.add_child(btn)

	# 每次重铺子地图都要重新接好节点的 pressed：切小节时旧按钮被释放，
	# 只连一次的话新节点就点不动（选中 / 进关都会失灵）。
	_bind_nodes()


func _clear(holder: Node) -> void:
	for child in holder.get_children():
		# 必须先 remove_child 再 queue_free：queue_free 是延迟释放，
		# 同一帧里 add_child 同名节点会被自动改名成 @XXX@2，后续按名取就取不到了。
		holder.remove_child(child)
		child.queue_free()


# ---------------------------------------------------------------- 地图元素

func _make_stage_node(cfg: Dictionary) -> Button:
	var sid := int(cfg.get("stage_id", 0))
	var anchor := GameDB.stage_node_pos(sid)
	var z := maxi(1, int(cfg.get("z", 1)))
	var icon_size := float(cfg.get("icon_size", 0))

	var btn := Button.new()
	btn.name = "StageNode_%d" % sid
	btn.custom_minimum_size = NODE_BOX
	btn.size = NODE_BOX
	btn.position = anchor - ANCHOR_IN_BOX
	# pivot 落在锚点上：选中放大与入场动效都绕锚点做，锚点不会漂
	btn.pivot_offset = ANCHOR_IN_BOX
	btn.z_index = z
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_stylebox_override("normal", UI.style(Color(0, 0, 0, 0), 22))
	btn.add_theme_stylebox_override("hover",
		UI.style(Color(1.0, 0.85, 0.45, 0.12), 22, 2, Color(1.0, 0.85, 0.45, 0.35)))
	btn.add_theme_stylebox_override("pressed",
		UI.style(Color(1.0, 0.85, 0.45, 0.20), 22, 2, Color(1.0, 0.85, 0.45, 0.5)))
	btn.add_theme_stylebox_override("focus", UI.style(Color(0, 0, 0, 0), 22))

	# 选中光晕：直径跟着节点自身的可视范围走（有叠加图标就跟图标，没有就跟背景浮岛）
	var glow_d := (icon_size if icon_size > 0.0 else DEFAULT_GLOW) + 70.0
	var glow := UI.glow_rect(Color("#FFC94A"), 0.55)
	glow.name = "SelectionGlow"
	UI.place(glow, ANCHOR_IN_BOX.x - glow_d * 0.5, ANCHOR_IN_BOX.y - glow_d * 0.5,
		glow_d, glow_d)
	glow.visible = false
	btn.add_child(glow)

	# 叠加图标是可选的：icon 为空表示该关浮岛已画在背景里，再叠一层会重复
	var icon_path := str(cfg.get("icon", ""))
	if icon_path != "" and icon_size > 0.0:
		var isle := UI.icon(icon_path, icon_size)
		isle.name = "IsleIcon"
		UI.place(isle, ANCHOR_IN_BOX.x - icon_size * 0.5,
			ANCHOR_IN_BOX.y - icon_size * 0.5, icon_size, icon_size)
		btn.add_child(isle)

	var tag := str(cfg.get("tag", ""))
	if tag != "":
		btn.add_child(_make_tag_badge(tag))

	_build_node_labels(btn, cfg)
	return btn


func _make_tag_badge(text: String) -> Control:
	var badge := UI.panel(Color("#D9503F"), 12, 2, Color("#FFE9A8"), 6, Color(0, 0, 0, 0.4))
	badge.name = "TagBadge"
	var c := ANCHOR_IN_BOX + TAG_OFFSET
	UI.place(badge, c.x - TAG_SIZE.x * 0.5, c.y - TAG_SIZE.y * 0.5, TAG_SIZE.x, TAG_SIZE.y)
	var l := UI.label(text, 26, UI.CREAM, 5)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UI.fill(l)
	badge.add_child(l)
	return badge


## 名称 / 等级两行的先后顺序由配置的 label_order 决定
## （概念稿里「风暴元素」是等级在上、名称在下，另两处反之）
##
## 标签的纵向落点不看节点盒，而是由每个节点自己的 label_dy 决定 ——
## 三处浮岛的高低各不相同（城堡高耸、石台平缓），用同一套偏移对不齐。
func _build_node_labels(btn: Button, cfg: Dictionary) -> void:
	var sid := int(cfg.get("stage_id", 0))
	var name_text := str(cfg.get("name", ""))
	var level_text := "%d级 %d" % [int(cfg.get("level", 1)), sid]
	var name_first := str(cfg.get("label_order", "name_level")) == "name_level"
	var first_y := ANCHOR_IN_BOX.y + float(cfg.get("label_dy", 56))

	var l1 := UI.label(name_text if name_first else level_text,
		LABEL_NAME_SIZE, UI.CREAM, LABEL_OUTLINE, LABEL_OUTLINE_COLOR)
	l1.name = "LabelA"
	l1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l1.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UI.place(l1, 0.0, first_y - LABEL_H * 0.5, NODE_BOX.x, LABEL_H)
	btn.add_child(l1)

	var l2 := UI.label(level_text if name_first else name_text,
		LABEL_LEVEL_SIZE, Color("#FFE0A0"), LABEL_OUTLINE, LABEL_OUTLINE_COLOR)
	l2.name = "LabelB"
	l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l2.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UI.place(l2, 0.0, first_y + LABEL_LH - LABEL_H * 0.5, NODE_BOX.x, LABEL_H)
	btn.add_child(l2)

	var stars := _stars_of(sid)
	if stars > 0:
		btn.add_child(_make_star_row(stars, first_y + LABEL_LH * 1.5))


func _make_star_row(stars: int, center_y: float) -> HBoxContainer:
	var size := 30.0
	var gap := 5.0
	var total := size * 3.0 + gap * 2.0
	var row := HBoxContainer.new()
	row.name = "StarRow"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", int(gap))
	UI.place(row, (NODE_BOX.x - total) * 0.5, center_y - size * 0.5, total, size + 2.0)
	for i in 3:
		var s := UI.icon(STAR_ICON, size,
			Color("#FFD45E") if i < stars else Color(0.30, 0.20, 0.12, 0.72))
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(s)
	return row


## 引导线：按各节点的 pre_stage_id 逐段画，三层叠出流光质感。
##
## 两端各按节点的 radius 从中心收回 —— 概念稿里的引导线是两座浮岛之间露出的
## 一小段，直接连中心的话会横穿城堡、盖住关卡名，还会在石台上拖出一整条长线。
func _draw_guides() -> void:
	for pair in GameDB.section_links(_current_section):
		var a := int(pair[0])
		var b := int(pair[1])
		var pa := GameDB.stage_node_pos(a)
		var pb := GameDB.stage_node_pos(b)
		var dir := (pb - pa).normalized()
		var start := pa + dir * float(GameDB.stage_node(a).get("radius", 110))
		var end := pb - dir * float(GameDB.stage_node(b).get("radius", 90))
		if start.distance_to(end) < 24.0:
			continue
		var pts := PackedVector2Array([start, end])
		# 垫一层暖褐暗底：引导线要横跨天空的橙黄天光，纯金色在那上面几乎看不见，
		# 先压一条暗色再叠亮芯，才能像概念稿那样任何背景上都跳得出来。
		_add_line("GuideShadow", pts, 42.0, Color(0.24, 0.10, 0.03, 0.32))
		_add_line("GuideGlow", pts, 30.0, Color(1.0, 0.72, 0.28, 0.22))
		_add_line("GuideMid", pts, 16.0, Color(1.0, 0.84, 0.42, 0.62))
		_add_line("GuideCore", pts, 7.0, Color(1.0, 0.90, 0.52, 1.0))


func _add_line(nm: String, pts: PackedVector2Array, width: float, color: Color) -> void:
	var line := Line2D.new()
	line.name = nm
	line.points = pts
	line.width = width
	line.default_color = color
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.antialiased = true
	_guide_layer.add_child(line)


# ---------------------------------------------------------------- 队伍

## 底部队伍预览条：与主界面 / 编队页同一口径 —— 显示玩家真实上阵
## （SaveDB.resolved_team 经 roster_of 造 unit），新号 0 卡时如实显示空槽，
## 不再回落到配置里的展演队（team_panel.lineup）。面板物理容量固定 3 格，
## 超出取前 3、不足补空；角标「RxC N」的 N 同步为实际上阵人数。
func _build_team() -> void:
	for c in _team_slots.get_children():
		# 先 remove_child 再 queue_free：queue_free 延迟到帧尾，同一帧重建时
		# 旧槽仍会在树上，会与新槽叠成双份。
		_team_slots.remove_child(c)
		c.queue_free()

	var units: Array = []
	if not SaveDB.cards().is_empty():
		units = RealmDB.roster_of(SaveDB.resolved_team())

	for i in TEAM_SLOTS:
		_team_slots.add_child(_make_team_slot(units[i]) if i < units.size() else _make_empty_slot())

	var tp: Dictionary = GameDB.select_map().get("team_panel", {})
	if _team_label != null:
		_team_label.text = "%dx%d %d" % [int(tp.get("rows", 3)), int(tp.get("cols", 3)), units.size()]


## 单个头像槽：稀有度描边 + 立绘
func _make_team_slot(unit: Dictionary) -> Panel:
	var cfg: Dictionary = unit.get("config", {})
	var rar := GameDB.rarity(str(cfg.get("rarity", "R")))
	var accent := Color(str(rar.get("color", "#FFFFFF")))
	var slot := Panel.new()
	slot.custom_minimum_size = Vector2(72, 72)
	slot.add_theme_stylebox_override("panel",
		UI.style(Color(0.06, 0.05, 0.09, 0.85), 18, 3, accent, 0))
	var pic := UI.picture(str(cfg.get("portrait", "")), TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	UI.fill(pic)
	pic.offset_left = 5
	pic.offset_top = 5
	pic.offset_right = -5
	pic.offset_bottom = -5
	slot.add_child(pic)
	return slot


## 空槽：未上阵 / 新号 0 卡时的占位暗格（虚位以待）
func _make_empty_slot() -> Panel:
	var slot := Panel.new()
	slot.custom_minimum_size = Vector2(72, 72)
	slot.add_theme_stylebox_override("panel",
		UI.style(Color(0.06, 0.05, 0.09, 0.45), 18, 2, Color(1.0, 0.85, 0.45, 0.22), 0))
	return slot


# ---------------------------------------------------------------- 选中与交互

func _bind_inputs() -> void:
	_enter.pressed.connect(_on_enter_pressed)
	_back.pressed.connect(_on_back_pressed)
	for node in _find_all(self, "Btn_"):
		(node as Button).pressed.connect(_on_entry_pressed.bind(str(node.name).trim_prefix("Btn_")))


## 关卡节点的选中信号：随子地图重铺而接（节点每次重建，_build_map 末尾调用）
func _bind_nodes() -> void:
	for key in _nodes.keys():
		var btn: Button = _nodes[key]
		btn.pressed.connect(_select_stage.bind(int(key)))


## 选中态：光晕 + 提亮 + 整体轻微放大（对应概念稿里 1003 比另两处更醒目）。
## 放大绕锚点做，所以放大不会让浮岛与背景错位。
func _select_stage(stage_id: int) -> void:
	if not _nodes.has(stage_id):
		return
	_selected = stage_id

	if _glow_tween and _glow_tween.is_valid():
		_glow_tween.kill()
	_glow_tween = null

	for key in _nodes.keys():
		var btn: Button = _nodes[key]
		var on := int(key) == stage_id
		var glow: TextureRect = btn.get_node_or_null("SelectionGlow")
		if glow != null:
			glow.visible = on
			if on:
				_start_glow_pulse(glow)
		btn.modulate = Color.WHITE if on else Color(0.94, 0.95, 1.0)
		_scale_node(btn, SELECTED_SCALE if on else 1.0, 0.18)

	_refresh_enter()


func _scale_node(btn: Button, factor: float, dur: float) -> void:
	# 把目标值记在节点上：选中放大是补间出来的，冒烟测试在补间跑完之前就断言了，
	# 只能读这个目标值，读 scale 会读到中间态。
	btn.set_meta("scale_target", factor)
	# 入场动效开始前不做补间，直接把目标值落到位 ——
	# 否则会和 _play_intro 的缩放补间抢同一个属性，默认选中那个节点会跳一下。
	if not _intro_done:
		btn.scale = Vector2.ONE * factor
		return
	var tw := create_tween()
	tw.tween_property(btn, "scale", Vector2.ONE * factor, dur) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _start_glow_pulse(glow: TextureRect) -> void:
	glow.modulate.a = 1.0
	_glow_tween = create_tween().set_loops()
	_glow_tween.tween_property(glow, "modulate:a", 0.42, 0.7).set_trans(Tween.TRANS_SINE)
	_glow_tween.tween_property(glow, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE)


func _refresh_enter() -> void:
	var cfg: Dictionary = GameDB.stage_node(_selected)
	var btn_cfg: Dictionary = GameDB.enter_button()
	_enter.text = str(btn_cfg.get("text", "进入关卡"))
	_enter_sub.text = str(btn_cfg.get("sub_text", "START LEVEL"))
	# tooltip 里带上历史最佳与体力消耗：结算评星写档后，这里选关前就能看到上回打到几星
	var best := _best_stars_of(_selected)
	var best_txt := "未通关"
	if best > 0:
		best_txt = "%s（%d/%d★）" % [_stars_text(best), best, GameDB.star_max()]
	_enter.tooltip_text = "%s（%s）\n历史最佳：%s  ｜  消耗体力 %d" % [
		str(cfg.get("name", "")), GameDB.stage_kind_name(str(cfg.get("kind", ""))),
		best_txt, GameDB.stage_stamina(_selected)]


func _on_enter_pressed() -> void:
	var cfg: Dictionary = GameDB.stage_node(_selected)
	if cfg.is_empty():
		_show_toast("没有可进入的关卡")
		return
	# 事件 / 休息节点（祭坛、喷泉）不进战场、不耗体力、无需编队：
	# 直接进战斗场景，由 battle.gd 的 _setup_non_battle 渲染选项面板。
	# 节点里「祈祷」下发的增益写在 BattleCtx，离开后仍会带到下一场真正的战斗。
	if not GameDB.stage_is_battle(_selected):
		BattleCtx.begin_from_stage(_selected, "stage_select")
		_show_toast("进入事件 · %s（%s）\n无需上阵 · 不消耗体力" % [
			str(cfg.get("name", "")), GameDB.stage_kind_name(str(cfg.get("kind", "")))])
		if auto_transition:
			_go_event()
		return
	# 体力以关卡自身为准：1001 新手引导关免费、1003 精英 8 点、1008 高难支线 10 点，
	# 只有没写 stamina 的关卡才回落到全局缺省值
	var cost := GameDB.stage_stamina(_selected)

	# 体力在哪一步扣由配置决定（formation.spend_stamina_at）：
	# 默认在编队页「确认选择」时扣 —— 编队是准备界面，玩家还没出发就不该已经被扣。
	if GameDB.spend_stamina_at() == "stage_select":
		if not StaminaSys.spend(cost):
			_show_toast("体力不足：需要 %d 点，当前 %d 点\n（%s 后恢复 1 点）"
				% [cost, StaminaSys.current(), StaminaSys.format_next()])
			return
	elif cost > StaminaSys.current():
		_show_toast("体力不足：需要 %d 点，当前 %d 点\n（%s 后恢复 1 点）"
			% [cost, StaminaSys.current(), StaminaSys.format_next()])
		return

	# 进关只登记「这一场打哪」，不清 buff：祭坛「祈祷」下发的增益要能撑到
	# 下一场真正战斗，故其消费放在 battle.gd 结算处（_show_result），不在这里抹掉。
	BattleCtx.begin_from_stage(_selected, "stage_select")

	# 提示条顺带报一次本关历史最佳：结算评星写档后，这里能直接看到同步结果
	var best := _best_stars_of(_selected)
	_show_toast("进入编队 · 关卡 %d · %s（%s）\n待消耗体力 %d，当前 %d/%d%s" % [
		int(cfg.get("stage_id", 0)), str(cfg.get("name", "")),
		GameDB.stage_kind_name(str(cfg.get("kind", ""))),
		cost, StaminaSys.current(), StaminaSys.maximum(),
		("　历史最佳 %s" % _stars_text(best)) if best > 0 else "",
	])
	if auto_transition:
		_go_formation()


## 编队页才是「出门前的最后一站」：改完阵容点「确认选择」才扣体力并进战斗
func _go_formation() -> void:
	if ResourceLoader.exists(FORMATION_SCENE):
		get_tree().change_scene_to_file(FORMATION_SCENE)
	else:
		_show_toast("编队场景缺失：%s" % FORMATION_SCENE)


## 事件 / 休息节点：不走编队，直接进战斗场景的非战斗分支（battle.gd _setup_non_battle）
func _go_event() -> void:
	if ResourceLoader.exists(BATTLE_SCENE):
		get_tree().change_scene_to_file(BATTLE_SCENE)
	else:
		_show_toast("战斗场景缺失：%s" % BATTLE_SCENE)


func _on_back_pressed() -> void:
	if ResourceLoader.exists(MAIN_MENU_SCENE):
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)
	else:
		_show_toast("主界面场景缺失：%s" % MAIN_MENU_SCENE)


func _on_entry_pressed(id: String) -> void:
	var label := id
	for m in GameDB.mode_entries():
		if str(m.get("id", "")) == id:
			label = "%s（%s）" % [str(m.get("name", id)), str(m.get("tag", ""))]
			break
	for e in GameDB.menu().get("top_right_entries", []):
		if str(e.get("id", "")) == id:
			label = str(e.get("name", id))
			break
	if id == str(GameDB.select_map().get("promo_entry", {}).get("id", "promo")):
		label = str(GameDB.select_map().get("promo_entry", {}).get("name", "活动"))
	_show_toast("%s · 模块待接入" % label)


# ---------------------------------------------------------------- 关卡星数

## 只认存档里的历史最佳：默认（没打过 / 没记录）就是 0 星不画，
## 配置里的 demo_stars 只是空值占位，不再作为地图星数的回落来源
func _stars_of(stage_id: int) -> int:
	return SaveDB.stage_stars(stage_id)


## 只认存档里的历史最佳（不含配置展演值）—— 只有它才够格叫「历史最佳」
func _best_stars_of(stage_id: int) -> int:
	return SaveDB.stage_stars(stage_id)


## 星级文案：0 星返回空串，方便拼提示
func _stars_text(stars: int) -> String:
	return "★".repeat(clampi(stars, 0, GameDB.star_max()))


func _default_stage() -> int:
	var nodes: Array = GameDB.section_nodes(_current_section)
	if nodes.is_empty():
		return 0
	for raw in nodes:
		if bool(raw.get("demo_selected", false)):
			return int(raw.get("stage_id", 0))
	# 停在首个未通关关；全通关则停在末关
	for raw in nodes:
		var sid := int(raw.get("stage_id", 0))
		if SaveDB.stage_clear_count(sid) == 0:
			return sid
	return int((nodes[nodes.size() - 1] as Dictionary).get("stage_id", 0))


# ---------------------------------------------------------------- 体力

func _watch_stamina() -> void:
	StaminaSys.changed.connect(func(_c, _m): _refresh_stamina())
	_clock = Timer.new()
	_clock.wait_time = 1.0
	_clock.autostart = true
	_clock.timeout.connect(_refresh_stamina)
	add_child(_clock)


func _refresh_stamina() -> void:
	_stamina_value.text = "%d/%d" % [StaminaSys.current(), StaminaSys.maximum()]
	if StaminaSys.is_full():
		_stamina_next.text = "已满 · %d点/时" % StaminaSys.regen_per_hour()
	else:
		_stamina_next.text = "%s 后 +1" % StaminaSys.format_next()


# ---------------------------------------------------------------- 动效

func _play_intro() -> void:
	var i := 0
	for raw in GameDB.section_nodes(_current_section):
		var sid := int(raw.get("stage_id", 0))
		if not _nodes.has(sid):
			continue
		var btn: Button = _nodes[sid]
		var target := Vector2.ONE * (SELECTED_SCALE if sid == _selected else 1.0)
		btn.scale = target * 0.86
		btn.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_interval(0.05 * float(i))
		tw.set_parallel(true)
		tw.tween_property(btn, "scale", target, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(btn, "modulate:a", 1.0, 0.26)
		i += 1
	_intro_done = true


# ---------------------------------------------------------------- 反馈与工具

func _refresh_footer() -> void:
	# 底部统计口径与结算面板一致：星级 / 材料都取存档，不做二次计算
	var tally := SaveDB.material_tally()
	_footer.text = "GameDB · SaveDB · RealmDB  |  v%s · %d 关 · 累计 ★%d · 材料 %d 种 %s 件 · 体力 %d/%d" % [
		GameDB.version(),
		GameDB.stage_nodes().size(),
		SaveDB.stat("stars_total"),
		int(tally.get("kinds", 0)), UI.fmt_num(int(tally.get("total", 0))),
		StaminaSys.current(), StaminaSys.maximum(),
	]


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


func _find_all(root: Node, prefix: String) -> Array:
	var out: Array = []
	for c in root.get_children():
		if str(c.name).begins_with(prefix):
			out.append(c)
		out.append_array(_find_all(c, prefix))
	return out
