extends Control
## Gacha —— 抽卡（群星召唤）界面
##
## 场景骨架由 tools/build_gacha.gd 程序化生成；本脚本只做三件事：
##   把 GachaSys / SaveDB 的结果接到界面、把交互接起来、播召唤演出。
##
## 数据流向：GameDB(配置) + SaveDB(存档) → GachaSys(掷点与结算) → 界面
##
## 演出时序（一个抽卡周期）：
##   点按钮 → 卡包抬起并抖动 → 撕开（上下两半飞散）+ 白闪 + 散射光
##   → 有 SSR/UR 时先起光柱（紫 / 彩虹）并震屏 → 卡牌逐张弹出 → 汇总结算
##   任意时刻可「跳过」，直接落到结果静止态。

const UI := preload("res://tools/ui_kit.gd")
const CardViewScript := preload("res://scripts/card_view.gd")
const BASE := Vector2(1920, 1080)

## 冒烟测试要验「按钮接线 / 卡池切换 / 弹层开关」，但不希望演出把断言拖到几秒后，
## 于是把整段演出做成开关：测试里置 false，点一下立即到静止态。
var animate := true
var auto_transition := true

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"

# —— 版面常量：与 build_gacha.gd 同一口径 ——
const CODEX_CENTER := Vector2(960, 552)
const CODEX_WIDTH := 380.0
const CODEX_HEIGHT := 500.0
const SINGLE_BOX := Vector2(336, 520)
const MULTI_BOX := Vector2(200, 300)
const MULTI_COLUMNS := 5
const ROW_TOP := 180.0
## 行距要给「卡片上沿之外的角标条」留出 30px：太窄角标会压到上一排卡的下缘
const ROW_GAP := 56.0
const CARD_GAP := 26.0
const STAGE_WIDTH := 1920.0
const STAGE_HEIGHT := 1080.0

## 卡面在这个宽度以下就换紧凑版：CardView 的三围条是按内腔分三格的，
## 卡片太小时第三个数值会被卡框切掉（见主界面冒烟测试里那组守卫）。
const FULL_CARD_MIN_WIDTH := 300.0

var _pool_id := ""
var _busy := false
var _reveal_result: Dictionary = {}
var _card_nodes: Array = []
var _skipped := false
var _toast_tween: Tween
var _idle_tween: Tween
var _orbit_tween: Tween
var _tab_buttons: Dictionary = {}

@onready var _avatar: TextureRect = %AvatarTex
@onready var _player_name: Label = %PlayerName
@onready var _player_level: Label = %PlayerLevel
@onready var _gem: Label = %GemLabel
@onready var _gold: Label = %GoldLabel
@onready var _bound_gem: Label = %BoundGemLabel
@onready var _crystal: Label = %CrystalLabel
@onready var _ticket_basic: Label = %TicketBasicLabel
@onready var _ticket_advanced: Label = %TicketAdvancedLabel
@onready var _tabs: HBoxContainer = %PoolTabs
@onready var _pool_name: Label = %PoolName
@onready var _pool_desc: Label = %PoolDesc
@onready var _pity_small: Label = %PitySmall
@onready var _pity_large: Label = %PityLarge
@onready var _pity_small_bar: ProgressBar = %PitySmallBar
@onready var _pity_large_bar: ProgressBar = %PityLargeBar
@onready var _pity_badge: Panel = %PityBadge
@onready var _pity_small_half: Panel = %PitySmallHalf
@onready var _pity_large_half: Panel = %PityLargeHalf
@onready var _world: Control = %World
@onready var _codex: Control = %MagicCodex
@onready var _codex_top: Panel = %CodexTop
@onready var _codex_bottom: Panel = %CodexBottom
@onready var _codex_tag: Label = %CodexTag
@onready var _codex_pool_name: Label = %CodexPoolName
@onready var _codex_hint: Label = %CodexHint
@onready var _orbit: Control = %OrbitRing
@onready var _one_btn: Button = %PullOneButton
@onready var _ten_btn: Button = %PullTenButton
@onready var _one_cost: Label = %PullOneCost
@onready var _ten_cost: Label = %PullTenCost
@onready var _rate_btn: Button = %RateButton
@onready var _shop_btn: Button = %ShopButton
@onready var _shop_crystal: Label = %ShopCrystalLabel
@onready var _rule_body: Label = %RuleBody
@onready var _recent_row: HBoxContainer = %RecentRow
@onready var _recent_empty: Label = %RecentEmpty
@onready var _back_btn: Button = %BackButton
@onready var _footer: Label = %FooterInfo
@onready var _footer_stat: Label = %FooterStat
@onready var _toast: Panel = %Toast
@onready var _toast_label: Label = %ToastLabel
@onready var _flash: ColorRect = %FlashRect
@onready var _reveal: Control = %RevealLayer
@onready var _reveal_backdrop: ColorRect = %RevealBackdrop
@onready var _pillar: Control = %LightPillar
@onready var _pillar_base: TextureRect = %PillarBase
@onready var _reveal_cards: Control = %RevealCards
@onready var _reveal_title: Control = %RevealTitle
@onready var _reveal_sub: Label = %RevealSub
@onready var _reveal_summary: Label = %RevealSummary
@onready var _reveal_skip: Button = %RevealSkipButton
@onready var _reveal_again: Button = %RevealAgainButton
@onready var _reveal_close: Button = %RevealCloseButton
@onready var _rate_panel: Panel = %RatePanel
@onready var _rate_body: VBoxContainer = %RateBody
@onready var _rate_pool_name: Label = %RatePoolName
@onready var _rate_close: Button = %RateCloseButton
@onready var _shop_panel: Panel = %ShopPanel
@onready var _shop_body: VBoxContainer = %ShopBody
@onready var _shop_balance: Label = %ShopBalanceLabel
@onready var _shop_close: Button = %ShopCloseButton


func _ready() -> void:
	var ids := GachaSys.pool_ids()
	_pool_id = str(ids[0]) if not ids.is_empty() else ""
	_bind_player()
	_build_tabs()
	_bind_inputs()
	_select_pool(_pool_id, true)
	_refresh_all()
	_play_idle()


# ---------------------------------------------------------------- 配置快捷取

func _gacha() -> Dictionary:
	return GameDB.gacha()


func _card_box() -> Vector2:
	var v: Variant = GameDB.menu().get("card_box", {})
	var box: Dictionary = v if v is Dictionary else {}
	return Vector2(float(box.get("w", 336)), float(box.get("h", 520)))


func _pool() -> Dictionary:
	return GachaSys.pool(_pool_id)


# ---------------------------------------------------------------- 数据接线

