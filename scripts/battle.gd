extends Control
## Battle —— 战斗界面
##
## 场景骨架由 tools/build_battle.gd 程序化生成；本脚本负责三件事：
##   1. 把关卡配置「翻译」成画面：环境配色、九宫格落位、敌方阵容、我方队伍；
##   2. 驱动 BattleCore 逐拍推进，把事件播成演出（突进 / 飘字 / 血条 / 倒下）；
##   3. 结算：胜负、奖励入账、首通判定、回选关。
##
## 铁律：**任何数值判断都不在这里做**。伤害、治疗、护盾、眩晕、怒气全部由
## BattleCore 算完给出事件，本脚本只是事件播放器 —— 这样同一场战斗在
## 无头冒烟里跑出的结果，和玩家在屏幕上看到的一定是同一个。

const UI := preload("res://tools/ui_kit.gd")
const CORE := preload("res://scripts/battle_core.gd")

const STAGE_SELECT_SCENE := "res://scenes/stage_select.tscn"
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const ISLE_ICONS := [
	"res://assets/icons/stage_isle_plain.svg",
	"res://assets/icons/stage_isle_castle.svg",
	"res://assets/icons/stage_isle_storm.svg",
]
const STAR_ICON := "res://assets/icons/icon_star.svg"

const SPEEDS := [1.0, 2.0, 3.0]
const SPEED_NAMES := ["1×", "2×", "3×"]
const ACTION_SECONDS := 0.72   ## 1× 速度下每拍的演出时长
const SETTLE_DELAY := 0.7      ## 最后一拍打完到结算面板弹出的间隔

const HP_ALLY := Color("#5BD6A6")
const HP_ENEMY := Color("#FF7A6B")
const SHIELD_COLOR := Color("#7BE0FF")
const ENERGY_COLOR := Color("#FFC94A")

@onready var _bg: Control = $Background
@onready var _cell_layer: Control = $CellLayer
@onready var _unit_layer: Control = $UnitLayer
@onready var _plate_layer: Control = $PlateLayer
@onready var _float_layer: Control = $FloatLayer

@onready var _stage_no: Label = %StageNo
@onready var _stage_name: Label = %StageName
@onready var _stage_kind: Label = %StageKind
@onready var _power_mine: Label = %PowerMine
@onready var _power_rec: Label = %PowerRec

@onready var _team_box: VBoxContainer = %TeamBox
@onready var _info_title: Label = %InfoTitle
@onready var _info_body: Label = %InfoBody
@onready var _log_box: VBoxContainer = %LogBox
@onready var _log_scroll: ScrollContainer = %LogScroll

@onready var _turn_label: Label = %TurnLabel
@onready var _ally_count: Label = %AllyCount
@onready var _enemy_count: Label = %EnemyCount
@onready var _order_layer: HBoxContainer = %OrderLayer
@onready var _env_label: Label = %EnvLabel

@onready var _speed_btn: Button = %SpeedButton
@onready var _pause_btn: Button = %PauseButton
@onready var _skip_btn: Button = %SkipButton
@onready var _retreat_btn: Button = %RetreatButton

@onready var _result: Panel = %ResultPanel
@onready var _result_title: Label = %ResultTitle
@onready var _result_sub: Label = %ResultSub
@onready var _result_box: VBoxContainer = %ResultRewardBox
@onready var _result_retry: Button = %ResultRetry
@onready var _result_close: Button = %ResultClose

@onready var _toast: Panel = %Toast
@onready var _toast_label: Label = %ToastLabel
@onready var _footer: Label = %FooterInfo

var core: RefCounted = null
var stage_id := 0
var stage: Dictionary = {}

var _tokens: Dictionary = {}      ## uid -> {root, sprite, hp_fill, shield_fill, energy_fill, ...}
var _cards: Dictionary = {}       ## uid -> {hp_fill, hp_text, energy_fill, root}
var _log_lines_shown := 0
var _speed_index := 0
var _paused := false
var _timer := 0.0
var _settle_timer := -1.0
var _selected_uid := -1
var _rewards: Array = []
var _grade: Dictionary = {}      ## 本场星级评定（{stars, max, prev, best, hits}）
var _result_open := false
var _toast_tween: Tween
## 非战斗（祭坛 / 事件）节点的选项交互：选一次即锁定，按钮置灰
var _event_done := false
var _event_buttons: Array = []


func _ready() -> void:
	_bind_buttons()
	stage_id = _resolve_stage_id()
	stage = GameDB.chapter_stage(stage_id)

	_build_background()
	_build_cells()
	if not GameDB.stage_is_battle(stage_id):
		_setup_non_battle()
		return

	core = CORE.new()
	core.setup(stage_id, CORE.player_entries(), {
		"atk_bonus": float(BattleCtx.atk_bonus),
		"seed": int(BattleCtx.seed_override),
	})
	_build_units()
	_build_team_cards()
	_refresh_header()
	_refresh_log()
	_refresh_status()
	_refresh_order()
	_restore_mechanic()
	_play_intro()


# ---------------------------------------------------------------- 关卡上下文

func _resolve_stage_id() -> int:
	var sid := int(BattleCtx.stage_id)
	if sid > 0 and not GameDB.chapter_stage(sid).is_empty():
		return sid
	# 直接运行场景（调试 / 冒烟）时给一个合理缺省：章节里第一场真正的战斗
	for raw in GameDB.chapter_stages():
		var s: Dictionary = raw
		if not s.get("enemies", []).is_empty():
			return int(s.get("id", 0))
	return 1001


func _bind_buttons() -> void:
	_speed_btn.pressed.connect(_on_speed)
	_pause_btn.pressed.connect(_on_pause)
	_skip_btn.pressed.connect(_on_skip)
	_retreat_btn.pressed.connect(_on_retreat)
	_result_retry.pressed.connect(_on_retry)
	_result_close.pressed.connect(_on_close_result)
	# 点空白处 = 取消选中，回到关卡机制
	_bg.gui_input.connect(_on_bg_input)


func _on_bg_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_selected_uid = -1
		_highlight(-1)
		_restore_mechanic()


# ---------------------------------------------------------------- 背景

