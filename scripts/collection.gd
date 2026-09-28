extends Control
## Collection —— 卡片图鉴（全部卡片：已获取 / 未获取）
##
## 场景骨架由 tools/build_collection.gd 程序化生成；本脚本只做三件事：
##   把 GameDB(全卡目录) + SaveDB(持卡) 接到网格、按筛选重建、点开详情弹层。
##
## 数据流向：GameDB.characters(全部 8 卡) + SaveDB.find_card(是否持有)
##   → _entries()（一张卡一行：owned / card / stats）→ 网格与详情弹层
##
## 未获取的卡：CardView 走 set_locked() 剪影态（立绘压黑、数值隐藏、名牌 ???），
## 网格上再叠一枚锁章；详情弹层仍展示定位与技能文案，数值按展演态预览。

const UI := preload("res://tools/ui_kit.gd")
const CardViewScript := preload("res://scripts/card_view.gd")
const BASE := Vector2(1920, 1080)

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"

## —— 版面常量：与 build_collection.gd 同一口径 ——
## 卡面高度受网格底板（y 134..1002）约束：两行整块 2×高+行距 必须装得下
const CARD_BOX := Vector2(286, 412)
const GRID_COLUMNS := 4
const COL_GAP := 50.0
const ROW_GAP := 40.0
## 网格底板（y 134..1002）的垂直中心，整块卡阵对它居中
const GRID_CENTER_Y := 568.0
const FILTERS := ["all", "owned", "unowned"]
const FILTER_NAMES := { "all": "全部", "owned": "已获取", "unowned": "未获取" }

## 冒烟测试用：置 false 时切场景 / 动画都不执行
var auto_transition := true

var _filter := "all"
var _entries: Array = []
var _shown: Array = []
var _viewing := -1
var _toast_tween: Tween
var _filter_buttons: Dictionary = {}

@onready var _grid: Control = %GridHolder
@onready var _collect_label: Label = %CollectLabel
@onready var _footer_stat: Label = %FooterStat
@onready var _footer: Label = %FooterInfo
@onready var _back_btn: Button = %BackButton
@onready var _toast: Panel = %Toast
@onready var _toast_label: Label = %ToastLabel
@onready var _detail_layer: Control = %DetailLayer
@onready var _detail_backdrop: Control = %DetailBackdrop
@onready var _card_holder: Control = %DetailCardHolder
@onready var _lock_panel: Panel = %DetailLockPanel
@onready var _d_title: Label = %DetailTitle
@onready var _d_tags: Label = %DetailTags
@onready var _d_state: Label = %DetailState
@onready var _d_power: Label = %DetailPower
@onready var _d_stats: Label = %DetailStats
@onready var _d_skills: Label = %DetailSkills
@onready var _d_acquire: Label = %DetailAcquire
@onready var _d_prev: Button = %DetailPrevButton
@onready var _d_next: Button = %DetailNextButton
@onready var _d_close: Button = %DetailCloseButton


func _ready() -> void:
	_entries = _build_entries()
	var top: Control = get_node_or_null("%TopPanel")
	for raw in FILTERS:
		var f := str(raw)
		var btn: Button = top.get_node_or_null("Filt_" + f) if top != null else null
		if btn != null:
			_filter_buttons[f] = btn
			btn.pressed.connect(_on_filter_pressed.bind(f))
	_back_btn.pressed.connect(_on_back)
	_detail_backdrop.gui_input.connect(_on_detail_backdrop)
	_d_close.pressed.connect(_close_detail)
	_d_prev.pressed.connect(_step_detail.bind(-1))
	_d_next.pressed.connect(_step_detail.bind(1))
	_detail_layer.visible = false
	_lock_panel.visible = false
	_apply_filter("all")
	_refresh_footer()


## 存档变化后重拉一遍（抽卡获得新卡回图鉴定时调）
func reload() -> void:
	_entries = _build_entries()
	_apply_filter(_filter)
	_refresh_footer()


# ---------------------------------------------------------------- 数据