func _bind_player() -> void:
	var p: Dictionary = SaveDB.profile.get("player", {})
	_player_name.text = str(p.get("name", "云上旅人"))
	_player_level.text = "Lv.%d" % int(p.get("level", 1))
	var av := str(p.get("avatar", ""))
	if av != "" and ResourceLoader.exists(av):
		_avatar.texture = load(av)


## 卡池标签：配置里几个池就几个按钮，点哪个切哪个
func _build_tabs() -> void:
	for c in _tabs.get_children():
		c.queue_free()
	_tab_buttons.clear()
	for raw in GachaSys.pools():
		var cfg: Dictionary = raw
		var pid := str(cfg.get("id", ""))
		var accent := Color(str(cfg.get("accent", "#FFC94A")))
		var btn := UI.text_button(str(cfg.get("name", pid)), 21,
			Color(0.10, 0.08, 0.14, 0.80), Color(accent.r, accent.g, accent.b, 0.45),
			UI.CREAM, 16)
		btn.name = "Tab_%s" % pid
		btn.custom_minimum_size = Vector2(172, 46)
		btn.size = Vector2(172, 46)
		btn.tooltip_text = str(cfg.get("subtitle", ""))
		_tabs.add_child(btn)
		_tab_buttons[pid] = btn
		btn.pressed.connect(_on_tab_pressed.bind(pid))


func _bind_inputs() -> void:
	_one_btn.pressed.connect(_on_pull.bind(1))
	_ten_btn.pressed.connect(_on_pull.bind(10))
	_rate_btn.pressed.connect(_toggle_rate_panel.bind(true))
	_rate_close.pressed.connect(_toggle_rate_panel.bind(false))
	_shop_btn.pressed.connect(_toggle_shop_panel.bind(true))
	_shop_close.pressed.connect(_toggle_shop_panel.bind(false))
	_reveal_skip.pressed.connect(_skip_reveal)
	_reveal_again.pressed.connect(_on_reveal_again)
	_reveal_close.pressed.connect(_close_reveal)
	_back_btn.pressed.connect(_on_back)


# ---------------------------------------------------------------- 卡池切换

func _on_tab_pressed(pool_id: String) -> void:
	if _busy or pool_id == _pool_id:
		return
	_select_pool(pool_id, false)


func _select_pool(pool_id: String, initial: bool) -> void:
	_pool_id = pool_id
	for pid in _tab_buttons.keys():
		var btn: Button = _tab_buttons[pid]
		var on := str(pid) == pool_id
		var accent := Color(str(GachaSys.pool(str(pid)).get("accent", "#FFC94A")))
		btn.add_theme_stylebox_override("normal", UI.style(
			Color(0.16, 0.13, 0.22, 0.92) if on else Color(0.10, 0.08, 0.14, 0.80),
			16, 3 if on else 2,
			Color(accent.r, accent.g, accent.b, 0.95 if on else 0.35), 10))
	_refresh_pool_texts()
	_refresh_pity()
	_refresh_cost()
	_refresh_rate_panel()
	_refresh_shop_panel()
	_refresh_rule_panel()
	if not initial:
		_pulse_codex()


func _refresh_pool_texts() -> void:
	var cfg := _pool()
	_pool_name.text = str(cfg.get("name", ""))
	_pool_desc.text = str(cfg.get("desc", ""))
	_codex_pool_name.text = str(cfg.get("name", ""))
	_codex_tag.text = str(cfg.get("tag", ""))
	var accent := Color(str(cfg.get("accent", "#C08BFF")))
	_codex_tag.add_theme_color_override("font_color", accent.lightened(0.35))
	_codex_pool_name.add_theme_color_override("font_color", accent.lightened(0.45))
	_refresh_codex_hint()


## 卡包下半张上的小字：UP 名单 / 保底口径
func _refresh_codex_hint() -> void:
	var parts: Array = []
	var ups := _up_names()
	if not ups.is_empty():
		parts.append("当期 UP：" + "、".join(ups))
	else:
		parts.append("常驻全英雄 · 无当期 UP")
	var pity := GameDB.gacha_pity(_pool_id)
	if bool(pity.get("small_on", false)):
		parts.append("小保底 %d 抽必出 SSR+" % int(pity.get("small_count", 50)))
	if bool(pity.get("large_on", false)):
		parts.append("大保底 %d 抽必出当期 UP" % int(pity.get("large_count", 100)))
	_codex_hint.text = "\n".join(parts)


func _up_names() -> Array:
	var out: Array = []
	for raw in GameDB.gacha_up(_pool_id):
		var cfg := GameDB.character(str(raw))
		if not cfg.is_empty():
			out.append(str(cfg.get("name", raw)))
	return out


# ---------------------------------------------------------------- 刷新

func _refresh_all() -> void:
	_refresh_currency()
	_refresh_pity()
	_refresh_cost()
	_refresh_recent()
	_refresh_rule_panel()
	_refresh_rate_panel()
	_refresh_shop_panel()
	_refresh_footer()


func _refresh_currency() -> void:
	_gem.text = UI.fmt_num(SaveDB.balance("gem"))
	_gold.text = UI.fmt_num(SaveDB.balance("gold"))
	_bound_gem.text = UI.fmt_num(SaveDB.balance("bound_gem"))
	_crystal.text = UI.fmt_num(SaveDB.balance(GachaSys.crystal_currency()))
	_ticket_basic.text = UI.fmt_num(SaveDB.material_count("ticket_basic"))
	_ticket_advanced.text = UI.fmt_num(SaveDB.material_count("ticket_advanced"))
	_shop_crystal.text = "%s  %s" % [
		str(GameDB.gacha_crystal().get("name", "心愿水晶")),
		UI.fmt_num(SaveDB.balance(GachaSys.crystal_currency())),
	]


