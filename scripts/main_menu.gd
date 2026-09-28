extends Control
## MainMenu —— 主界面
##
## 场景骨架由 tools/build_main_menu.gd 程序化生成；
## 本脚本只做三件事：把数据层的结果接到界面、把交互接起来、做入场动效。
##
## 数据流向：GameDB(配置) + SaveDB(存档) → RealmDB(派生属性) → 界面

const UI := preload("res://tools/ui_kit.gd")
const BASE := Vector2(1920, 1080)
const STAGE_SELECT_SCENE := "res://scenes/stage_select.tscn"

## 冒烟测试要把「入口路由指向哪」验完，但不希望真的切场景（切了后面的断言就断了），
## 于是把切场景这一步做成开关：测试里置 false。与选关页 / 编队页同一套做法。
var auto_transition := true

@onready var _fan: CardFan = %CardFan
@onready var _team_slots: HBoxContainer = %TeamSlots
@onready var _team_power_label: Label = %TeamPowerLabel
@onready var _start: Button = %StartButton
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

var _toast_tween: Tween
var _clock: Timer


func _ready() -> void:
	_bind_player()
	_build_showcase()
	_build_team()
	_bind_inputs()
	_refresh_stamina()
	_watch_stamina()
	_refresh_footer()
	_fan.play_intro()


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


## 卡牌陈列（上方大卡）：与底部「出战阵容」栏共用同一份预览数据，
## 让扇形里的大卡永远等于阵容栏里的那几个英雄（真实编队优先、回落展演队）。
func _build_showcase() -> void:
	var items := _preview_units()
	_fan.configure(items, {
		"rarities": GameDB.rarity_table(),
		"elements": GameDB.element_table(),
	}, _card_box(), _fan_cfg(items.size()))


## 底部阵容预览条：优先显示玩家真实上阵（RealmDB.roster 已含羁绊），
## 存档没编队时回落到当前预设（与编队页同一口径），铺满上阵上限（不足补空槽），并刷新总战力。
func _build_team() -> void:
	# 先 remove_child 再 queue_free：queue_free 延迟到帧尾，同一帧重建时
	# 旧槽仍会在树上，会与新槽叠成双份（从编队页返回后重跑接线的场景）。
	for c in _team_slots.get_children():
		_team_slots.remove_child(c)
		c.queue_free()

	var units := _lineup_units()
	for i in GameDB.team_max():
		if i < units.size():
			_team_slots.add_child(_make_team_slot(units[i]))
		else:
			_team_slots.add_child(_make_empty_slot())
	_refresh_team_power()


## 预览数据源：真实编队优先，空档时回落到当前预设（与编队页共用 SaveDB.resolved_team）。
## 返回的是**未含羁绊的基础 unit**：大卡上显示的三围与编队页扇形
## 卡面同一口径（都取 stats_of 基础值）；羁绊只影响下面的「队伍总战力」读数。
func _lineup_units() -> Array:
	var real: Array = RealmDB.roster_of(SaveDB.resolved_team())
	if not real.is_empty():
		return real
	return RealmDB.showcase_team()


## 队伍总战力：与编队页头部完全同一算法（formation_report 的 total_power，含羁绊）。
## 数据源同 _lineup_units（SaveDB.resolved_team），保证两处读数一致。
func _lineup_power() -> int:
	return int(RealmDB.formation_report(SaveDB.resolved_team()).get("total_power", 0))


## 上方扇形与下方阵容栏共用的预览队：口径同 _lineup_units，最多取上阵上限个
## （与编队页人数口径一致）。这样「大卡」与「小头像」指向的永远是同一批英雄。
func _preview_units() -> Array:
	return _lineup_units().slice(0, GameDB.team_max())