## 全卡目录 × 存档持卡 → 一行一张卡。未持有的用配置展演态算一份预览数据，
## 保证与 GachaSys 免费展演卡同一口径（界面结构不用分叉）。
func _build_entries() -> Array:
	var out: Array = []
	for raw in GameDB.characters():
		var cfg: Dictionary = raw
		var char_id := str(cfg.get("id", ""))
		if char_id == "":
			continue
		var owned_card := SaveDB.find_card(char_id)
		var owned := not owned_card.is_empty()
		var card := owned_card if owned else {
			"char_id": char_id,
			"level": int(cfg.get("demo_level", 1)),
			"star": int(cfg.get("demo_star", 1)),
			"exp": 0,
			"equipment": GameDB.blank_equipment(),
		}
		out.append({
			"char_id": char_id, "config": cfg, "card": card,
			"stats": RealmDB.stats_of(card), "owned": owned,
			"rarity": str(cfg.get("rarity", "R")),
		})
	return out


func _owned_count() -> int:
	var n := 0
	for e in _entries:
		if bool(e["owned"]):
			n += 1
	return n


func _filtered() -> Array:
	var out: Array = []
	for e in _entries:
		if _filter == "owned" and not bool(e["owned"]):
			continue
		if _filter == "unowned" and bool(e["owned"]):
			continue
		out.append(e)
	return out


# ---------------------------------------------------------------- 筛选与网格

func _on_filter_pressed(f: String) -> void:
	_apply_filter(f)


## 供冒烟测试直接调用的公开入口
func apply_filter(f: String) -> void:
	_apply_filter(f)


func _apply_filter(f: String) -> void:
	if not FILTERS.has(f):
		f = "all"
	_filter = f
	for key in _filter_buttons.keys():
		var btn: Button = _filter_buttons[key]
		btn.modulate = Color(1.0, 0.87, 0.42) if str(key) == f else Color(0.72, 0.7, 0.78)
	_shown = _filtered()
	_rebuild_grid()
	_refresh_counters()


func _grid_pos(i: int) -> Vector2:
	var row := i / GRID_COLUMNS
	var col := i % GRID_COLUMNS
	var n := _shown.size()
	var rows := int(ceil(float(n) / float(GRID_COLUMNS)))
	var in_row := mini(GRID_COLUMNS, n - row * GRID_COLUMNS)
	var total_w := float(in_row) * (CARD_BOX.x + COL_GAP) - COL_GAP
	# 垂直按「整块」居中：只按单行居中会把两行的块体整体下移，压出底板
	var total_h := float(rows) * (CARD_BOX.y + ROW_GAP) - ROW_GAP
	return Vector2(
		(BASE.x - total_w) * 0.5 + float(col) * (CARD_BOX.x + COL_GAP),
		GRID_CENTER_Y - total_h * 0.5 + float(row) * (CARD_BOX.y + ROW_GAP))


func _rebuild_grid() -> void:
	# queue_free 是帧末才真删：先把旧子节点从树上摘下来，
	# 同一帧内连续重建（测试/快速切筛选）才不会叠加或撞名。
	# 必须先拷快照再遍历：边遍历 get_children() 边 remove_child 会跳节点，
	# 旧格子会永久泄漏在网格上（叠在新卡面上）。
	for c in (_grid.get_children() as Array):
		_grid.remove_child(c)
		c.queue_free()
	# 构建器只留了一个占位，按筛选结果动态补格
	var slots: Array = []
	for i in _shown.size():
		var slot := Control.new()
		slot.name = "CardSlot%d" % i
		slot.custom_minimum_size = CARD_BOX
		slot.size = CARD_BOX
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_grid.add_child(slot)
		slots.append(slot)
	for i in _shown.size():
		var e: Dictionary = _shown[i]
		var slot: Control = slots[i]
		slot.position = _grid_pos(i)
		slot.add_child(_make_grid_card(e))
		if not bool(e["owned"]):
			slot.add_child(_make_lock_badge())