func _refresh_pity() -> void:
	var st := GachaSys.pity_state(_pool_id)
	var small_on := bool(st.get("small_on", false))
	var large_on := bool(st.get("large_on", false))
	_pity_small_bar.max_value = float(st.get("small_max", 50))
	_pity_small_bar.value = float(st.get("small", 0))
	_pity_large_bar.max_value = float(st.get("large_max", 100))
	_pity_large_bar.value = float(st.get("large", 0))
	_pity_small.visible = small_on
	_pity_small_half.visible = small_on
	_pity_large.visible = large_on
	_pity_large_half.visible = large_on
	_pity_badge.visible = small_on or large_on

	# 只有一条保底时（常驻池没有大保底）让剩下那条占满整条，别留半格空白
	var full_w := _pity_badge.custom_minimum_size.x - 16.0
	var half_w := full_w * 0.5 - 8.0
	if small_on and not large_on:
		UI.place(_pity_small_half, 8, 6, full_w, _pity_badge.custom_minimum_size.y - 12.0)
		UI.place(_pity_small, 12, 2, full_w - 24.0, 24)
		UI.place(_pity_small_bar, 12, 28, full_w - 24.0, 10)
	elif large_on and not small_on:
		UI.place(_pity_large_half, 8, 6, full_w, _pity_badge.custom_minimum_size.y - 12.0)
		UI.place(_pity_large, 12, 2, full_w - 24.0, 24)
		UI.place(_pity_large_bar, 12, 28, full_w - 24.0, 10)
	else:
		UI.place(_pity_small_half, 8, 6, half_w, _pity_badge.custom_minimum_size.y - 12.0)
		UI.place(_pity_small, 12, 2, half_w - 24.0, 24)
		UI.place(_pity_small_bar, 12, 28, half_w - 24.0, 10)
		UI.place(_pity_large_half, 8 + full_w * 0.5, 6, half_w, _pity_badge.custom_minimum_size.y - 12.0)
		UI.place(_pity_large, 12 + full_w * 0.5, 2, half_w - 24.0, 24)
		UI.place(_pity_large_bar, 12 + full_w * 0.5, 28, half_w - 24.0, 10)

	if small_on:
		_pity_small.text = "小保底  %d / %d  ·  还差 %d 抽必出 %s" % [
			int(st.get("small", 0)), int(st.get("small_max", 50)),
			int(st.get("small_left", 0)), str(st.get("small_guarantee", "SSR"))]
	if large_on:
		var up_name := ""
		var up_id := GachaSys.up_hero(_pool_id)
		if up_id != "":
			up_name = str(GameDB.character(up_id).get("name", up_id))
		_pity_large.text = "大保底  %d / %d  ·  还差 %d 抽必出 %s" % [
			int(st.get("large", 0)), int(st.get("large_max", 100)),
			int(st.get("large_left", 0)), up_name if up_name != "" else "UP"]


## 按钮：花得起才亮，文案里写清这次会用哪种支付方式
func _refresh_cost() -> void:
	for pair in [[1, _one_btn, _one_cost], [10, _ten_btn, _ten_cost]]:
		var count := int(pair[0])
		var btn: Button = pair[1]
		var label: Label = pair[2]
		var c := GachaSys.cost(_pool_id, count)
		var chosen: Dictionary = c.get("option", {})
		btn.disabled = not bool(c.get("affordable", false))
		btn.modulate = Color.WHITE if not btn.disabled else Color(1, 1, 1, 0.72)
		label.text = _cost_text(c)
		if btn.disabled:
			label.add_theme_color_override("font_color", Color(1, 0.72, 0.72, 0.92))
		else:
			label.add_theme_color_override("font_color",
				Color(str(chosen.get("color", "#FFFFFF"))).lightened(0.2))


func _cost_text(c: Dictionary) -> String:
	var options: Array = c.get("options", [])
	if options.is_empty():
		return "—"
	var parts: Array = []
	for raw in options:
		var row: Dictionary = raw
		parts.append("%s ×%d" % [str(row.get("name", row.get("id", ""))), int(row.get("amount", 0))])
	return "　/　".join(parts)


func _refresh_recent() -> void:
	for c in _recent_row.get_children():
		c.queue_free()
	var items := GachaSys.recent_heroes(4)
	_recent_empty.visible = items.is_empty()
	# 4 张缩略图要塞进 412 宽的条里：单张 92 + 间距 10 = 398，留一点余量
	var box := Vector2(92, 128)
	for raw in items:
		var e: Dictionary = raw
		var item := _hero_item(str(e.get("char_id", "")))
		if item.is_empty():
			continue
		var cfg: Dictionary = item.get("config", {})
		var accent := Color(str(GameDB.rarity(str(e.get("rarity", "R"))).get("color", "#8D6E63")))
		var holder := Control.new()
		holder.custom_minimum_size = box
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_recent_row.add_child(holder)

		var glow := UI.glow_rect(accent, 0.35)
		UI.place(glow, -10, -14, box.x + 20, box.y + 28)
		holder.add_child(glow)

		var frame := UI.panel(Color(0.06, 0.05, 0.09, 0.9), 14, 2, accent, 6)
		UI.place(frame, 0, 0, box.x, box.y - 24)
		holder.add_child(frame)

		_fill_portrait(holder, cfg, Rect2(4, 4, box.x - 8, box.y - 32))

		var tag := UI.label(str(e.get("rarity", "R")), 15, Color.WHITE, 5, Color(0, 0, 0, 0.8))
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		UI.place(tag, 4, 4, box.x - 8, 20)
		holder.add_child(tag)

		var nm := UI.label(str(cfg.get("name", "")), 15, UI.CREAM, 5)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UI.place(nm, 0, box.y - 24, box.x, 24)
		holder.add_child(nm)


func _hero_item(char_id: String) -> Dictionary:
	var cfg := GameDB.character(char_id)
	if cfg.is_empty():
		return {}
	return { "char_id": char_id, "config": cfg }


func _refresh_rule_panel() -> void:
	var pity := GameDB.gacha_pity(_pool_id)
	var crystal := GameDB.gacha_crystal()
	var lines: Array = []
	var ups := _up_names()
	lines.append("【UP】%s" % ("、".join(ups) if not ups.is_empty() else "本池无当期 UP"))
	lines.append("【UP 规则】%s" % str(_pool().get("up_note", "—")))
	lines.append("【小保底】%s" % str(pity.get("small_desc", "—")))
	if bool(pity.get("large_on", false)):
		lines.append("【大保底】%s" % str(pity.get("large_desc", "—")))
		lines.append("【继承】限时池累计抽数跨期全额继承至下一次同类型限时卡池。")
	lines.append("【水晶】%s" % str(crystal.get("desc", "")))
	_rule_body.text = "\n".join(lines)


func _refresh_footer() -> void:
	_footer.text = "GameDB · SaveDB · RealmDB · GachaSys  |  v%s · %d 个卡池 · 本期累计 %d 抽 · %s" % [
		GameDB.version(), GachaSys.pools().size(), SaveDB.total_pulls(),
		str(_pool().get("subtitle", "")),
	]
	_footer_stat.text = "总抽数 %s · 心愿水晶 %s" % [
		UI.fmt_num(SaveDB.total_pulls()),
		UI.fmt_num(SaveDB.balance(GachaSys.crystal_currency())),
	]


# ---------------------------------------------------------------- 概率公示

