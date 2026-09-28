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


## 卡牌陈列：用 RealmDB 的展演阵容（等级 / 星级 / 属性都来自存档与配置的合成）
func _build_showcase() -> void:
	var items := RealmDB.showcase_lineup()
	_fan.configure(items, {
		"rarities": GameDB.rarity_table(),
		"elements": GameDB.element_table(),
	}, _card_box(), GameDB.menu().get("fan", {}))


func _build_team() -> void:
	for c in _team_slots.get_children():
		c.queue_free()

	for unit in RealmDB.showcase_team():
		var cfg: Dictionary = unit.get("config", {})
		var rar := GameDB.rarity(str(cfg.get("rarity", "R")))
		var accent := Color(str(rar.get("color", "#FFFFFF")))

		var slot := Panel.new()
		slot.custom_minimum_size = Vector2(56, 56)
		slot.add_theme_stylebox_override("panel",
			UI.style(Color(0.06, 0.05, 0.09, 0.85), 16, 2, accent, 0))
		_team_slots.add_child(slot)

		var pic := UI.picture(str(cfg.get("portrait", "")), TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
		pic.set_anchors_preset(Control.PRESET_FULL_RECT)
		pic.offset_left = 4
		pic.offset_top = 4
		pic.offset_right = -4
		pic.offset_bottom = -4
		slot.add_child(pic)


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
	var s := "v%s · 配置 %d 卡 / %d 品质 / %d 元素 · 存档 %d 卡 · 阵容战力 %d · %s" % [
		GameDB.version(),
		GameDB.characters().size(),
		GameDB.rarities().size(),
		GameDB.elements().size(),
		SaveDB.cards().size(),
		RealmDB.team_power() if not SaveDB.team().is_empty() else _showcase_power(),
		"游戏数据包就绪",
	]
	_footer.text = "GameDB · SaveDB · RealmDB · StaminaSys  |  " + s


func _showcase_power() -> int:
	var total := 0
	for item in RealmDB.showcase_lineup():
		total += int(item.get("power", 0))
	return total


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
	for it in RealmDB.showcase_lineup():
		if it.char_id == char_id:
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
	_show_toast("%s · 模块待接入" % label)


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
