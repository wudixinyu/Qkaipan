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

@onready var _node_layer: Control = %NodeLayer
@onready var _guide_layer: Control = %GuideLayer
@onready var _decor_layer: Control = %DecorLayer
@onready var _team_slots: HBoxContainer = %TeamSlots
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
@onready var _avatar: TextureRect = %AvatarTex

var _selected := 0
var _nodes: Dictionary = {}          # stage_id -> Button
var _toast_tween: Tween
var _glow_tween: Tween
var _clock: Timer
var _intro_done := false


func _ready() -> void:
	_bind_player()
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

	var av := str(p.get("avatar", ""))
	if av != "" and ResourceLoader.exists(av):
		_avatar.texture = load(av)

	_gold.text = UI.fmt_num(SaveDB.balance("gold"))
	_gem.text = UI.fmt_num(SaveDB.balance("gem"))


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

	for raw in GameDB.stage_nodes():
		var cfg: Dictionary = raw
		var btn := _make_stage_node(cfg)
		_nodes[int(cfg.get("stage_id", 0))] = btn
		_node_layer.add_child(btn)


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
	for pair in GameDB.stage_links():
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

func _build_team() -> void:
	for c in _team_slots.get_children():
		_team_slots.remove_child(c)
		c.queue_free()

	var by_id := {}
	for item in RealmDB.showcase_lineup():
		by_id[str(item.char_id)] = item

	for raw in GameDB.select_map().get("team_panel", {}).get("lineup", []):
		var unit: Variant = by_id.get(str(raw), null)
		if not (unit is Dictionary):
			continue
		var cfg: Dictionary = unit.get("config", {})
		var rar := GameDB.rarity(str(cfg.get("rarity", "R")))
		var accent := Color(str(rar.get("color", "#FFFFFF")))

		var slot := Panel.new()
		slot.custom_minimum_size = Vector2(72, 72)
		slot.add_theme_stylebox_override("panel",
			UI.style(Color(0.06, 0.05, 0.09, 0.85), 18, 3, accent, 0))
		_team_slots.add_child(slot)

		var pic := UI.picture(str(cfg.get("portrait", "")), TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
		UI.fill(pic)
		pic.offset_left = 5
		pic.offset_top = 5
		pic.offset_right = -5
		pic.offset_bottom = -5
		slot.add_child(pic)


# ---------------------------------------------------------------- 选中与交互

func _bind_inputs() -> void:
	for key in _nodes.keys():
		var btn: Button = _nodes[key]
		btn.pressed.connect(_select_stage.bind(int(key)))
	_enter.pressed.connect(_on_enter_pressed)
	_back.pressed.connect(_on_back_pressed)
	for node in _find_all(self, "Btn_"):
		(node as Button).pressed.connect(_on_entry_pressed.bind(str(node.name).trim_prefix("Btn_")))


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

	BattleCtx.begin_from_stage(_selected, "stage_select")
	BattleCtx.consume_buff()

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

## 优先取存档进度，未记录时回落到配置里的展演值（demo_stars）
func _stars_of(stage_id: int) -> int:
	var best: int = SaveDB.stage_stars(stage_id)
	if best > 0:
		return best
	var cfg: Dictionary = GameDB.stage_node(stage_id)
	return int(cfg.get("demo_stars", 0))


## 只认存档里的历史最佳（不含配置展演值）—— 只有它才够格叫「历史最佳」
func _best_stars_of(stage_id: int) -> int:
	return SaveDB.stage_stars(stage_id)


## 星级文案：0 星返回空串，方便拼提示
func _stars_text(stars: int) -> String:
	return "★".repeat(clampi(stars, 0, GameDB.star_max()))


func _default_stage() -> int:
	for raw in GameDB.stage_nodes():
		var n: Dictionary = raw
		if bool(n.get("demo_selected", false)):
			return int(n.get("stage_id", 0))
	var list: Array = GameDB.stage_nodes()
	if list.is_empty():
		return 0
	var head: Dictionary = list[0]
	return int(head.get("stage_id", 0))


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
	for raw in GameDB.stage_nodes():
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