func _refresh_rate_panel() -> void:
	for c in _rate_body.get_children():
		c.queue_free()
	_rate_pool_name.text = str(_pool().get("name", ""))

	for raw in GachaSys.rate_rows(_pool_id):
		var row: Dictionary = raw
		var accent := Color(str(row.get("color", "#FFFFFF")))
		var box := Panel.new()
		box.custom_minimum_size = Vector2(0, 66)
		box.add_theme_stylebox_override("panel",
			UI.style(Color(0.10, 0.08, 0.15, 0.72), 14, 1, Color(accent.r, accent.g, accent.b, 0.45)))
		_rate_body.add_child(box)

		var bar := ColorRect.new()
		bar.color = accent
		UI.place(bar, 10, 12, 6, 42)
		box.add_child(bar)

		var nm := UI.label("%s · %s" % [str(row.get("rarity", "")), str(row.get("name", ""))],
			22, accent.lightened(0.3), 5)
		UI.place(nm, 28, 8, 280, 30)
		box.add_child(nm)

		var up := UI.label("UP" if bool(row.get("up", false)) else "", 16, Color("#FF9E6B"), 5)
		UI.place(up, 250, 12, 60, 24)
		box.add_child(up)

		var pct := UI.label("%.2f%%" % float(row.get("percent", 0.0)), 26, UI.CREAM, 6)
		pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		UI.place(pct, 900, 6, 140, 34)
		box.add_child(pct)

		var contents: Array = row.get("contents", [])
		var cl := UI.label("可出：%s" % "、".join(contents), 17, Color(0.9, 0.92, 0.98, 0.75), 4)
		cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UI.place(cl, 28, 36, 1010, 24)
		box.add_child(cl)

	var sep := UI.label("", 6)
	sep.custom_minimum_size = Vector2(0, 6)
	_rate_body.add_child(sep)

	var ten := GameDB.gacha_ten_guarantee()
	var ten_box := UI.panel(Color(0.14, 0.10, 0.06, 0.8), 14, 1, Color(1.0, 0.85, 0.45, 0.4))
	ten_box.custom_minimum_size = Vector2(0, 60)
	_rate_body.add_child(ten_box)
	var ten_label := UI.label("【十连】%s　%s" % [str(ten.get("label", "")), str(ten.get("desc", ""))],
		19, Color("#FFD98A"), 4)
	ten_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UI.place(ten_label, 14, 10, 1010, 44)
	ten_box.add_child(ten_label)

	for raw in GameDB.gacha_rate_notice():
		var line := UI.label("· " + str(raw), 18, Color(0.88, 0.90, 0.96, 0.8), 4)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size = Vector2(0, 26)
		_rate_body.add_child(line)


func _toggle_rate_panel(on: bool) -> void:
	_rate_panel.visible = on
	if on:
		_refresh_rate_panel()
		_rate_panel.modulate.a = 0.0
		create_tween().tween_property(_rate_panel, "modulate:a", 1.0, 0.14)
		_shop_panel.visible = false


# ---------------------------------------------------------------- 水晶商店

func _refresh_shop_panel() -> void:
	for c in _shop_body.get_children():
		c.queue_free()
	var crystal := GameDB.gacha_crystal()
	var cur := GachaSys.crystal_currency()
	_shop_balance.text = "%s  %s" % [str(crystal.get("name", "心愿水晶")),
		UI.fmt_num(SaveDB.balance(cur))]

	var options := GachaSys.exchange_options(_pool_id)
	if options.is_empty():
		var l := UI.label(str(GameDB.gacha_shop().get("empty_text", "当前卡池没有可兑换的 UP 英雄")),
			20, Color(1, 1, 1, 0.7), 4)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.custom_minimum_size = Vector2(0, 60)
		_shop_body.add_child(l)
		return

	for raw in options:
		var row: Dictionary = raw
		var cfg: Dictionary = row.get("config", {})
		var rarity := str(row.get("rarity", "R"))
		var rc := GameDB.rarity(rarity)
		var accent := Color(str(rc.get("color", "#FFFFFF")))

		var box := Panel.new()
		box.custom_minimum_size = Vector2(0, 116)
		box.add_theme_stylebox_override("panel",
			UI.style(Color(0.10, 0.08, 0.15, 0.75), 16, 1, Color(accent.r, accent.g, accent.b, 0.5)))
		_shop_body.add_child(box)

		var frame := UI.panel(Color(0.06, 0.05, 0.09, 0.9), 12, 2, accent, 6)
		UI.place(frame, 12, 12, 92, 92)
		box.add_child(frame)
		var pic := UI.picture(str(cfg.get("portrait", "")), TextureRect.STRETCH_KEEP_ASPECT_COVERED)
		UI.place(pic, 17, 17, 82, 82)
		box.add_child(pic)

		var nm := UI.label(str(row.get("name", "")), 26, UI.CREAM, 6)
		UI.place(nm, 120, 16, 300, 34)
		box.add_child(nm)

		var tag := UI.label("%s%s" % [rarity, "  ·  当期 UP" if bool(row.get("up", false)) else ""],
			18, accent.lightened(0.3), 5)
		UI.place(tag, 120, 52, 300, 26)
		box.add_child(tag)

		var state := UI.label("未持有 · 兑换即得新卡" if bool(row.get("is_new", true)) else "已持有 · 兑换即升星",
			17, Color(0.9, 0.92, 0.98, 0.7), 4)
		UI.place(state, 120, 80, 340, 24)
		box.add_child(state)

		var cost := int(row.get("cost", 0))
		var afford := bool(row.get("affordable", false))
		var cl := UI.label("%s ×%d" % [str(crystal.get("name", "水晶")), cost], 22,
			Color("#FFD45E") if afford else Color(1, 0.6, 0.6, 0.9), 6)
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		UI.place(cl, 470, 20, 200, 30)
		box.add_child(cl)

		var owned := int(row.get("owned", 0))
		var ol := UI.label("持有 %d / %d" % [owned, cost], 17,
			Color(0.9, 0.92, 0.98, 0.7), 4)
		ol.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		UI.place(ol, 470, 52, 200, 24)
		box.add_child(ol)

		var btn := UI.text_button(str(GameDB.gacha_shop().get("button_text", "兑换")), 22,
			Color("#FFC94A") if afford else Color(0.22, 0.20, 0.24, 0.9),
			Color("#B8791F") if afford else Color(1, 1, 1, 0.18),
			Color("#4A2408") if afford else Color(1, 1, 1, 0.45), 16)
		btn.name = "Exchange_%s" % str(row.get("char_id", ""))
		btn.disabled = not afford
		UI.place(btn, 690, 26, 168, 62)
		box.add_child(btn)
		btn.pressed.connect(_on_exchange_pressed.bind(str(row.get("char_id", ""))))


func _on_exchange_pressed(char_id: String) -> void:
	if _busy:
		return
	var res := GachaSys.exchange(_pool_id, char_id)
	if not bool(res.get("ok", false)):
		_show_toast(str(res.get("reason", "兑换失败")))
		return
	_refresh_all()
	var nm := str(GameDB.character(char_id).get("name", char_id))
	_show_toast("%s%s → %s" % [nm,
		" 已入队（新卡）" if bool(res.get("is_new", false)) else " 升星成功",
		"心愿水晶剩余 " + UI.fmt_num(SaveDB.balance(GachaSys.crystal_currency()))])