func _make_grid_card(e: Dictionary) -> Control:
	var view: CardView = CardViewScript.new()
	view.name = "Card_%s" % str(e["char_id"])
	view.set_locked(not bool(e["owned"]))
	view.setup({
		"char_id": str(e["char_id"]), "config": e["config"],
		"card": e["card"], "stats": e["stats"],
	}, GameDB.rarity(str(e["rarity"])),
		GameDB.element(str(e["config"].get("element", ""))), CARD_BOX)
	view.card_pressed.connect(_open_detail)
	return view


## 未获取卡面中央的锁章：圆牌 + 锁形。
## 文字「未获得」由 CardView 的等级槽位统一承担，这里只画锁形图标，避免同字重复。
func _make_lock_badge() -> Control:
	var holder := Control.new()
	holder.name = "LockBadge"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.place(holder, (CARD_BOX.x - 120) * 0.5, CARD_BOX.y * 0.34, 120, 110)

	var disc := UI.panel(Color(0.05, 0.04, 0.09, 0.82), 34, 3,
		Color(0.85, 0.82, 0.95, 0.55), 8)
	UI.place(disc, 10, 5, 100, 100)
	holder.add_child(disc)

	# 锁形：整圆环当锁梁，锁体直接盖住下半圈 —— 不用裁剪也能拼出经典锁形
	var shackle := UI.panel(Color(0, 0, 0, 0), 32, 12, Color(0.92, 0.9, 0.98, 0.92), 0)
	UI.place(shackle, 28, 17, 64, 64)
	holder.add_child(shackle)

	var body := UI.panel(Color(0.92, 0.9, 0.98, 0.95), 10, 0, Color.TRANSPARENT, 4)
	UI.place(body, 30, 53, 64, 44)
	holder.add_child(body)

	var keyhole := UI.panel(Color(0.05, 0.04, 0.09, 1.0), 6, 0, Color.TRANSPARENT)
	UI.place(keyhole, 56, 65, 12, 20)
	holder.add_child(keyhole)
	return holder


func _refresh_counters() -> void:
	_collect_label.text = "已收集 %d / %d" % [_owned_count(), _entries.size()]


func _refresh_footer() -> void:
	_footer_stat.text = "图鉴 %d / %d" % [_owned_count(), _entries.size()]
	_footer.text = "GameDB · SaveDB · RealmDB ｜ v%s ｜ 配置 %d 卡 · 持有 %d 卡" % [
		GameDB.version(), _entries.size(), SaveDB.cards().size()]


# ---------------------------------------------------------------- 详情弹层

func open_detail(char_id: String) -> void:
	_open_detail(char_id)


func _open_detail(char_id: String) -> void:
	var idx := -1
	for i in _shown.size():
		if str(_shown[i]["char_id"]) == char_id:
			idx = i
			break
	if idx < 0:
		return
	_viewing = idx
	_fill_detail(_shown[idx])
	_detail_layer.visible = true


func _close_detail() -> void:
	_detail_layer.visible = false
	_viewing = -1
	_clear_card_holder()


## 详情卡面容器同样要即摘即删：同一帧内连续换卡时 child_count 才是真 1
## （同样要先拷快照，边遍历边摘会跳节点）
func _clear_card_holder() -> void:
	for c in (_card_holder.get_children() as Array):
		_card_holder.remove_child(c)
		c.queue_free()


func _step_detail(dir: int) -> void:
	if _shown.is_empty():
		return
	var idx := posmod(_viewing + dir, _shown.size())
	_viewing = idx
	_clear_card_holder()
	_fill_detail(_shown[idx])