## 按实际卡数（1~上阵上限）现算一组左右对称的扇形排布：卡数随编队变化时扇形仍居中、
## 不歪向一边。4/5 张时额外收紧整体缩放与间距，保证末卡不压到右侧入口栏；
## 1~3 张沿用配置里的整体参数（menu.fan.scale / spacing_x）。
func _fan_cfg(n: int) -> Dictionary:
	var cfg: Dictionary = GameDB.menu().get("fan", {}).duplicate(true)
	var per: Array = []
	match n:
		1:
			per = [_fan_slot(0.0, -10.0, 1.08, 3)]
		2:
			per = [_fan_slot(-4.0, 8.0, 0.99, 1), _fan_slot(4.0, 8.0, 0.99, 2)]
		3:
			per = [
				_fan_slot(-7.0, 26.0, 0.93, 1),
				_fan_slot(0.0, -22.0, 1.05, 3),
				_fan_slot(7.0, 26.0, 0.93, 2),
			]
		4:
			cfg["scale"] = 0.74
			cfg["spacing_x"] = 320.0
			per = [
				_fan_slot(-11.0, 34.0, 0.90, 1),
				_fan_slot(-4.0, -18.0, 1.02, 4),
				_fan_slot(4.0, -18.0, 1.00, 3),
				_fan_slot(11.0, 34.0, 0.90, 2),
			]
		_:
			cfg["scale"] = 0.62
			cfg["spacing_x"] = 300.0
			per = [
				_fan_slot(-14.0, 46.0, 0.86, 1),
				_fan_slot(-7.0, 8.0, 0.96, 3),
				_fan_slot(0.0, -26.0, 1.04, 5),
				_fan_slot(7.0, 8.0, 0.96, 4),
				_fan_slot(14.0, 46.0, 0.86, 2),
			]
	cfg["per_index"] = per
	return cfg


func _fan_slot(rot: float, y: float, sc: float, z: int) -> Dictionary:
	return { "rot_deg": rot, "y": y, "scale": sc, "z": z }


const SLOT_SIZE := 68.0


## 单个上阵槽：品质描边头像 + 底部等级条 + 右上星级角标，tooltip 给全名与战力
func _make_team_slot(unit: Dictionary) -> Control:
	var cfg: Dictionary = unit.get("config", {})
	var card: Dictionary = unit.get("card", {})
	var rar := GameDB.rarity(str(cfg.get("rarity", "R")))
	var accent := Color(str(rar.get("color", "#FFFFFF")))

	var slot := Panel.new()
	slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	slot.add_theme_stylebox_override("panel",
		UI.style(Color(0.06, 0.05, 0.09, 0.9), 14, 2, accent, 0))
	slot.tooltip_text = "%s  ·  战力 %s" % [str(cfg.get("name", "")), UI.fmt_num(int(unit.get("power", 0)))]

	var pic := UI.picture(str(cfg.get("portrait", "")), TextureRect.STRETCH_KEEP_ASPECT_COVERED)
	pic.set_anchors_preset(Control.PRESET_FULL_RECT)
	pic.offset_left = 3
	pic.offset_top = 3
	pic.offset_right = -3
	pic.offset_bottom = -17
	slot.add_child(pic)

	# 底部等级条
	var band := Panel.new()
	UI.place(band, 0, SLOT_SIZE - 18, SLOT_SIZE, 18)
	band.add_theme_stylebox_override("panel", UI.style(Color(0.04, 0.03, 0.07, 0.82), 0))
	slot.add_child(band)
	var lv := UI.label("Lv.%d" % int(card.get("level", 1)), 12, UI.CREAM, 3)
	lv.set_anchors_preset(Control.PRESET_FULL_RECT)
	lv.offset_left = 5
	lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lv.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	band.add_child(lv)

	# 右上星级角标
	var star := clampi(int(card.get("star", 1)), 0, int(rar.get("star_max", 3)))
	if star > 0:
		var st := UI.label("★".repeat(star), 12, Color("#FFD45E"), 3)
		UI.place(st, 0, 2, SLOT_SIZE - 4, 16)
		st.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		slot.add_child(st)
	return slot


## 空槽占位：编队没满上阵上限时补位，保持预览条布局稳定
func _make_empty_slot() -> Control:
	var slot := Panel.new()
	slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	slot.add_theme_stylebox_override("panel",
		UI.style(Color(0.06, 0.05, 0.09, 0.5), 14, 2, Color(1, 1, 1, 0.18), 0))
	var lb := UI.label("空", 16, Color(1, 1, 1, 0.35), 4)
	lb.set_anchors_preset(Control.PRESET_FULL_RECT)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slot.add_child(lb)
	return slot


## 队伍总战力：走 _lineup_power（formation_report 同算法，含羁绊），与编队页头部一致
func _refresh_team_power() -> void:
	if _team_power_label == null:
		return
	_team_power_label.text = "战力 %s" % UI.fmt_num(_lineup_power())


func _bind_inputs() -> void:
	_fan.card_pressed.connect(_on_card_pressed)
	_start.pressed.connect(_on_start_pressed)

	for node in _find_all(self, "Mode_"):
		(node as Button).pressed.connect(_on_mode_pressed.bind(str(node.name).trim_prefix("Mode_")))
	for node in _find_all(self, "Sys_"):
		(node as Button).pressed.connect(_on_system_pressed.bind(str(node.name).trim_prefix("Sys_")))
	for node in _find_all(self, "Btn_"):
		(node as Button).pressed.connect(_on_mode_pressed.bind(str(node.name).trim_prefix("Btn_")))