func _toggle_shop_panel(on: bool) -> void:
	_shop_panel.visible = on
	if on:
		_refresh_shop_panel()
		_shop_panel.modulate.a = 0.0
		create_tween().tween_property(_shop_panel, "modulate:a", 1.0, 0.14)
		_rate_panel.visible = false


# ---------------------------------------------------------------- 抽卡

func _on_pull(count: int) -> void:
	if _busy:
		return
	if _reveal.visible:
		_close_reveal()
	var res := GachaSys.pull(_pool_id, count)
	if not bool(res.get("ok", false)):
		_show_toast(str(res.get("reason", "抽取失败")))
		_refresh_cost()
		return
	_reveal_result = res
	_busy = true
	_refresh_all()
	# 先把卡面算好再开演：演出中途跳过 / 关面板都不会缺数据
	_build_reveal_cards(res)
	_show_toast("本次消耗：" + _pay_text(res) + "　心愿水晶 +%d" % int(res.get("crystals", 0)))
	if animate:
		_play_pull_sequence(res)
	else:
		# 无动画模式（冒烟测试）：直接落到静止结果
		_open_reveal(res)
		_finish_pull()


func _pay_text(res: Dictionary) -> String:
	var pay: Dictionary = res.get("pay", {})
	if pay.is_empty():
		return "无"
	return "%s ×%d" % [str(pay.get("name", pay.get("id", ""))), int(pay.get("amount", 0))]


func _finish_pull() -> void:
	_busy = false
	_refresh_cost()


# ---------------------------------------------------------------- 演出：撕包

func _play_idle() -> void:
	if _idle_tween and _idle_tween.is_valid():
		_idle_tween.kill()
	if _orbit_tween and _orbit_tween.is_valid():
		_orbit_tween.kill()
	# 悬浮呼吸：让祭坛上的卡包一直在动
	_idle_tween = create_tween().set_loops()
	_idle_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_idle_tween.tween_property(_codex, "position:y", _codex.position.y - 14.0, 2.2)
	_idle_tween.tween_property(_codex, "position:y", _codex.position.y, 2.2)
	# 星光环绕
	if animate:
		_orbit_tween = create_tween().set_loops()
		_orbit_tween.tween_property(_orbit, "rotation", TAU, 18.0).from(0.0)


func _pulse_codex() -> void:
	if not animate:
		return
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_codex, "scale", Vector2(1.08, 1.08), 0.14)
	tw.tween_property(_codex, "scale", Vector2.ONE, 0.22)


## 一次完整抽卡演出
func _play_pull_sequence(res: Dictionary) -> void:
	_skipped = false
	var reveal_cfg := GameDB.gacha_reveal()
	var raise := float(reveal_cfg.get("pack_raise_seconds", 0.55))
	var burst := float(reveal_cfg.get("pack_burst_seconds", 0.42))

	# 1) 卡包抬起 + 抖动
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_codex, "scale", Vector2(1.16, 1.16), raise * 0.5)
	tw.tween_property(_codex, "scale", Vector2(1.06, 1.06), raise * 0.5)
	_shake(_world, 6.0, raise)

	# 2) 撕开：两半飞散 + 白闪 + 散射光
	tw.tween_callback(func(): _burst_codex(burst))

	# 3) 光柱 + 震屏 + 卡牌逐张弹出
	tw.tween_interval(burst * 0.75)
	tw.tween_callback(func(): _open_reveal(res))


func _burst_codex(seconds: float) -> void:
	if _skipped:
		return
	_flash.visible = true
	_flash.color = Color(1.0, 0.96, 0.86, 0.0)
	var fw := create_tween()
	fw.tween_property(_flash, "color:a", 0.85, seconds * 0.3)
	fw.tween_property(_flash, "color:a", 0.0, seconds * 0.7)
	fw.tween_callback(func(): _flash.visible = false)

	# 两半卡包朝相反方向散开并淡出 —— 「卡包撕开」
	var half := create_tween().set_parallel(true)
	half.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	half.tween_property(_codex_top, "position:y", -160.0, seconds)
	half.tween_property(_codex_top, "rotation", -0.18, seconds)
	half.tween_property(_codex_top, "modulate:a", 0.0, seconds)
	half.tween_property(_codex_bottom, "position:y", 170.0, seconds)
	half.tween_property(_codex_bottom, "rotation", 0.16, seconds)
	half.tween_property(_codex_bottom, "modulate:a", 0.0, seconds)

	# 向四周散射的光芒：16 根细长光条
	var center := Vector2(CODEX_CENTER.x, CODEX_CENTER.y)
	for i in 16:
		var ang := TAU * float(i) / 16.0
		var ray := UI.gradient_rect(Color(1.0, 0.94, 0.72, 0.9), Color(1, 1, 1, 0.0), false)
		ray.name = "Ray%d" % i
		ray.pivot_offset = Vector2(0, 9)
		UI.place(ray, center.x, center.y - 9.0, 420, 18)
		ray.rotation = ang
		ray.scale = Vector2(0.1, 1.0)
		_world.add_child(ray)
		# 光条的生命周期绑在自己身上：卡包一散就随节点一起消失，不留孤儿补间
		var rt := ray.create_tween()
		rt.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		rt.tween_property(ray, "scale", Vector2(1.0, 1.0), seconds * 0.8)
		rt.parallel().tween_property(ray, "modulate:a", 0.0, seconds * 1.2).set_delay(seconds * 0.25)
		rt.tween_callback(func(): ray.queue_free())


func _shake(node: Control, amount: float, seconds: float) -> void:
	if not animate or node == null:
		return
	var base := node.position
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE)
	var steps := 8
	for i in steps:
		var amp := amount * (1.0 - float(i) / float(steps))
		var off := Vector2(randf_range(-amp, amp), randf_range(-amp * 0.6, amp * 0.6))
		tw.tween_property(node, "position", base + off, seconds / float(steps))
	tw.tween_property(node, "position", base, 0.05)


# ---------------------------------------------------------------- 演出：光柱与卡牌