## 有整张背景图就用图；没有就按关卡 theme 铺程序化战场
## （天光渐变 + 太阳辉光 + 云带 + 远景浮岛剪影 + 两块石台）。
## 这样 10 个关卡各有各的色调，等美术图到位后只要填 stage.bg 就能整体替换。
func _build_background() -> void:
	var bg_path := str(stage.get("bg", ""))
	if bg_path != "" and ResourceLoader.exists(bg_path):
		var pic := UI.picture(bg_path, TextureRect.STRETCH_KEEP_ASPECT_COVERED)
		UI.fill(pic)
		_bg.add_child(pic)
		_bg.add_child(_vignette())
		return

	var theme: Dictionary = stage.get("theme", {})
	var sky_top := Color(str(theme.get("sky_top", "#8FB4D8")))
	var sky_bottom := Color(str(theme.get("sky_bottom", "#F2F7FB")))
	var sun := Color(str(theme.get("sun", "#FFF0C0")))
	var ground := Color(str(theme.get("ground", "#9AA3AE")))
	var rim := Color(str(theme.get("rim", "#5E6670")))
	var haze := Color(str(theme.get("haze", "#5A6C86")))

	var sky := UI.gradient_rect(sky_top, sky_bottom)
	sky.name = "Sky"
	UI.fill(sky)
	_bg.add_child(sky)

	# 远景：三座浮岛剪影，压在天际线上做纵深
	var isle_cfg := [
		{"x": 60.0, "y": 30.0, "s": 420.0},
		{"x": 1480.0, "y": 0.0, "s": 500.0},
		{"x": 860.0, "y": -40.0, "s": 380.0},
	]
	for i in isle_cfg.size():
		var c: Dictionary = isle_cfg[i]
		var isle := UI.icon(str(ISLE_ICONS[i % ISLE_ICONS.size()]), float(c.s), haze)
		isle.name = "FarIsle_%d" % i
		isle.modulate.a = 0.34
		UI.place(isle, float(c.x), float(c.y), float(c.s), float(c.s))
		_bg.add_child(isle)

	# 日光：两团大辉光，位置偏右上，给整个战场定光位
	for g in [
		{"x": 1180.0, "y": 20.0, "s": 980.0, "a": 0.42},
		{"x": -180.0, "y": 240.0, "s": 620.0, "a": 0.22},
	]:
		var glow := UI.glow_rect(sun, float(g.a))
		glow.name = "SunGlow"
		UI.place(glow, float(g.x), float(g.y), float(g.s), float(g.s))
		_bg.add_child(glow)

	# 云带：横向拉长的高光椭圆，压在浮岛与战场之间
	for cl in [
		{"x": -120.0, "y": 250.0, "w": 1400.0, "h": 200.0, "a": 0.20},
		{"x": 820.0, "y": 170.0, "w": 1500.0, "h": 190.0, "a": 0.16},
		{"x": -200.0, "y": 640.0, "w": 1700.0, "h": 240.0, "a": 0.13},
	]:
		var cloud := _ellipse_tex(Color(1, 1, 1, float(cl.a)), 0.55, float(cl.w), float(cl.h))
		UI.place(cloud, float(cl.x), float(cl.y), float(cl.w), float(cl.h))
		_bg.add_child(cloud)

	# 一整块石台，而不是两块分开画：两块圆心不同的椭圆叠在一起时，
	# 交界处会露出一条比背景更亮的弧线，看着像地面上凭空多了一道坎。
	var plate_w := 1500.0
	var plate_h := 880.0
	var plate_cx := 880.0
	var plate_cy := 622.0

	var shadow := _ellipse_tex(Color(0, 0, 0, 0.22), 0.74, plate_w + 50.0, plate_h + 40.0)
	UI.place(shadow, plate_cx - (plate_w + 50.0) * 0.5, plate_cy - (plate_h + 40.0) * 0.5 + 18.0,
		plate_w + 50.0, plate_h + 40.0)
	_bg.add_child(shadow)

	var plate := _ellipse_tex(rim, 0.82, plate_w, plate_h)
	UI.place(plate, plate_cx - plate_w * 0.5, plate_cy - plate_h * 0.5, plate_w, plate_h)
	_bg.add_child(plate)

	var top := _ellipse_tex(ground, 0.80, plate_w - 46.0, plate_h - 38.0)
	UI.place(top, plate_cx - (plate_w - 46.0) * 0.5, plate_cy - plate_h * 0.5 + 14.0,
		plate_w - 46.0, plate_h - 38.0)
	_bg.add_child(top)

	_bg.add_child(_vignette())


func _vignette() -> Control:
	var v := ColorRect.new()
	v.color = Color(0.04, 0.03, 0.08, 0.10)
	UI.fill(v)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v


## 椭圆贴片：径向渐变在 0→edge_stop 保持实色、之后渐隐，于是边缘干净不打糊
func _ellipse_tex(color: Color, edge_stop: float, w: float, h: float) -> TextureRect:
	var edge := color
	edge.a = 0.0
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, edge_stop, 1.0])
	g.colors = PackedColorArray([color, color, edge])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 256
	t.height = 256
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	var tr := TextureRect.new()
	tr.texture = t
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.custom_minimum_size = Vector2(w, h)
	tr.size = Vector2(w, h)
	return tr


# ---------------------------------------------------------------- 九宫格

## 空格子：只画一块暗色地面投影，不画边框线 ——
## 2.5D 视角里画方格线会把地面画成一张表格，反而不像战场。
## 两侧 9 格全铺，于是「这一关只上了 3 个人」也能一眼看出来。
func _build_cells() -> void:
	for side in [CORE.SIDE_ENEMY, CORE.SIDE_PLAYER]:
		for slot in range(1, 10):
			var pos: Vector2 = _cell_pos(side, slot)
			var dot := _ellipse_tex(Color(0, 0, 0, 0.20), 0.75, 190.0, 62.0)
			dot.name = "Cell_%s_%d" % [side, slot]
			UI.place(dot, pos.x - 95.0, pos.y - 31.0, 190.0, 62.0)
			_cell_layer.add_child(dot)


## 非战斗节点没有 core，用一次性实例取坐标（cell_pos 只依赖配置，不依赖战斗状态）
func _cell_pos(side: String, slot: int) -> Vector2:
	return core.cell_pos(side, slot) if core != null else CORE.new().cell_pos(side, slot)


# ---------------------------------------------------------------- 单位

func _build_units() -> void:
	# 按脚下的 y 从小到大铺：屏幕位置越靠下的单位越靠近镜头，必须最后画（盖住后排）。
	# 不做这一步的话，「后排萨满的名字」会压在「中排 Boss 的头上」，谁在前谁在后全乱。
	var ordered: Array = core.units.duplicate()
	ordered.sort_custom(func(a, b): return core.unit_pos(a).y < core.unit_pos(b).y)
	for u in ordered:
		var token := _make_token(u)
		_tokens[int(u.uid)] = token
		_unit_layer.add_child(token.root)
		_plate_layer.add_child(token.block)
	_refresh_units()