func _on_detail_backdrop(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_close_detail()


func _fill_detail(e: Dictionary) -> void:
	var cfg: Dictionary = e["config"]
	var char_id := str(e["char_id"])
	var owned := bool(e["owned"])
	var rarity_id := str(e["rarity"])
	var accent := Color(str(GameDB.rarity(rarity_id).get("color", "#FFFFFF")))

	_clear_card_holder()
	var view: CardView = CardViewScript.new()
	view.name = "DetailCard"
	view.set_locked(not owned)
	view.setup({
		"char_id": char_id, "config": cfg, "card": e["card"], "stats": e["stats"],
	}, GameDB.rarity(rarity_id), GameDB.element(str(cfg.get("element", ""))), CARD_BOX)
	_card_holder.add_child(view)
	_lock_panel.visible = not owned

	_d_title.text = ("??? · " + GameDB.hero_name(char_id)) if not owned \
		else GameDB.full_name(char_id)
	_d_title.add_theme_color_override("font_color", accent.lightened(0.25))

	var elem := GameDB.element(str(cfg.get("element", "")))
	var role_cfg := GameDB.role(str(cfg.get("role", "")))
	var tags := [
		rarity_id + " · " + str(GameDB.rarity(rarity_id).get("name", "")),
		str(elem.get("name", "")),
		str(role_cfg.get("name", "")) + " · " + GameDB.class_name_of(str(cfg.get("role", ""))),
	]
	_d_tags.text = "　".join(tags)
	_d_tags.add_theme_color_override("font_color", accent.lightened(0.4))

	_d_state.text = "已获取 · Lv.%d ★%d" % [int(e["card"].get("level", 1)),
		int(e["card"].get("star", 1))] if owned else "未获取 · 数值为展演态预览"
	_d_state.add_theme_color_override("font_color",
		Color("#FFE9A8") if owned else Color(0.85, 0.85, 0.92, 0.75))
	_d_power.text = "战力 %s" % UI.fmt_num(RealmDB.battle_power(e["stats"]))

	_d_stats.text = _stats_text(e)
	_d_skills.text = _skills_text(cfg)
	_d_acquire.text = "获取途径：群星召唤（召集页卡池 / 招募商店心愿水晶兑换）" \
		if not owned else str(cfg.get("title", ""))
	_d_acquire.add_theme_color_override("font_color",
		Color(1.0, 0.72, 0.72, 0.9) if not owned else Color(0.88, 0.86, 0.95, 0.75))

	_d_prev.disabled = _shown.size() <= 1
	_d_next.disabled = _shown.size() <= 1


func _stats_text(e: Dictionary) -> String:
	var st: Dictionary = e["stats"]
	var lines: Array = []
	var pairs := [
		["生命", UI.fmt_num(int(st.get("hp", 0))), "攻击", UI.fmt_num(int(st.get("atk", 0))), ],
		["防御", UI.fmt_num(int(st.get("def", 0))), "魔抗", UI.fmt_num(int(st.get("mres", 0))), ],
		["速度", UI.fmt_num(int(st.get("spd", 0))), "暴击", "%d%%" % int(round(float(st.get("crit", 0.0)) * 100.0)), ],
	]
	for p in pairs:
		lines.append("%s　%-8s　　%s　%s" % [p[0], p[1], p[2], p[3]])
	return "\n".join(lines)


func _skills_text(cfg: Dictionary) -> String:
	var char_id := str(cfg.get("id", ""))
	var codex: Dictionary = GameDB.codex_of(char_id)
	var battle_role := GameDB.card_battle_role(char_id)
	var parts: Array = ["战斗定位：「%s」" % battle_role]
	var blocks := {
		"普攻": codex.get("attack", {}),
		"绝技": codex.get("ult", {}),
		"被动": codex.get("passive", {}),
	}
	for key in ["普攻", "绝技", "被动"]:
		var block: Dictionary = blocks.get(str(key), {})
		var nm := str(block.get("name", ""))
		var desc := str(block.get("desc", ""))
		if nm == "" and desc == "":
			continue
		parts.append("%s · %s\n%s" % [str(key), nm, desc])
	# 段间空一行：技能描述会折行，挤在一起会溢出信息区
	return "\n\n".join(parts)


# ---------------------------------------------------------------- 返回 / 提示

func _on_back() -> void:
	if auto_transition and ResourceLoader.exists(MAIN_MENU_SCENE):
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _show_toast(text: String) -> void:
	_toast_label.text = text
	_toast.visible = true
	_toast.modulate.a = 0.0
	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.14)
	_toast_tween.tween_interval(2.6)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.35)
	_toast_tween.tween_callback(func(): _toast.visible = false)