func _open_reveal(res: Dictionary) -> void:
	var reveal_cfg := GameDB.gacha_reveal()
	if _reveal.visible and not animate:
		_reveal_all_cards()
		return
	_reveal.visible = true
	var has_big := bool(res.get("has_ssr", false)) or bool(res.get("has_ur", false))
	var max_rarity := str(res.get("max_rarity", "R"))

	var sub := "本次召唤结果"
	if bool(res.get("has_ur", false)):
		sub = "彩虹光柱冲天 · UR 降临"
	elif bool(res.get("has_ssr", false)):
		sub = "紫色光柱冲天 · SSR 降临"
	_reveal_sub.text = sub
	_reveal_sub.add_theme_color_override("font_color",
		Color("#FFD45E") if bool(res.get("has_ur", false))
		else (Color("#C08BFF") if bool(res.get("has_ssr", false)) else Color("#FFD98A")))
	_fill_reveal_summary()

	if not animate:
		# 静止态：铺满、不播
		_reveal_backdrop.modulate.a = 1.0
		_reveal_title.modulate.a = 1.0
		_reveal_sub.modulate.a = 1.0
		_pillar.visible = false
		_pillar_base.visible = false
		_reveal_all_cards()
		return

	_reveal_backdrop.modulate.a = 0.0
	_reveal_title.modulate.a = 0.0
	_reveal_sub.modulate.a = 0.0

	var tw := create_tween()
	tw.tween_property(_reveal_backdrop, "modulate:a", 1.0, 0.28 if has_big else 0.20)
	tw.parallel().tween_property(_reveal_title, "modulate:a", 1.0, 0.3)
	tw.parallel().tween_property(_reveal_sub, "modulate:a", 1.0, 0.3)

	if has_big:
		_paint_pillar(max_rarity, reveal_cfg)
		_show_pillar(true)
		var shake_cfg: Dictionary = reveal_cfg.get("shake", {})
		var amp := float(shake_cfg.get(max_rarity, shake_cfg.get("SSR", 8.0)))
		_shake(_reveal, amp, float(shake_cfg.get("seconds", 0.5)))
	else:
		_show_pillar(false)

	# 卡牌逐张弹出
	var stagger := float(reveal_cfg.get("card_stagger", 0.12))
	for i in _card_nodes.size():
		_pop_card(i, stagger * float(i))


## 光柱配色：SSR 紫、UR 彩虹，其余不亮柱
func _paint_pillar(rarity: String, reveal_cfg: Dictionary) -> void:
	var colors: Dictionary = reveal_cfg.get("pillar_colors", {})
	var strips: Array = []
	for c in _pillar.get_children():
		if str(c.name).begins_with("Strip"):
			strips.append(c)
	strips.sort_custom(func(a, b): return str(a.name) < str(b.name))

	if rarity == "UR":
		var rainbow: Array = reveal_cfg.get("rainbow", [])
		for i in strips.size():
			var col := Color(str(rainbow[i % maxi(1, rainbow.size())])) if not rainbow.is_empty() \
				else Color("#FFD45E")
			(strips[i] as TextureRect).modulate = Color(col.r, col.g, col.b, 0.95)
		_pillar_base.modulate = Color(1.0, 0.86, 0.45, 0.9)
	else:
		var col := Color(str(colors.get(rarity, colors.get("SSR", "#B06BE8"))))
		for s in strips:
			(s as TextureRect).modulate = Color(col.r, col.g, col.b, 0.9)
		_pillar_base.modulate = Color(col.r, col.g, col.b, 0.85)


func _show_pillar(on: bool) -> void:
	if not on:
		_pillar.visible = false
		_pillar_base.visible = false
		return
	_pillar.visible = true
	_pillar_base.visible = true
	# 从底部冲上来：纵向拉伸 + 淡入，然后收掉
	_pillar.pivot_offset = Vector2(_pillar.size.x * 0.5, _pillar.size.y)
	_pillar.scale = Vector2(0.35, 0.05)
	_pillar.modulate.a = 0.0
	_pillar_base.pivot_offset = _pillar_base.size * 0.5
	_pillar_base.scale = Vector2(0.4, 0.4)
	_pillar_base.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_pillar, "scale", Vector2.ONE, 0.34)
	tw.tween_property(_pillar, "modulate:a", 1.0, 0.24)
	tw.tween_property(_pillar_base, "scale", Vector2.ONE, 0.5)
	tw.tween_property(_pillar_base, "modulate:a", 1.0, 0.4)
	var fade := create_tween()
	fade.tween_interval(0.8)
	fade.tween_property(_pillar, "modulate:a", 0.0, 0.5)
	fade.parallel().tween_property(_pillar_base, "modulate:a", 0.0, 0.5)
	fade.tween_callback(_hide_pillar)


func _hide_pillar() -> void:
	_pillar.visible = false
	_pillar_base.visible = false


func _pop_card(index: int, delay: float) -> void:
	if index >= _card_nodes.size():
		return
	var node: Control = _card_nodes[index]
	node.visible = true
	if not animate:
		node.scale = Vector2.ONE
		node.modulate = Color.WHITE
		return
	node.pivot_offset = node.size * 0.5
	node.scale = Vector2(1.28, 1.28)
	node.modulate.a = 0.0
	var tw := node.create_tween()
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(node, "scale", Vector2.ONE, 0.30)
	tw.parallel().tween_property(node, "modulate:a", 1.0, 0.18)
	# 高品质卡落地后继续流光：策划案要的「动态卡面」
	if _is_high(str(node.get_meta("rarity", "R"))):
		var loop := node.create_tween().set_loops()
		loop.tween_interval(delay + 0.4)
		loop.tween_property(node, "modulate", Color(1.12, 1.08, 1.0), 1.1)
		loop.tween_property(node, "modulate", Color.WHITE, 1.1)


func _is_high(rarity: String) -> bool:
	return GameDB.rarity_at_least(rarity, "SSR")


## 「跳过」：把演出切成静止态
func _skip_reveal() -> void:
	if not _reveal.visible:
		return
	_skipped = true
	_flash.visible = false
	_hide_pillar()
	_reveal_backdrop.modulate.a = 1.0
	_reveal_title.modulate.a = 1.0
	_reveal_sub.modulate.a = 1.0
	_reveal_all_cards()
	_finish_pull()


func _reveal_all_cards() -> void:
	for node in _card_nodes:
		var c: Control = node
		c.visible = true
		c.modulate = Color.WHITE
		c.scale = Vector2.ONE
	if _reveal_summary.text == "":
		_fill_reveal_summary()


func _fill_reveal_summary() -> void:
	var res := _reveal_result
	var pity := GachaSys.pity_state(_pool_id)
	var parts: Array = ["心愿水晶 +%d" % int(res.get("crystals", 0))]
	parts.append("累计 %d 抽" % SaveDB.total_pulls())
	if bool(pity.get("small_on", false)):
		parts.append("小保底 %d/%d" % [int(pity.get("small", 0)), int(pity.get("small_max", 50))])
	if bool(pity.get("large_on", false)):
		parts.append("大保底 %d/%d" % [int(pity.get("large", 0)), int(pity.get("large_max", 100))])
	_reveal_summary.text = "　·　".join(parts)


# ---------------------------------------------------------------- 结果卡面