func _make_token(u: Dictionary) -> Dictionary:
	var pos: Vector2 = core.unit_pos(u)
	var b: Dictionary = GameDB.battle_cfg().get("token", {})
	var w := float(b.get("w", 156))
	var px_h := float(b.get("px_h", 132))
	var block_h := float(b.get("block_h", 42))
	var block_w := float(b.get("block_w", 116))
	var is_ally := str(u.side) == "player"

	var root := Button.new()
	root.name = "Unit_%d" % int(u.uid)
	root.focus_mode = Control.FOCUS_NONE
	root.custom_minimum_size = Vector2(w, px_h + 8.0)
	root.size = root.custom_minimum_size
	root.position = Vector2(pos.x - w * 0.5, pos.y - px_h - 6.0)
	root.add_theme_stylebox_override("normal", UI.style(Color(0, 0, 0, 0), 16))
	root.add_theme_stylebox_override("hover", UI.style(Color(1, 1, 1, 0.07), 16))
	root.add_theme_stylebox_override("pressed", UI.style(Color(1, 1, 1, 0.12), 16))
	root.add_theme_stylebox_override("focus", UI.style(Color(0, 0, 0, 0), 16))
	root.pressed.connect(_on_unit_clicked.bind(int(u.uid)))

	var accent := GameDB.element_color(str(u.element))
	if str(u.element) == "":
		accent = Color("#9EC8FF") if is_ally else Color("#FFAF9E")

	# 脚下光环：己方偏青、敌方偏红，一眼分得清谁是谁的
	var ring := UI.glow_rect(Color("#7BE0FF") if is_ally else Color("#FF8A72"), 0.5)
	ring.name = "Ring"
	UI.place(ring, w * 0.5 - 92.0, px_h - 32.0, 184.0, 66.0)
	root.add_child(ring)

	# 元素色底盘：让「这是什么属性的怪」不用看字就知道
	var base := _ellipse_tex(Color(accent.r, accent.g, accent.b, 0.42), 0.66, 118.0, 42.0)
	UI.place(base, w * 0.5 - 59.0, px_h - 18.0, 118.0, 42.0)
	root.add_child(base)

	var sprite := UI.picture(_portrait_of(u), TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	sprite.name = "Sprite"
	var sprite_h := px_h if is_ally else float(b.get("monster_h", 112))
	var sprite_w := w - 12.0
	# Boss 整体放大一圈：同样是 3×3 里的一格，守关的应该一眼就是最大的那个
	if bool(u.is_boss):
		sprite_h *= 1.22
		sprite_w *= 1.22
	var sprite_x := (w - sprite_w) * 0.5
	var sprite_y := px_h - sprite_h
	UI.place(sprite, sprite_x, sprite_y, sprite_w, sprite_h)
	sprite.pivot_offset = Vector2(sprite_w * 0.5, sprite_h)
	root.add_child(sprite)

	var badge: Control = null
	if bool(u.is_boss):
		# 角标钉在立绘左上角而不是格子顶端：顶端正好落在后排单位的名牌上
		badge = _boss_badge(sprite_x + 2.0, sprite_y - 6.0)
		badge.name = "BossBadge"
		root.add_child(badge)

	# 名牌与血条：挂在**头顶上方**，住在独立图层（原因见配置的 block_layer_note）
	var block := Control.new()
	block.name = "Plate_%d" % int(u.uid)
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.place(block, pos.x - block_w * 0.5, pos.y - sprite_h - 6.0 - block_h, block_w, block_h)

	var name_l := UI.label(str(u.name), 22, UI.CREAM, 6, Color("#2A1F17"))
	name_l.name = "NameLabel"
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UI.place(name_l, -26.0, -2.0, block_w + 52.0, 26.0)
	block.add_child(name_l)

	var bar_w := block_w - 16.0
	var bar_x := 8.0
	var hp_back := UI.panel(Color(0, 0, 0, 0.62), 7, 2, Color(0, 0, 0, 0.5))
	UI.place(hp_back, bar_x, 24.0, bar_w, 13.0)
	block.add_child(hp_back)

	var hp_fill := _fill_bar(block, bar_x + 2.0, 26.0, bar_w - 4.0, 9.0, HP_ALLY if is_ally else HP_ENEMY)
	var shield_fill := _fill_bar(block, bar_x + 2.0, 26.0, bar_w - 4.0, 9.0, SHIELD_COLOR)
	shield_fill.size.x = 0.0
	shield_fill.visible = false

	var energy_fill: Panel = null
	if is_ally:
		var e_back := UI.panel(Color(0, 0, 0, 0.55), 5)
		UI.place(e_back, bar_x, 38.0, bar_w, 7.0)
		block.add_child(e_back)
		energy_fill = _fill_bar(block, bar_x + 1.0, 39.0, bar_w - 2.0, 5.0, ENERGY_COLOR)
		energy_fill.size.x = 0.0

	return {
		"root": root, "block": block, "sprite": sprite, "hp_fill": hp_fill,
		"shield_fill": shield_fill, "energy_fill": energy_fill, "name_label": name_l,
		"ring": ring, "bar_w": bar_w - 4.0, "bar_x": bar_x + 2.0, "is_ally": is_ally,
		"home": root.position, "sprite_home": sprite.position, "anchor": pos,
	}


## 会缩放的条（血条 / 护盾条 / 怒气条）
##
## 必须显式把 custom_minimum_size.x 归零：UI.place 会把给定宽度写进
## custom_minimum_size，而它是**尺寸下限** —— 之后无论怎么改 size.x，
## 条子都会停在满格宽度，掉血时看起来一点没掉。
func _fill_bar(parent: Control, x: float, y: float, w: float, h: float, color: Color) -> Panel:
	var p := UI.panel(color, maxi(3, int(round(h * 0.45))))
	UI.place(p, x, y, w, h)
	p.custom_minimum_size = Vector2(0.0, h)
	parent.add_child(p)
	return p


func _boss_badge(x: float, y: float) -> Control:
	var badge := UI.panel(Color("#D9503F"), 10, 2, Color("#FFE9A8"), 6)
	UI.place(badge, x, y, 92.0, 34.0)
	var l := UI.label("BOSS", 22, UI.CREAM, 5)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UI.fill(l)
	badge.add_child(l)
	return badge


func _portrait_of(u: Dictionary) -> String:
	var p := str(u.portrait)
	if p != "" and ResourceLoader.exists(p):
		return p
	var icon := str(u.icon)
	if icon != "" and ResourceLoader.exists(icon):
		return icon
	return "res://assets/icons/icon_star.svg"


# ---------------------------------------------------------------- 我方队伍卡

func _build_team_cards() -> void:
	for c in _team_box.get_children():
		_team_box.remove_child(c)
		c.queue_free()
	_cards.clear()

	for u in core.team_of(CORE.SIDE_PLAYER):
		var card := _make_team_card(u)
		_cards[int(u.uid)] = card
		_team_box.add_child(card.root)
	_refresh_cards()


func _make_team_card(u: Dictionary) -> Dictionary:
	var rarity := GameDB.rarity(str(u.rarity))
	var accent := Color(str(rarity.get("color", "#FFFFFF")))

	var root := UI.panel(Color(0.09, 0.08, 0.13, 0.86), 16, 3, accent, 8)
	root.custom_minimum_size = Vector2(276, 160)
	root.size = Vector2(276, 160)

	var frame := UI.panel(Color(0.05, 0.04, 0.08, 0.9), 14, 3, accent, 0)
	UI.place(frame, 10, 36, 84, 84)
	root.add_child(frame)

	var pic := UI.picture(_portrait_of(u), TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	UI.place(pic, 14, 40, 76, 76)
	root.add_child(pic)

	var name_l := UI.label(str(u.name), 23, UI.CREAM, 6)
	UI.place(name_l, 102, 8, 166, 30)
	root.add_child(name_l)

	var sub := UI.label("Lv.%d · %s" % [int(u.level), GameDB.element_name(str(u.element))], 18,
		Color(0.88, 0.92, 0.98, 0.78), 5)
	UI.place(sub, 102, 38, 166, 24)
	root.add_child(sub)

	var hp_back := UI.panel(Color(0, 0, 0, 0.6), 7, 2, Color(0, 0, 0, 0.5))
	UI.place(hp_back, 16, 126, 244, 18)
	root.add_child(hp_back)

	var hp_fill := _fill_bar(root, 18, 128, 240, 14, HP_ALLY)

	var hp_text := UI.label("", 16, Color(0.94, 0.97, 1.0, 0.92), 5)
	hp_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UI.place(hp_text, 22, 126, 232, 18)
	root.add_child(hp_text)

	var e_back := UI.panel(Color(0, 0, 0, 0.55), 5)
	UI.place(e_back, 16, 148, 244, 8)
	root.add_child(e_back)

	var e_fill := _fill_bar(root, 17, 149, 242, 6, ENERGY_COLOR)
	e_fill.size.x = 0.0

	var role := GameDB.role(str(u.role))
	var tag := UI.label("%s · 战力 %s" % [str(role.get("name", u.role)),
		UI.fmt_num(core.unit_power(u))], 17, Color("#FFD98A"), 5)
	UI.place(tag, 102, 68, 166, 24)
	root.add_child(tag)

	var skill := UI.label("怒气满释放【%s】" % str(u.ult_name), 16,
		Color(0.86, 0.90, 1.0, 0.72), 5)
	UI.place(skill, 102, 96, 166, 22)
	root.add_child(skill)

	return {"root": root, "hp_fill": hp_fill, "hp_text": hp_text, "energy_fill": e_fill}


# ---------------------------------------------------------------- 刷新

func _refresh_header() -> void:
	_stage_no.text = str(int(stage.get("id", stage_id)))
	_stage_name.text = str(stage.get("name", "关卡"))
	var kind := str(stage.get("kind", "battle"))
	_stage_kind.text = "%s · %s" % [GameDB.stage_kind_name(kind), str(stage.get("subtitle", ""))]
	_power_mine.text = "我方战力 %s" % UI.fmt_num(core.team_power(CORE.SIDE_PLAYER))
	_power_rec.text = "建议战力 %s · 消耗体力 %d 点" % [
		UI.fmt_num(int(stage.get("recommend_power", 0))), GameDB.stage_stamina(stage_id)]
	_footer.text = "GameDB · BattleCore  |  v%s · 第 %d 关 · 种子 %d" % [
		GameDB.version(), int(stage.get("no", 0)), core.rng_seed]
	_env_label.text = _env_text()


func _env_text() -> String:
	var lines: Array = []
	var env: Dictionary = stage.get("env", {})
	if not env.is_empty():
		lines.append("【%s】%s" % [str(env.get("name", "")), str(env.get("desc", ""))])
	if BattleCtx and BattleCtx.atk_bonus > 1.0:
		lines.append("【%s】%s" % [str(BattleCtx.buff_name), str(BattleCtx.buff_desc)])
	return "\n".join(lines)


func _refresh_units() -> void:
	for u in core.units:
		var t: Dictionary = _tokens.get(int(u.uid), {})
		if t.is_empty():
			continue
		var root: Button = t.root
		var ratio := float(u.hp) / maxf(1.0, float(u.max_hp))
		var bar_w := float(t.bar_w)
		var hp_w := maxf(0.0, bar_w * ratio)
		var fill: Panel = t.hp_fill
		fill.size.x = hp_w
		# 护盾条接在剩余血量后面（血 60% + 盾 20% = 占到 80%），
		# 而不是从左侧从头盖一遍 —— 后者会让人误以为血量比实际多
		var shield: Panel = t.shield_fill
		var shield_ratio := float(u.shield) / maxf(1.0, float(u.max_hp))
		var shield_w := minf(bar_w - hp_w, maxf(0.0, bar_w * shield_ratio))
		shield.visible = int(u.shield) > 0 and shield_w > 0.5
		shield.position.x = float(t.bar_x) + hp_w
		shield.size.x = shield_w
		if t.energy_fill != null:
			(t.energy_fill as Panel).size.x = maxf(0.0, bar_w * float(u.energy) / 100.0)
		if not bool(u.alive):
			root.modulate = Color(1, 1, 1, 0.30)
			(t.sprite as TextureRect).modulate = Color(0.4, 0.38, 0.42, 1.0)
			(t.block as Control).modulate = Color(1, 1, 1, 0.45)
			root.disabled = true
		root.set_meta("hp", int(u.hp))


func _refresh_cards() -> void:
	for u in core.units:
		var c: Dictionary = _cards.get(int(u.uid), {})
		if c.is_empty():
			continue
		var ratio := float(u.hp) / maxf(1.0, float(u.max_hp))
		(c.hp_fill as Panel).size.x = maxf(0.0, 240.0 * ratio)
		(c.energy_fill as Panel).size.x = maxf(0.0, 240.0 * float(u.energy) / 100.0)
		(c.hp_text as Label).text = "%s / %s" % [UI.fmt_num(int(u.hp)), UI.fmt_num(int(u.max_hp))]


## 我方单位在场上会随血量变色，队伍卡只跟着血条走就够了
func _refresh_status() -> void:
	_turn_label.text = "第 %d 拍" % core.action_count
	_ally_count.text = "我方 %d/%d" % [core.alive_of(CORE.SIDE_PLAYER).size(),
		core.team_of(CORE.SIDE_PLAYER).size()]
	_enemy_count.text = "敌方 %d/%d" % [core.alive_of(CORE.SIDE_ENEMY).size(),
		core.team_of(CORE.SIDE_ENEMY).size()]


## 行动顺序条：取接下来要动的 6 个单位
func _refresh_order() -> void:
	for c in _order_layer.get_children():
		_order_layer.remove_child(c)
		c.queue_free()
	for u in core.action_order().slice(0, 6):
		var is_ally := str(u.side) == "player"
		var accent := GameDB.element_color(str(u.element))
		if str(u.element) == "":
			accent = Color("#9EC8FF") if is_ally else Color("#FFAF9E")
		var box := Panel.new()
		box.custom_minimum_size = Vector2(62, 62)
		box.add_theme_stylebox_override("panel",
			UI.style(Color(0.08, 0.07, 0.12, 0.9), 14, 3,
				Color("#7BE0FF") if is_ally else Color("#FF8A72"), 0))
		_order_layer.add_child(box)
		var pic := UI.picture(_portrait_of(u), TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
		UI.fill(pic)
		pic.offset_left = 6
		pic.offset_top = 6
		pic.offset_right = -6
		pic.offset_bottom = -6
		box.add_child(pic)
		var tag := UI.panel(accent, 6)
		UI.place(tag, 44, 44, 16, 16)
		box.add_child(tag)


func _refresh_log() -> void:
	var lines: Array = core.log_lines
	while _log_lines_shown < lines.size():
		var l := UI.label(str(lines[_log_lines_shown]), 18, _log_color(str(lines[_log_lines_shown])), 4)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(500, 0)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_log_box.add_child(l)
		_log_lines_shown += 1
	if _log_box.get_child_count() > 0:
		await get_tree().process_frame
		if is_inside_tree():
			_log_scroll.scroll_vertical = int(_log_scroll.get_v_scroll_bar().max_value)


func _log_color(line: String) -> Color:
	if line.begins_with("★"):
		return Color("#FFD45E")
	if line.begins_with("【"):
		return Color("#BFE3FF")
	if line.contains("阵亡"):
		return Color("#FF9E8C")
	if line.contains("被震晕") or line.contains("跳过行动"):
		return Color("#FFE07A")
	if line.begins_with("·"):
		return Color("#CBB8FF")
	return Color(0.90, 0.93, 0.98, 0.86)


# ---------------------------------------------------------------- 逐拍演出

func _process(delta: float) -> void:
	if core == null:
		return
	if _settle_timer >= 0.0:
		_settle_timer -= delta
		if _settle_timer <= 0.0:
			_settle_timer = -1.0
			_show_result()
		return
	if core.finished or _paused or _result_open:
		return
	_timer += delta
	if _timer >= ACTION_SECONDS / SPEEDS[_speed_index]:
		_timer = 0.0
		_do_action()


func _do_action() -> void:
	var evs: Array = core.step()
	_play(evs)
	_refresh_units()
	_refresh_cards()
	_refresh_status()
	_refresh_order()
	_refresh_log()
	if core.finished:
		_pause_btn.text = "已结束"
		_pause_btn.disabled = true
		_skip_btn.disabled = true
		_speed_btn.disabled = true
		_settle_timer = SETTLE_DELAY


## 事件 -> 演出。所有分支只读事件里的字段，不重新算任何数值。
func _play(evs: Array) -> void:
	for raw in evs:
		var e: Dictionary = raw
		match str(e.get("t", "")):
			"action":
				_on_actor_act(e)
			"damage":
				_on_damage(e)
			"heal":
				_float_text(e.dst, "+%d" % int(e.value), Color("#7BE0A8"), 30)
				_flash(e.dst, Color(0.45, 1.0, 0.62, 0.5))
			"shield":
				_float_text(e.dst, "护盾 %d" % int(e.value), SHIELD_COLOR, 26)
				_flash(e.dst, Color(0.5, 0.85, 1.0, 0.45))
			"buff":
				_float_text(e.dst, "攻+%d%%" % int(round(float(e.value) * 100.0)),
					Color("#FFD45E"), 24)
			"stun_apply":
				_float_text(e.unit, "眩晕", Color("#FFE07A"), 28)
			"death":
				_on_death(e.unit)


func _on_actor_act(e: Dictionary) -> void:
	var u: Dictionary = e.unit
	var t: Dictionary = _tokens.get(int(u.uid), {})
	if t.is_empty():
		return
	var root: Button = t.root
	if str(e.get("kind", "")) == "ult":
		_float_text(u, str(e.get("name", "大招")), Color("#FFD45E"), 30)
	_flash(u, Color(1, 1, 1, 0.35))
	# 出手时立绘朝敌方方向前压一小段再回来 —— 比单纯闪烁更能看出「谁在打谁」。
	# 只推立绘、不推整个 token：名牌在另一个图层，跟着动会跟其他单位的名牌错位。
	var dir := -1.0 if str(u.side) == "player" else 1.0
	var sprite: TextureRect = t.sprite
	var home: Vector2 = t.sprite_home
	var tw := create_tween()
	tw.tween_property(sprite, "position", home + Vector2(0.0, dir * 18.0), 0.10) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(sprite, "position", home, 0.16) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _on_damage(e: Dictionary) -> void:
	var dst: Dictionary = e.dst
	var crit := bool(e.get("crit", false))
	var color := Color("#FFE07A") if crit else Color("#FFFFFF")
	if bool(e.get("counter", false)):
		color = Color("#FF9E6B")
	var text := str(int(e.hp_loss)) if int(e.hp_loss) > 0 else "0"
	if int(e.get("shield_absorb", 0)) > 0 and int(e.hp_loss) == 0:
		text = "格挡"
	_float_text(dst, text, color, 42 if crit else 32, crit)
	_flash(dst, Color(1.0, 0.42, 0.36, 0.55))


func _on_death(u: Dictionary) -> void:
	var t: Dictionary = _tokens.get(int(u.uid), {})
	if t.is_empty():
		return
	_float_text(u, "阵亡", Color("#FF9E8C"), 28)
	var sprite: TextureRect = t.sprite
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(sprite, "scale", Vector2(0.82, 0.82), 0.45)
	tw.tween_property(t.block, "modulate:a", 0.4, 0.45)


func _float_text(u: Dictionary, text: String, color: Color, size: int, big: bool = false) -> void:
	var t: Dictionary = _tokens.get(int(u.uid), {})
	if t.is_empty():
		return
	var pos: Vector2 = t.root.position
	var l := UI.label(text, size, color, 7, Color("#2A1F17"))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var w := 220.0
	# 注意用 anchor（脚下锚点）而不是 root.position —— 后者已经减掉了立绘高度，
	# 拿它当基准算出来的飘字会整体向上偏一个立绘高
	var anchor: Vector2 = t.anchor
	var x: float = anchor.x - w * 0.5 + randf_range(-16.0, 16.0)
	# 飘字默认从名牌上方起飞。敌方后排头顶只剩几十像素、再往上就压到顶部信息条了，
	# 这时候改成挂在名牌下方（落在自己的立绘上），既不越界也不会互相糊在一起。
	var plate_top: float = anchor.y - float(t.sprite.size.y) - 6.0 - float(t.block.size.y)
	var y: float = plate_top - 34.0
	if y < 132.0:
		y = plate_top + float(t.block.size.y) + 6.0
	UI.place(l, x, y, w, 44.0)
	_float_layer.add_child(l)

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", y - 54.0, 0.72).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.72).set_delay(0.18)
	if big:
		l.scale = Vector2(0.6, 0.6)
		l.pivot_offset = Vector2(w * 0.5, 22.0)
		tw.tween_property(l, "scale", Vector2(1.0, 1.0), 0.22) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(func(): l.queue_free())


func _flash(u: Dictionary, color: Color) -> void:
	var t: Dictionary = _tokens.get(int(u.uid), {})
	if t.is_empty():
		return
	var root: Button = t.root
	root.modulate = Color(1.0 + color.r * 0.6, 1.0 + color.g * 0.6, 1.0 + color.b * 0.6, 1.0)
	var tw := create_tween()
	tw.tween_property(root, "modulate", Color(1, 1, 1, 1 if bool(u.alive) else 0.30), 0.22)


func _play_intro() -> void:
	# 入场：整块战场从略远的地方推近，同时各单位错峰浮现
	for key in _tokens.keys():
		var t: Dictionary = _tokens[key]
		(t.root as Button).modulate.a = 0.0
	var i := 0
	for u in core.units:
		var t: Dictionary = _tokens.get(int(u.uid), {})
		if t.is_empty():
			continue
		var root: Button = t.root
		var tw := create_tween()
		tw.tween_interval(0.04 * float(i))
		tw.tween_property(root, "modulate:a", 1.0, 0.26)
		i += 1


# ---------------------------------------------------------------- 交互

func _on_speed() -> void:
	_speed_index = (_speed_index + 1) % SPEEDS.size()
	_speed_btn.text = "速度 %s" % SPEED_NAMES[_speed_index]


func _on_pause() -> void:
	_paused = not _paused
	_pause_btn.text = "继续" if _paused else "暂停"


func _on_skip() -> void:
	if core == null or core.finished:
		return
	core.run_all()
	_paused = true
	_pause_btn.text = "已结束"
	_pause_btn.disabled = true
	_skip_btn.disabled = true
	_speed_btn.disabled = true
	_refresh_units()
	_refresh_cards()
	_refresh_status()
	_refresh_order()
	_refresh_log()
	_settle_timer = 0.35


func _on_retreat() -> void:
	_show_toast("已撤退：本场不计胜负，体力不返还")
	core.finished = true
	core.winner = "retreat"
	core.end_reason = "retreat"
	_settle_timer = 0.9


func _on_unit_clicked(uid: int) -> void:
	_selected_uid = uid
	var u: Dictionary = {}
	for x in core.units:
		if int(x.uid) == uid:
			u = x
			break
	if u.is_empty():
		return
	_info_title.text = "%s  Lv.%d" % [str(u.name), int(u.level)]
	var rows: Array = [
		"属性：%s ｜ 定位：%s" % [GameDB.element_name(str(u.element)),
			str(GameDB.role(str(u.role)).get("name", u.role))],
		"生命 %s / %s%s" % [UI.fmt_num(int(u.hp)), UI.fmt_num(int(u.max_hp)),
			("（护盾 %s）" % UI.fmt_num(int(u.shield))) if int(u.shield) > 0 else ""],
		"攻击 %d ｜ 防御 %d ｜ 法抗 %d" % [int(u.atk), int(u.def), int(u.mres)],
		"攻速 %d ｜ 暴击 %d%% ｜ 怒气 %d" % [int(u.spd), int(round(float(u.crit) * 100.0)),
			int(u.energy)],
	]
	var act: Dictionary = u.action
	if not act.is_empty():
		rows.append("行动：%s ×%.2f" % [_target_name(str(act.get("target", ""))),
			float(act.get("mult", 1.0))])
	var skill: Dictionary = u.skill
	var traits: Array = u.traits
	if not skill.is_empty():
		rows.append("技能【%s】：%s" % [str(skill.get("name", "")), str(skill.get("desc", ""))])
	for raw in traits:
		var tr: Dictionary = raw
		rows.append("特性【%s】：%s" % [str(tr.get("name", "")), str(tr.get("desc", ""))])
	if not (u.ult as Dictionary).is_empty():
		rows.append("大招【%s】：怒气满时释放" % str(u.ult.get("name", "")))
	var full := "\n".join(rows)
	_info_body.text = _clip(full, 150)
	var panel := _info_body.get_parent() as Control
	if panel != null:
		panel.tooltip_text = full
	_highlight(uid)


func _highlight(uid: int) -> void:
	for key in _tokens.keys():
		var t: Dictionary = _tokens[key]
		var on := int(key) == uid
		(t.ring as TextureRect).modulate = Color(1, 1, 1, 1) if on else Color(1, 1, 1, 0.55)


func _on_background_clicked() -> void:
	_selected_uid = -1
	_restore_mechanic()


func _restore_mechanic() -> void:
	_info_title.text = "关卡机制"
	# 面板只有 300x180，机制原文放不下 —— 截到刚好一屏并留省略号，
	# 完整文案（含战术要点）挂在 tooltip 上，悬停可读全。
	var mech := str(stage.get("mechanic", "—"))
	var tactics := str(stage.get("tactics", ""))
	_info_body.text = _clip(mech, 108)
	var panel := _info_body.get_parent() as Control
	if panel != null:
		panel.tooltip_text = mech + (("\n战术要点：" + tactics) if tactics != "" else "")


func _clip(text: String, limit: int) -> String:
	return text if text.length() <= limit else text.substr(0, limit - 1) + "…"


func _target_name(t: String) -> String:
	match t.trim_prefix("enemy_"):
		"nearest_front": return "打最前排"
		"middle_row": return "打中排"
		"back_row": return "打后排"
		"lowest_hp_back": return "打后排残血"
		"front_row": return "打前排全体"
		"all_allies": return "全队"
		"lowest_hp_ally": return "奶最残血"
		"self_and_adjacent_front": return "自身与相邻前排"
		_: return t


# ---------------------------------------------------------------- 结算

func _show_result() -> void:
	if _result_open:
		return
	_result_open = true
	# 本场已把祭坛增益吃进伤害公式（core.atk_bonus），结算即消费，不带到下一场。
	BattleCtx.consume_buff()
	var win: bool = str(core.winner) == "player"
	var retreat: bool = str(core.winner) == "retreat"
	_result_title.text = "战斗失败" if (not win and not retreat) else ("撤退" if retreat else "战斗胜利")
	_result_title.add_theme_color_override("font_color",
		Color("#FFE9A8") if win else Color("#FF9E8C"))
	_result_sub.text = "第 %d 拍 · %s ｜ 我方残血 %.0f%% ｜ 敌方残血 %.0f%%" % [
		core.action_count, "全歼" if core.end_reason == "wipe" else
			("超时裁定" if core.end_reason == "timeout" else "主动撤退"),
		core.hp_ratio(CORE.SIDE_PLAYER) * 100.0, core.hp_ratio(CORE.SIDE_ENEMY) * 100.0]

	for c in _result_box.get_children():
		_result_box.remove_child(c)
		c.queue_free()

	if win:
		# 先评星再入账：星级要连同材料一起写进存档，结算面板读的是同一份数据
		_grade = _rate_stars()
		var lv_before := int(SaveDB.player().get("level", 1))
		_rewards = _grant_rewards()
		_sync_progress(_grade, _rewards)
		_add_star_row(_grade)
		_add_reward_line("战利品", Color("#BFE3FF"), 24)
		for raw in _rewards:
			var r: Dictionary = raw
			_add_reward_row(str(r.get("icon", "")), str(r.get("name", "")),
				int(r.get("count", 0)), int(r.get("owned", -1)))
		if _rewards.is_empty():
			_add_reward_line("（本关为重复通关，奖励已领取）", Color(0.86, 0.9, 0.96, 0.7), 20)
		_add_exp_line(lv_before)
		_add_reward_line(_tally_line(), Color(0.80, 0.88, 0.98, 0.86), 19)
	else:
		# 打完就记一场：失败 / 撤退只累计场次，不发奖、不动地图上的星星
		SaveDB.add_stats({"battles": 1})
		_add_reward_line("未获得奖励", Color("#FF9E8C"), 24)
		_add_reward_line("提示：提升等级 / 星级，或先用低难度关卡刷突破石", Color(0.9, 0.92, 0.96, 0.7), 19)

	_result_retry.visible = not retreat
	_result.visible = true
	_result.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_result, "modulate:a", 1.0, 0.22)


func _add_reward_line(text: String, color: Color, size: int) -> void:
	var l := UI.label(text, size, color, 5)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(480, size + 14)
	_result_box.add_child(l)


## owned >= 0 时在名称下方补一行「持有 N」—— 材料统计要能一眼看到累计量
func _add_reward_row(icon_path: String, name: String, count: int, owned: int = -1) -> void:
	var row := Panel.new()
	row.name = "RewardRow"
	row.custom_minimum_size = Vector2(480, 56)
	row.add_theme_stylebox_override("panel",
		UI.style(Color(0.12, 0.10, 0.17, 0.9), 14, 2, Color(1.0, 0.85, 0.45, 0.35), 0))
	_result_box.add_child(row)

	var ic := UI.icon(icon_path, 34.0, Color("#FFE9A8"))
	UI.place(ic, 14, 11, 34, 34)
	row.add_child(ic)

	var l := UI.label(name, 21, UI.CREAM, 5)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UI.place(l, 60, 4, 300, 30)
	row.add_child(l)

	if owned >= 0:
		var own := UI.label("持有 %s" % UI.fmt_num(owned), 16, Color(0.72, 0.84, 0.98, 0.82), 4)
		own.name = "RewardOwned"
		own.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		UI.place(own, 60, 32, 300, 20)
		row.add_child(own)

	var c := UI.label("×%s" % UI.fmt_num(count), 22, Color("#FFD98A"), 5)
	c.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	c.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UI.place(c, 360, 8, 106, 40)
	row.add_child(c)


# ---------------------------------------------------------------- 星级评分

## 星级评定：规则全部来自 GameDB.star_rating()，本函数只做判定，不改口径。
## 只有胜利才走到这里 —— 撤退 / 失败 0 星，存档不会被擦。
func _rate_stars() -> Dictionary:
	var max_stars := GameDB.star_max()
	# core 是 RefCounted，方法返回的是 Variant，这里必须显式标注类型（4.7 的推断规则）
	var hp: float = core.hp_ratio(CORE.SIDE_PLAYER)
	var wiped: bool = core.end_reason == "wipe"
	var stars := 0
	var hits: Array = []
	for raw in GameDB.star_rules():
		var r: Dictionary = raw
		if not _star_rule_hit(r, wiped, hp):
			continue
		stars = maxi(stars, int(r.get("star", 0)))
		var desc := str(r.get("desc", ""))
		if desc != "":
			hits.append(desc)
	return {
		"stars": clampi(stars, 0, max_stars),
		"max": max_stars,
		"hits": hits,
		"hp": hp,
		"wiped": wiped,
	}


## 单条星级规则的判定。新增条件类型时只加分支，配置表不用动结构
func _star_rule_hit(rule: Dictionary, wiped: bool, hp: float) -> bool:
	match str(rule.get("cond", "")):
		"win":
			return true
		"wipe":
			return wiped
		"hp_ratio":
			return hp >= float(rule.get("value", 0.0))
		"max_actions":
			return core.action_count <= int(rule.get("value", 999))
		"no_death":
			return core.alive_of(CORE.SIDE_PLAYER).size() \
				== core.team_of(CORE.SIDE_PLAYER).size()
	return false


## 结算同步：星级写进 progress.stage_stars（只升不降），材料件数与星级进累计统计。
## 选关地图的星星读的就是这份记录，所以「战斗结果 → 地图星数」只有这一条通路。
func _sync_progress(grade: Dictionary, rewards: Array) -> void:
	var stars := int(grade.get("stars", 0))
	var prev := SaveDB.stage_stars(stage_id)
	var is_best := SaveDB.record_stage_stars(stage_id, stars)
	grade["prev"] = prev
	grade["is_best"] = is_best
	grade["best"] = SaveDB.stage_stars(stage_id)

	var materials := 0
	for raw in rewards:
		var r: Dictionary = raw
		if GameDB.currency(str(r.get("id", ""))).is_empty():
			materials += int(r.get("count", 0))
	SaveDB.add_stats({
		"battles": 1,
		"wins": 1,
		"stars_total": stars,
		"materials_total": materials,
	})


func _add_star_row(grade: Dictionary) -> void:
	var stars := int(grade.get("stars", 0))
	var max_stars := int(grade.get("max", 3))
	var row := Panel.new()
	row.name = "StarRatingRow"
	row.custom_minimum_size = Vector2(480, 96)
	row.add_theme_stylebox_override("panel",
		UI.style(Color(0.13, 0.11, 0.19, 0.92), 14, 2, Color(1.0, 0.85, 0.45, 0.45), 0))
	_result_box.add_child(row)

	var size := 36.0
	var gap := 10.0
	var total := size * float(max_stars) + gap * float(max_stars - 1)
	var holder := HBoxContainer.new()
	holder.name = "StarRow"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_theme_constant_override("separation", int(gap))
	UI.place(holder, (480.0 - total) * 0.5, 10.0, total, size + 2.0)
	row.add_child(holder)
	for i in max_stars:
		holder.add_child(UI.icon(STAR_ICON, size,
			Color("#FFD45E") if i < stars else Color(0.30, 0.26, 0.24, 0.9)))

	var line := UI.label(_grade_line(grade), 20, Color("#FFE9A8"), 5)
	line.name = "StarLine"
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UI.place(line, 10, 54, 460, 30)
	row.add_child(line)


## 星级评语：「3★ 刷新最佳 ｜ 通关 · 全歼 · 我方存活率 ≥ 60%」
func _grade_line(grade: Dictionary) -> String:
	var stars := int(grade.get("stars", 0))
	if stars <= 0:
		return GameDB.star_label("unrated", "未评级")
	var state := GameDB.star_label("first", "首次通关")
	if int(grade.get("prev", 0)) > 0:
		state = GameDB.star_label("new_best", "刷新最佳") if bool(grade.get("is_best", false)) \
			else GameDB.star_label("keep_best", "历史最佳")
	var hits: Array = grade.get("hits", [])
	var detail := " · ".join(PackedStringArray(hits))
	return "%d★/%d★  %s%s" % [stars, int(grade.get("max", 3)), state,
		("  ｜  " + detail) if detail != "" else ""]


## 经验/升级行：把本场胜利经验与是否升级直接报出来，
## 与主界面 / 选关页头部读同一份存档，保证「打完即升级」看得见。
func _add_exp_line(lv_before: int) -> void:
	var exp_item := GameDB.player_exp_item()
	var gained := 0
	for raw in _rewards:
		var r: Dictionary = raw
		if str(r.get("id", "")) == exp_item:
			gained += int(r.get("count", 0))
	if gained <= 0:
		return
	var p := SaveDB.player()
	var lv_now := int(p.get("level", 1))
	if lv_now > lv_before:
		_add_reward_line("经验 +%d  ｜  升级！Lv.%d → Lv.%d" % [gained, lv_before, lv_now],
			Color("#FFE9A8"), 22)
	else:
		_add_reward_line("经验 +%d  ｜  Lv.%d（%d/%d）"
			% [gained, lv_now, int(p.get("exp", 0)), int(p.get("exp_max", 800))],
			Color(0.86, 0.9, 0.96, 0.8), 20)


## 结算底部统计行：材料仓累计 + 累计星级 / 通关场次，口径全部走 SaveDB
func _tally_line() -> String:
	var tally := SaveDB.material_tally()
	return "物资统计：材料 %d 种 · 共 %s 件  ｜  累计 ★%d · 通关 %d 场" % [
		int(tally.get("kinds", 0)), UI.fmt_num(int(tally.get("total", 0))),
		SaveDB.stat("stars_total"), SaveDB.stat("wins"),
	]



## 奖励入账：货币走 SaveDB.wallet，材料 / 道具走 SaveDB 的材料仓
## （progress.pending_items）—— 背包系统还没做，但账目已经统一，
## 每行都带回入账后的持有量，结算面板直接显示「持有 N」。
func _grant_rewards() -> Array:
	var progress: Dictionary = SaveDB.progress()
	var clears: Dictionary = SaveDB.stage_clears_table()
	var first := not clears.has(str(stage_id))
	var out: Array = []
	for raw in stage.get("rewards", []):
		var r: Dictionary = raw
		if bool(r.get("first_clear", false)) and not first:
			continue
		var rid := str(r.get("id", ""))
		var cnt := int(r.get("count", 0))
		var owned := 0
		if not GameDB.currency(rid).is_empty():
			SaveDB.add_currency(rid, cnt)
			owned = SaveDB.balance(rid)
		elif rid == GameDB.player_exp_item():
			# 胜利经验不再堆进材料仓，直接入账号经验并触发升级
			var up := SaveDB.add_player_exp(cnt, false)
			owned = int(up.get("exp", 0))
		else:
			owned = SaveDB.add_material(rid, cnt)
		out.append({"id": rid, "name": str(r.get("name", rid)), "count": cnt,
			"icon": str(r.get("icon", "")), "owned": owned})

	clears[str(stage_id)] = int(clears.get(str(stage_id), 0)) + 1
	progress["stage_clears"] = clears
	progress["cleared_stages"] = clears.size()
	SaveDB.save_profile()
	return out


func _on_retry() -> void:
	BattleCtx.atk_bonus = 1.0
	get_tree().reload_current_scene()


func _on_close_result() -> void:
	_leave()


func _leave() -> void:
	if ResourceLoader.exists(STAGE_SELECT_SCENE):
		get_tree().change_scene_to_file(STAGE_SELECT_SCENE)
	elif ResourceLoader.exists(MAIN_MENU_SCENE):
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)


# ---------------------------------------------------------------- 非战斗节点

## 1010 之外还有祭坛 / 喷泉这类节点：不进战场，直接把节点效果讲清楚并发放奖励。
func _setup_non_battle() -> void:
	_stage_no.text = str(int(stage.get("id", stage_id)))
	_stage_name.text = str(stage.get("name", "事件"))
	_stage_kind.text = "%s · %s" % [GameDB.stage_kind_name(str(stage.get("kind", "event"))),
		str(stage.get("subtitle", ""))]
	_power_mine.text = "非战斗节点"
	_power_rec.text = "无需上阵 · 不消耗体力"
	_footer.text = "GameDB  |  v%s · 事件节点" % GameDB.version()

	var options: Array = stage.get("options", [])
	var rows: Array = [str(stage.get("mechanic", ""))]
	for raw in options:
		var o: Dictionary = raw
		rows.append("· %s%s" % [str(o.get("name", "")),
			("（消耗 %s）" % _option_cost_text(o.get("cost", {}))) if not (o.get("cost", {}) as Dictionary).is_empty() else ""])
	_env_label.text = "\n".join(rows)

	_result_title.text = str(stage.get("name", "事件节点"))
	_result_title.add_theme_color_override("font_color", Color("#FFE9A8"))
	_result_sub.text = str(stage.get("mechanic", ""))
	_result_retry.visible = false
	_result_close.text = "返回选关"
	for c in _result_box.get_children():
		_result_box.remove_child(c)
		c.queue_free()

	# 固定掉落（若有）照旧入账一次：已领过的节点再进来只复述，不重复发。
	var rewards: Array = stage.get("rewards", [])
	var first_visit := SaveDB.stage_clear_count(stage_id) == 0
	if first_visit:
		_grant_rewards()
	if not rewards.is_empty():
		_add_reward_line("节点奖励" if first_visit else "节点奖励（已领取）",
			Color("#BFE3FF"), 24)
		for raw in rewards:
			var r: Dictionary = raw
			var rid := str(r.get("id", ""))
			var owned := SaveDB.balance(rid) if not GameDB.currency(rid).is_empty() \
				else SaveDB.material_count(rid)
			_add_reward_row(str(r.get("icon", "")), str(r.get("name", "")),
				int(r.get("count", 0)), owned)
		if not first_visit:
			_add_reward_line("该节点的奖励此前已发放，不再重复计算", Color(0.86, 0.9, 0.96, 0.7), 19)

	# 交互选项：可点击，真实扣费（金币 / 体力）并下发收益（增益 / 道具）。
	if not options.is_empty():
		_add_reward_line("你的选择", Color("#BFE3FF"), 24)
		_event_done = false
		_event_buttons.clear()
		for raw in options:
			_add_event_option_button(raw as Dictionary)
	_result.visible = true


## 单个事件选项按钮：文案带上消耗，点击走 _on_event_option 真实结算
func _add_event_option_button(o: Dictionary) -> void:
	var nm := str(o.get("name", o.get("id", "")))
	var cost: Dictionary = o.get("cost", {})
	var txt := nm if cost.is_empty() else "%s（%s）" % [nm, _option_cost_text(cost)]
	var btn := UI.text_button(txt, 22, Color(0.12, 0.10, 0.18, 0.95), UI.GOLD, UI.CREAM, 14)
	btn.custom_minimum_size = Vector2(480, 52)
	btn.pressed.connect(_on_event_option.bind(o))
	_result_box.add_child(btn)
	_event_buttons.append(btn)


## 消耗文案：货币读经济表名字，体力直接标注
func _option_cost_text(cost: Dictionary) -> String:
	if cost.has("currency"):
		var cid := str(cost.get("currency", ""))
		return "%s ×%s" % [str(GameDB.currency(cid).get("name", cid)), UI.fmt_num(int(cost.get("count", 0)))]
	if cost.has("stamina"):
		return "体力 ×%d" % int(cost.get("stamina", 0))
	return ""


## 事件选项结算：先校验并扣费，失败即回退；成功后发放 buff / 道具并锁定所有选项
func _on_event_option(o: Dictionary) -> void:
	if _event_done:
		return
	if str(o.get("id", "")) == "leave":
		_leave()
		return
	var cost: Dictionary = o.get("cost", {})
	if cost.has("currency"):
		var cid := str(cost.get("currency", ""))
		var need := int(cost.get("count", 0))
		if need > 0 and not SaveDB.spend_currency(cid, need):
			_show_toast("%s不足：需要 %d，当前 %d"
				% [str(GameDB.currency(cid).get("name", cid)), need, SaveDB.balance(cid)])
			return
	if cost.has("stamina"):
		var sn := int(cost.get("stamina", 0))
		if sn > 0 and not StaminaSys.spend(sn):
			_show_toast("体力不足：需要 %d 点，当前 %d 点" % [sn, StaminaSys.current()])
			return
	var grant: Dictionary = o.get("grant", {})
	var buff: Dictionary = grant.get("buff", {})
	var item: Dictionary = grant.get("item", {})
	var gained := false
	if not buff.is_empty():
		BattleCtx.grant_buff(float(buff.get("mult", 1.0)),
			str(buff.get("name", "")), str(buff.get("desc", "")))
		_add_reward_line("已获【%s】：%s" % [str(buff.get("name", "祝福")), str(buff.get("desc", ""))],
			Color("#BFE3FF"), 20)
		gained = true
	if not item.is_empty():
		var iid := str(item.get("id", ""))
		var owned := SaveDB.add_material(iid, int(item.get("count", 1)))
		_add_reward_row(str(item.get("icon", "")), str(item.get("name", iid)),
			int(item.get("count", 1)), owned)
		gained = true
	if gained:
		SaveDB.save_profile()
		_event_done = true
		for b in _event_buttons:
			(b as Button).disabled = true
		_show_toast("选择已生效")


# ---------------------------------------------------------------- Toast

func _show_toast(text: String) -> void:
	_toast_label.text = text
	_toast.visible = true
	_toast.modulate.a = 0.0
	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.14)
	_toast_tween.tween_interval(2.6)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.32)
	_toast_tween.tween_callback(func(): _toast.visible = false)