## 右侧竖栏的「系统入口」：配置里给了 route 就真的切过去，留空才回落到待接入提示。
## 与 modes 的区别就在这一步 —— modes 是占位玩法，system_entries 是已经做好的页面。
func _on_system_pressed(id: String) -> void:
	var label := id
	var route := ""
	for raw in _system_entries():
		var e: Dictionary = raw
		if str(e.get("id", "")) == id:
			label = str(e.get("name", id))
			route = str(e.get("route", ""))
			break
	if route == "":
		_show_toast("%s · 模块待接入" % label)
		return
	if not ResourceLoader.exists(route):
		_show_toast("%s 场景缺失：%s" % [label, route])
		return
	if auto_transition:
		get_tree().change_scene_to_file(route)


func _system_entries() -> Array:
	var v: Variant = GameDB.menu().get("system_entries", [])
	return v if v is Array else []


func _refresh_footer() -> void:
	# 阵容战力与底部栏 / 编队页头部同一算法（_lineup_power，含羁绊），三处读数一致
	var s := "v%s · 配置 %d 卡 / %d 品质 / %d 元素 · 存档 %d 卡 · 阵容战力 %d · %s" % [
		GameDB.version(),
		GameDB.characters().size(),
		GameDB.rarities().size(),
		GameDB.elements().size(),
		SaveDB.cards().size(),
		_lineup_power(),
		"游戏数据包就绪",
	]
	_footer.text = "GameDB · SaveDB · RealmDB · StaminaSys  |  " + s


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


# ---------------------------------------------------------------- 交互

func _on_card_pressed(char_id: String) -> void:
	var item := {}
	# 在「扇形实际陈列的那批」里找，而不是固定的展演队 —— 编队换成别的英雄时，
	# 点卡才能查到对应数据。
	for it in _preview_units():
		if str(it.get("char_id", "")) == char_id:
			item = it
			break
	if item.is_empty():
		return

	var cfg: Dictionary = item.config
	var rar := GameDB.rarity(str(cfg.get("rarity", "R")))
	var elem := GameDB.element(str(cfg.get("element", "")))
	var role := GameDB.role(str(cfg.get("role", "")))
	var skill: Dictionary = cfg.get("skill", {})
	var stats: Dictionary = item.stats

	_show_toast("%s  ·  %s %s  ·  %s\n战力 %s   HP %s   ATK %s   DEF %s\n绝技：%s" % [
		str(cfg.get("name", "")),
		str(rar.get("id", "")), str(elem.get("name", "")),
		str(role.get("name", "")),
		UI.fmt_num(int(item.get("power", 0))),
		UI.fmt_num(int(stats.get("hp", 0))),
		UI.fmt_num(int(stats.get("atk", 0))),
		UI.fmt_num(int(stats.get("def", 0))),
		str(skill.get("name", "—")),
	])


func _on_mode_pressed(id: String) -> void:
	var label := id
	for m in GameDB.mode_entries():
		if str(m.get("id", "")) == id:
			label = "%s（%s）" % [str(m.get("name", id)), str(m.get("tag", ""))]
			break
	match id:
		"settings":
			label = "设置"
		"mail":
			label = "邮件"
		"event":
			label = "活动"
	_show_toast("%s · 模块待接入，敬请期待" % label)


## 「进入冒险」跳转冒险关卡选择页。
## 体力不在这一步扣 —— 要等选关页点「进入关卡」、编队页点「确认选择」才扣。
func _on_start_pressed() -> void:
	if not ResourceLoader.exists(STAGE_SELECT_SCENE):
		_show_toast("关卡选择场景缺失：%s" % STAGE_SELECT_SCENE)
		return
	if auto_transition:
		get_tree().change_scene_to_file(STAGE_SELECT_SCENE)


# ---------------------------------------------------------------- 反馈

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


# ---------------------------------------------------------------- 工具

func _card_box() -> Vector2:
	var box: Dictionary = GameDB.menu().get("card_box", {})
	return Vector2(float(box.get("w", 336)), float(box.get("h", 520)))


func _find_all(root: Node, prefix: String) -> Array:
	var out: Array = []
	for c in root.get_children():
		if str(c.name).begins_with(prefix):
			out.append(c)
		out.append_array(_find_all(c, prefix))
	return out