## 按「几张」决定卡面：单抽给完整卡（CardView，带三围条），十连排 2×5 用紧凑卡。
## 紧凑卡不是省事 —— 是把「立体贴纸 / 潮玩卡框」这个形态单独做出来：
## 完整卡面按内腔分三格摆三围条，卡片小了第三个数值必被卡框切掉。
func _build_reveal_cards(res: Dictionary) -> void:
	for c in _reveal_cards.get_children():
		c.queue_free()
	_card_nodes.clear()
	var items: Array = res.get("items", [])
	var single := items.size() == 1
	var box := SINGLE_BOX if single else MULTI_BOX
	var columns := 1 if single else MULTI_COLUMNS

	for i in items.size():
		var it: Dictionary = items[i]
		var node: Control = _make_card(it, box)
		if node == null:
			continue
		var row := i / columns
		var col := i % columns
		var in_row := mini(columns, items.size() - row * columns)
		var total := float(in_row) * (box.x + CARD_GAP) - CARD_GAP
		var x := (STAGE_WIDTH - total) * 0.5 + float(col) * (box.x + CARD_GAP)
		var y := ROW_TOP + float(row) * (box.y + ROW_GAP)
		if single:
			y = (STAGE_HEIGHT - box.y) * 0.5 - 34.0
		node.position = Vector2(x, y)
		node.visible = false
		node.set_meta("rarity", str(it.get("rarity", "R")))
		_reveal_cards.add_child(node)
		_card_nodes.append(node)


func _make_card(it: Dictionary, box: Vector2) -> Control:
	if str(it.get("kind", "hero")) == "hero":
		return _make_hero_card(it, box)
	return _make_material_card(it, box)


func _make_hero_card(it: Dictionary, box: Vector2) -> Control:
	var char_id := str(it.get("char_id", ""))
	var cfg: Dictionary = it.get("config", {})
	if cfg.is_empty():
		cfg = GameDB.character(char_id)
	if cfg.is_empty():
		return null
	var rarity_id := str(it.get("rarity", cfg.get("rarity", "R")))
	var card: Dictionary = it.get("card", {})
	var stats: Dictionary = it.get("stats", {})
	if card.is_empty():
		card = { "char_id": char_id, "level": 1, "star": 1, "exp": 0,
			"equipment": GameDB.blank_equipment() }
	if stats.is_empty():
		stats = RealmDB.stats_of(card)

	var holder := Control.new()
	holder.name = "Card_%s" % char_id
	holder.custom_minimum_size = box
	holder.size = box
	holder.mouse_filter = Control.MOUSE_FILTER_PASS

	var glow := UI.glow_rect(Color(str(GameDB.rarity(rarity_id).get("glow", "#FFFFFF"))), 0.42)
	UI.place(glow, -box.x * 0.18, -box.y * 0.12, box.x * 1.36, box.y * 1.24)
	holder.add_child(glow)

	if box.x >= FULL_CARD_MIN_WIDTH and _has_art(cfg):
		# 完整卡面：直接复用主界面的 CardView，卡框 / 内腔 / 三围条一处口径
		var view: CardView = CardViewScript.new()
		view.name = "View"
		view.setup({
			"char_id": char_id, "config": cfg, "card": card, "stats": stats,
		}, GameDB.rarity(rarity_id), GameDB.element(str(cfg.get("element", ""))), box)
		UI.place(view, 0, 0, box.x, box.y)
		holder.add_child(view)
	else:
		holder.add_child(_compact_card_face(cfg, card, rarity_id, box))

	holder.add_child(_tag_row(it, box))
	return holder


## 立绘是否已就位。这一批 GDD 新英雄（秘法少女 / 暗夜刺客 …）目前只有配置，
## 美术图还没进来 —— 缺图时不能留个洞，要有占位。
func _has_art(cfg: Dictionary) -> bool:
	var path := str(cfg.get("portrait", ""))
	return path != "" and ResourceLoader.exists(path)


## 立绘：有图按原样铺满，没图就画一块品质色底 + 元素徽记 + 一行占位提示
func _fill_portrait(holder: Control, cfg: Dictionary, rect: Rect2) -> void:
	var clip := Control.new()
	clip.clip_contents = true
	UI.place(clip, rect.position.x, rect.position.y, rect.size.x, rect.size.y)
	holder.add_child(clip)

	if _has_art(cfg):
		var pic := UI.picture(str(cfg.get("portrait", "")), TextureRect.STRETCH_SCALE)
		UI.place(pic, 0, 0, rect.size.x, rect.size.y)
		clip.add_child(pic)
		return

	var element := str(cfg.get("element", ""))
	var accent := GameDB.element_color(element)
	var bed := UI.gradient_rect(Color(accent.r, accent.g, accent.b, 0.5),
		Color(0.06, 0.05, 0.10, 0.92))
	UI.fill(bed)
	clip.add_child(bed)

	var ic := UI.icon(str(GameDB.element(element).get("icon", "")),
		rect.size.x * 0.42, Color(accent.r, accent.g, accent.b, 0.72))
	UI.place(ic, rect.size.x * 0.29, rect.size.y * 0.24, rect.size.x * 0.42, rect.size.x * 0.42)
	clip.add_child(ic)

	var tip := UI.label("立绘待接入", 15, Color(1, 1, 1, 0.62), 4, Color(0, 0, 0, 0.6))
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.place(tip, 0, rect.size.y - 30.0, rect.size.x, 22)
	clip.add_child(tip)


## 紧凑卡面：卡框 + 立绘 + 品质星级 + 名字，走「贴纸 / 潮玩卡」形态
func _compact_card_face(cfg: Dictionary, card: Dictionary, rarity_id: String, box: Vector2) -> Control:
	var face := Control.new()
	face.name = "Face"
	UI.place(face, 0, 0, box.x, box.y)

	var rc := GameDB.rarity(rarity_id)
	var inner := GameDB.rarity_inner_rect(rarity_id)
	var win := Rect2(
		inner.position.x * box.x, inner.position.y * box.y,
		inner.size.x * box.x, inner.size.y * box.y)

	var bed := UI.panel(Color(str(rc.get("bed_tint", "#222222"))), 18)
	UI.place(bed, 0, 0, box.x, box.y)
	face.add_child(bed)

	_fill_portrait(face, cfg, win)

	var band := UI.gradient_rect(Color(0.05, 0.04, 0.08, 0.0), Color(0.05, 0.04, 0.08, 0.92))
	UI.place(band, 0, win.position.y + win.size.y * 0.5, box.x, box.y - win.position.y - win.size.y * 0.5)
	face.add_child(band)

	var frame := UI.picture(str(rc.get("frame", "")), TextureRect.STRETCH_SCALE)
	UI.place(frame, 0, 0, box.x, box.y)
	face.add_child(frame)

	var eb := UI.icon(str(GameDB.element(str(cfg.get("element", ""))).get("icon", "")),
		box.x * 0.26, Color.WHITE)
	UI.place(eb, win.position.x + 10.0, win.position.y + 10.0, box.x * 0.26, box.x * 0.26)
	face.add_child(eb)

	var rar := UI.label(rarity_id, maxi(18, int(box.x / 9.0)), Color.WHITE, 6, Color(0, 0, 0, 0.85))
	rar.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UI.place(rar, win.position.x, win.position.y + 2.0, win.size.x - 10.0, 32)
	face.add_child(rar)

	var star := clampi(int(card.get("star", 1)), 0, int(rc.get("star_max", 3)))
	if star > 0:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 1)
		UI.place(row, win.position.x + win.size.x - 10.0 - float(star) * 20.0,
			win.position.y + 34.0, float(star) * 20.0, 22)
		face.add_child(row)
		for i in star:
			row.add_child(UI.icon("res://assets/icons/icon_star.svg", 19.0, Color("#FFD45E")))

	var nm := UI.label(str(cfg.get("name", "")), maxi(16, int(box.x / 11.0)), UI.CREAM, 6)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.place(nm, win.position.x, box.y - win.position.y - win.size.y * 0.42, win.size.x, 34)
	face.add_child(nm)

	var lv := UI.label("Lv.%d" % int(card.get("level", 1)), 15, Color("#FFE9A8"), 4)
	lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.place(lv, win.position.x, box.y - 34.0, win.size.x, 24)
	face.add_child(lv)
	return face


## 角标：NEW / 升星 / UP / 保底。
## 刻意挂在卡片**上沿之外**横着排 —— 卡面下半是名牌与三围条，
## 竖着堆在卡内必然压住这些既有信息。
func _tag_row(it: Dictionary, box: Vector2) -> Control:
	var tags: Array = []
	if bool(it.get("is_new", false)):
		tags.append(["NEW", Color("#7BE0A8")])
	elif bool(it.get("star_up", false)):
		tags.append(["升星 ★%d" % int(it.get("star", 1)), Color("#FFD45E")])
	if bool(it.get("is_up", false)):
		tags.append(["当期 UP", Color("#C08BFF")])
	if bool(it.get("is_up_pity", false)):
		tags.append(["大保底", Color("#FF9E6B")])
	elif bool(it.get("is_small_pity", false)):
		tags.append(["小保底", Color("#FF9E6B")])
	elif bool(it.get("is_ten_guarantee", false)):
		tags.append(["十连保底", Color("#FF9E6B")])

	var holder := Control.new()
	holder.name = "Tags"
	UI.place(holder, -box.x * 0.06, -30.0, box.x * 1.12, 26)

	var chip_w := 96.0
	var gap := 6.0
	var total := float(tags.size()) * chip_w + gap * float(maxi(0, tags.size() - 1))
	var x := (holder.custom_minimum_size.x - total) * 0.5
	for raw in tags:
		var t: Array = raw
		var accent: Color = t[1]
		var chip := UI.panel(Color(0.05, 0.04, 0.08, 0.95), 10, 2, accent, 6)
		UI.place(chip, x, 0, chip_w, 24)
		holder.add_child(chip)
		var lb := UI.label(str(t[0]), 15, accent.lightened(0.2), 4)
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		UI.fill(lb)
		chip.add_child(lb)
		x += chip_w + gap
	return holder


## 道具卡（英雄经验 / 突破石）：不是英雄，没卡框，用同一套品质配色画一张
func _make_material_card(it: Dictionary, box: Vector2) -> Control:
	var rarity_id := str(it.get("rarity", "R"))
	var rc := GameDB.rarity(rarity_id)
	var accent := Color(str(rc.get("color", "#FFFFFF")))
	var holder := Control.new()
	holder.name = "Item_%s" % str(it.get("id", ""))
	holder.custom_minimum_size = box
	holder.size = box
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var glow := UI.glow_rect(accent, 0.30)
	UI.place(glow, -box.x * 0.18, -box.y * 0.14, box.x * 1.36, box.y * 1.28)
	holder.add_child(glow)

	var bed := UI.panel(Color(str(rc.get("bed_tint", "#222222"))), 20, 3, accent, 12)
	UI.place(bed, 0, 0, box.x, box.y)
	holder.add_child(bed)

	var icon := UI.icon(str(it.get("icon", "res://assets/icons/icon_star.svg")),
		minf(box.x * 0.5, 120.0), accent.lightened(0.25))
	UI.place(icon, box.x * 0.25, box.y * 0.16, box.x * 0.5, box.x * 0.5)
	holder.add_child(icon)

	var nm := UI.label(str(it.get("name", "")), maxi(14, int(box.y / 22.0)), UI.CREAM, 6)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.place(nm, 8, box.y * 0.62, box.x - 16, 30)
	holder.add_child(nm)

	var cnt := UI.label("×%d" % int(it.get("count", 1)), maxi(16, int(box.y / 16.0)),
		accent.lightened(0.3), 6)
	cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.place(cnt, 8, box.y * 0.72, box.x - 16, 34)
	holder.add_child(cnt)

	var owned := UI.label("持有 %s" % UI.fmt_num(int(it.get("owned", 0))), 15,
		Color(0.9, 0.92, 0.98, 0.72), 4)
	owned.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.place(owned, 8, box.y - 34, box.x - 16, 26)
	holder.add_child(owned)

	var tag := UI.label("狗粮 / 材料", 14, Color(1, 1, 1, 0.6), 4)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.place(tag, 8, 10, box.x - 16, 22)
	holder.add_child(tag)
	return holder


func _on_reveal_again() -> void:
	var count := 1 if _card_nodes.size() == 1 else 10
	_close_reveal()
	_on_pull(count)


func _close_reveal() -> void:
	_reveal.visible = false
	_hide_pillar()
	_flash.visible = false
	# 卡包复位：撕开的两半回到原位，下一次抽取才能再撕一遍
	_codex_top.position = Vector2.ZERO
	_codex_bottom.position = Vector2(0.0, CODEX_HEIGHT * 0.5)
	_codex_top.rotation = 0.0
	_codex_bottom.rotation = 0.0
	_codex_top.modulate.a = 1.0
	_codex_bottom.modulate.a = 1.0
	_codex.scale = Vector2.ONE
	for c in _reveal_cards.get_children():
		c.queue_free()
	_card_nodes.clear()
	_skipped = false
	_finish_pull()
	_refresh_all()


# ---------------------------------------------------------------- 返回 / 提示

func _on_back() -> void:
	var route := str((_gacha().get("back_button", {}) as Dictionary).get("route", MAIN_MENU_SCENE))
	if not ResourceLoader.exists(route):
		route = MAIN_MENU_SCENE
	if auto_transition and ResourceLoader.exists(route):
		get_tree().change_scene_to_file(route)


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
