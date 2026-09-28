extends SceneTree
## build_gacha.gd —— 程序化构建抽卡界面场景
##
## 用法（headless）：
##   Godot --headless --path <项目> --script res://tools/build_gacha.gd
##
## 产出：res://scenes/gacha.tscn
##
## 版面按策划案 §1「2.5D 悬浮魔法祭坛」搭：
##   中央是带浮雕流光质感的卡包 / 魔法圣典，环绕星光粒子，脚下是一圈祭坛台面；
##   四周是数据与操作区（左上资源、顶部卡池与保底、底部单抽 / 十连、右栏公示与商店）。
##
## 与其它 build_*.gd 同一套约定：
##   1. 不依赖 autoload —— 配置直接读 res://data/game_data.json，运行时由 gacha.gd 覆盖；
##   2. 静态布局全部用「锚点 + 偏移」写死，换分辨率不错位；
##   3. 会震屏的节点收敛在 World 层里，Hud 不跟着抖，免得按钮乱跳。

const UI := preload("res://tools/ui_kit.gd")

## gacha.gd 引用了 autoload，而 autoload 全局名在 --script 模式下要等主循环
## 才注册，所以这里必须用延迟 load()，不能 preload。
const GACHA_SCRIPT_PATH := "res://scripts/gacha.gd"

const DATA_PATH := "res://data/game_data.json"
const OUT_PATH := "res://scenes/gacha.tscn"
const BG_PATH := "res://assets/art/bg/bg_islands.png"
const BASE := Vector2(1920, 1080)

const PANEL_BG := Color(0.09, 0.07, 0.13, 0.78)
const PANEL_BG_SOFT := Color(0.09, 0.07, 0.13, 0.62)
const PANEL_BORDER := Color(1.0, 0.85, 0.45, 0.45)
const PANEL_BORDER_SOFT := Color(1.0, 0.85, 0.45, 0.26)

const PLATE := Rect2(26, 18, 448, 148)
const RESOURCE_PANEL := Rect2(26, 180, 448, 244)
const RECENT_PANEL := Rect2(26, 440, 448, 340)
const BACK_BUTTON := Rect2(20, 1010, 260, 58)

const TITLE_BOX := Vector2(1000, 86)
const PITY_BADGE := Rect2(620, 232, 680, 60)

const CODEX := Vector2(380, 500)
const CODEX_CENTER := Vector2(960, 552)
const ALTAR_RING := Rect2(596, 768, 728, 130)

const PULL_ONE := Rect2(600, 906, 340, 108)
const PULL_TEN := Rect2(980, 906, 340, 108)

const RIGHT_X := 1574.0
const RIGHT_W := 320.0
const RATE_BUTTON := Rect2(RIGHT_X, 286, RIGHT_W, 76)
const SHOP_BUTTON := Rect2(RIGHT_X, 378, RIGHT_W, 76)
const RULE_PANEL := Rect2(RIGHT_X, 470, RIGHT_W, 320)

const TOAST := Rect2(660, 1006, 600, 56)
const RATE_PANEL := Rect2(420, 76, 1080, 880)
const SHOP_PANEL := Rect2(470, 96, 980, 840)

const UNIQUE_NAMES := [
	"AvatarTex", "PlayerName", "PlayerLevel", "GemLabel", "GoldLabel",
	"BoundGemLabel", "CrystalLabel", "TicketBasicLabel", "TicketAdvancedLabel",
	"TitleLabel", "SubTitle", "PoolTabs", "PoolName", "PoolDesc",
	"PityBadge", "PitySmall", "PityLarge", "PitySmallBar", "PityLargeBar",
	"PitySmallHalf", "PityLargeHalf",
	"World", "AltarGlow", "AltarRing", "MagicCodex", "CodexTop", "CodexBottom",
	"CodexEmblem", "CodexTag", "CodexPoolName", "CodexHint", "CodexCost",
	"OrbitRing", "PackParticles", "ExpBar", "CurrencyRow",
	"PullOneButton", "PullOneCost", "PullTenButton", "PullTenCost", "TenTag",
	"RateButton", "ShopButton", "ShopCrystalLabel", "RulePanel", "RuleBody",
	"RecentPanel", "RecentRow", "BackButton", "FooterInfo", "Toast", "ToastLabel",
	"RevealLayer", "RevealBackdrop", "LightPillar", "PillarBase", "RevealCards",
	"RevealTitle", "RevealSub", "RevealSummary", "RevealSkipButton",
	"RevealAgainButton", "RevealCloseButton", "FlashRect",
	"RatePanel", "RateBody", "RateCloseButton", "RatePoolName", "RecentEmpty",
	"ShopPanel", "ShopBody", "ShopCloseButton", "ShopBalanceLabel", "FooterStat",
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
	_root.name = "Gacha"
	var script: Script = load(GACHA_SCRIPT_PATH)
	if script == null:
		push_error("[build] 无法加载 %s" % GACHA_SCRIPT_PATH)
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

	var world := _mk(_root, Control.new(), "World")
	UI.fill(world)
	world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_altar(world)
	_build_codex(world)

	var hud := _mk(_root, Control.new(), "Hud")
	UI.fill(hud)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_player_plate(hud)
	_build_resource_panel(hud)
	_build_recent_panel(hud)
	_build_title(hud)
	_build_pity_badge(hud)
	_build_pull_buttons(hud)
	_build_right_rail(hud)
	_build_back_button(hud)
	_build_toast(hud)
	_build_footer(hud)

	_build_flash(hud)
	_build_reveal_layer(hud)
	_build_popups(hud)

	for child in _root.get_children():
		UI.set_owner_recursive(child, _root)
	_mark_unique()
	print("[build] 节点树组装完成，共 %d 个节点（卡池 %d 个）"
		% [_count(_root), _pools().size()])


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
	bg.name = "Background"
	UI.fill(bg)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mk(_root, bg, "Background")

	# 比主界面更暗一档：祭坛要把光压出来
	var tint := ColorRect.new()
	tint.name = "NightTint"
	tint.color = Color(0.06, 0.04, 0.12, 0.42)
	UI.fill(tint)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mk(_root, tint, "NightTint")

	# 上下压暗，让中央祭坛成为视线落点
	var top := UI.gradient_rect(Color(0, 0, 0, 0.55), Color(0, 0, 0, 0.0))
	UI.place(top, 0, 0, 1920, 320)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mk(_root, top, "TopShade")

	var bottom := UI.gradient_rect(Color(0, 0, 0, 0.0), Color(0.02, 0.01, 0.04, 0.72))
	UI.place(bottom, 0, 700, 1920, 380)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mk(_root, bottom, "BottomShade")


# ---------------------------------------------------------------- 祭坛

func _build_altar(world: Control) -> void:
	var glow := UI.glow_rect(Color("#FFD45E"), 0.30)
	glow.name = "AltarGlow"
	UI.place(glow, CODEX_CENTER.x - 620.0, CODEX_CENTER.y - 400.0, 1240, 800)
	world.add_child(glow)

	# 台面：一个被压扁的圆角矩形 —— 2.5D 视角下就是一个圆盘
	var ring := _mk(world, Panel.new(), "AltarRing")
	ring.add_theme_stylebox_override("panel", _ellipse_style(
		Color(0.10, 0.08, 0.16, 0.72), Color(1.0, 0.85, 0.45, 0.42), 4))
	UI.place(ring, ALTAR_RING.position.x, ALTAR_RING.position.y,
		ALTAR_RING.size.x, ALTAR_RING.size.y)

	var inner := Panel.new()
	inner.name = "AltarInner"
	inner.add_theme_stylebox_override("panel", _ellipse_style(
		Color(0.30, 0.22, 0.44, 0.36), Color(1.0, 0.90, 0.60, 0.30), 2))
	UI.place(inner, 26, 20, ALTAR_RING.size.x - 52, ALTAR_RING.size.y - 40)
	ring.add_child(inner)

	# 台面上的符文刻线：一圈星点，替美术图占位
	var runes := Control.new()
	runes.name = "AltarRunes"
	UI.place(runes, 0, 0, ALTAR_RING.size.x, ALTAR_RING.size.y)
	ring.add_child(runes)
	for i in 9:
		var ang := TAU * float(i) / 9.0
		var st := UI.icon("res://assets/icons/icon_star.svg", 22.0, Color(1.0, 0.88, 0.55, 0.55))
		UI.place(st, ALTAR_RING.size.x * 0.5 + cos(ang) * (ALTAR_RING.size.x * 0.5 - 46.0) - 11.0,
			ALTAR_RING.size.y * 0.5 + sin(ang) * (ALTAR_RING.size.y * 0.5 - 22.0) - 11.0, 22, 22)
		runes.add_child(st)


# ---------------------------------------------------------------- 中央：魔法圣典

func _build_codex(world: Control) -> void:
	var holder := _mk(world, Control.new(), "MagicCodex")
	UI.place(holder, CODEX_CENTER.x - CODEX.x * 0.5,
		CODEX_CENTER.y - CODEX.y * 0.5, CODEX.x, CODEX.y)

	var glow := UI.glow_rect(Color("#C08BFF"), 0.34)
	glow.name = "CodexGlow"
	UI.place(glow, -180, -140, CODEX.x + 360, CODEX.y + 280)
	holder.add_child(glow)

	# 卡包做成上下两半：撕开时两半各自飞走，就是「卡包撕开」的观感
	var top := _mk(holder, Panel.new(), "CodexTop")
	top.add_theme_stylebox_override("panel", _half_style(
		Color(0.20, 0.13, 0.32, 0.96), Color("#C08BFF"), true))
	UI.place(top, 0, 0, CODEX.x, CODEX.y * 0.5)
	_build_codex_face(top, true)

	var bottom := _mk(holder, Panel.new(), "CodexBottom")
	bottom.add_theme_stylebox_override("panel", _half_style(
		Color(0.13, 0.09, 0.22, 0.96), Color("#C08BFF"), false))
	UI.place(bottom, 0, CODEX.y * 0.5, CODEX.x, CODEX.y * 0.5)
	_build_codex_face(bottom, false)

	# 中缝：烫金书脊
	var spine := ColorRect.new()
	spine.name = "CodexSpine"
	spine.color = Color(1.0, 0.85, 0.45, 0.75)
	UI.place(spine, 10, CODEX.y * 0.5 - 3.0, CODEX.x - 20, 6)
	holder.add_child(spine)

	# 环绕的星光：一圈星形图标 + 两片粒子
	var orbit := _mk(holder, Control.new(), "OrbitRing")
	UI.place(orbit, -160, -110, CODEX.x + 320, CODEX.y + 220)
	for i in 10:
		var ang := TAU * float(i) / 10.0
		var st := UI.icon("res://assets/icons/icon_star.svg",
			18.0 + 8.0 * float(i % 3), Color(1.0, 0.90, 0.62, 0.85))
		UI.place(st, orbit.custom_minimum_size.x * 0.5 + cos(ang) * (CODEX.x * 0.72) - 12.0,
			orbit.custom_minimum_size.y * 0.5 + sin(ang) * (CODEX.y * 0.62) - 12.0, 30, 30)
		orbit.add_child(st)

	# 粒子是 Node2D，不进 Control 的锚点体系，位置直接给 —— 别用 UI.place()
	var rise := _mk_particles(holder, "PackParticles", Color(1.0, 0.86, 0.52, 0.9), 46, 26.0)
	rise.position = Vector2(CODEX.x * 0.5, CODEX.y - 40.0)

	var mist := _mk_particles(holder, "CodexMist", Color(0.75, 0.55, 1.0, 0.65), 30, 12.0)
	mist.position = Vector2(CODEX.x * 0.5, -20.0)


## 卡包正面：外框描线 + 徽记 + 卡池名（会被 gacha.gd 按当前卡池重刷）
func _build_codex_face(half: Panel, top_half: bool) -> void:
	var inset := Panel.new()
	inset.name = "Emboss"
	inset.add_theme_stylebox_override("panel", UI.style(
		Color(0, 0, 0, 0), 18, 2, Color(1.0, 0.88, 0.58, 0.35)))
	UI.place(inset, 16, 14, CODEX.x - 32, CODEX.y * 0.5 - 28)
	half.add_child(inset)

	if top_half:
		var emblem := UI.icon("res://assets/icons/icon_gacha.svg", 132.0, Color(1.0, 0.92, 0.70))
		emblem.name = "CodexEmblem"
		UI.place(emblem, (CODEX.x - 132.0) * 0.5, 54, 132, 132)
		half.add_child(emblem)

		var tag := UI.label("", 20, Color("#FFE9A8"), 6)
		tag.name = "CodexTag"
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UI.place(tag, 20, 16, CODEX.x - 40, 26)
		half.add_child(tag)
	else:
		var nm := UI.label("", 28, Color("#FFE9A8"), 7)
		nm.name = "CodexPoolName"
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UI.place(nm, 24, 24, CODEX.x - 48, 78)
		half.add_child(nm)

		var hint := UI.label("", 18, Color(0.90, 0.86, 1.0, 0.72), 5)
		hint.name = "CodexHint"
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UI.place(hint, 20, 108, CODEX.x - 40, 50)
		half.add_child(hint)

		var cost := UI.label("", 20, Color("#FFD98A"), 5)
		cost.name = "CodexCost"
		cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UI.place(cost, 20, 172, CODEX.x - 40, 28)
		half.add_child(cost)


# ---------------------------------------------------------------- 左上：玩家 / 资源

func _build_player_plate(hud: Control) -> void:
	var plate := _mk(hud, Control.new(), "PlayerPlate")
	UI.place(plate, PLATE.position.x, PLATE.position.y, PLATE.size.x, PLATE.size.y)

	var bg := UI.panel(Color(0.09, 0.07, 0.13, 0.66), 20, 2, PANEL_BORDER, 10)
	UI.place(bg, 0, 10, PLATE.size.x, PLATE.size.y - 10)
	plate.add_child(bg)

	var frame := UI.panel(Color(0.06, 0.05, 0.09, 0.85), 24, 3, UI.GOLD, 8, Color(0, 0, 0, 0.5))
	UI.place(frame, 14, 22, 100, 100)
	plate.add_child(frame)

	var avatar := UI.picture(_player_avatar(), TextureRect.STRETCH_KEEP_ASPECT_COVERED)
	avatar.name = "AvatarTex"
	UI.place(avatar, 21, 29, 86, 86)
	plate.add_child(avatar)

	var nm := UI.label(str(_player().get("name", "云上旅人")), 28, UI.CREAM, 6)
	nm.name = "PlayerName"
	UI.place(nm, 126, 26, 240, 36)
	plate.add_child(nm)

	var pill := UI.panel(UI.GOLD, 13, 2, UI.GOLD_DEEP)
	UI.place(pill, 126, 68, 74, 26)
	plate.add_child(pill)
	var lv := UI.label("Lv.%d" % int(_player().get("level", 1)), 19, UI.INK, 0)
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
	bar.add_theme_stylebox_override("background", UI.style(Color(0, 0, 0, 0.5), 7, 2, Color(0, 0, 0, 0.35)))
	bar.add_theme_stylebox_override("fill", UI.style(Color("#5BD6A6"), 7))
	UI.place(bar, 210, 74, 156, 14)
	plate.add_child(bar)

	var cr := HBoxContainer.new()
	cr.name = "CurrencyRow"
	cr.add_theme_constant_override("separation", 16)
	UI.place(cr, 126, 104, 310, 30)
	plate.add_child(cr)
	var pairs := [
		["gem", "GemLabel", int(_player().get("gem", 0))],
		["coin", "GoldLabel", int(_player().get("gold", 0))],
	]
	for raw in pairs:
		var p: Array = raw
		var ic := UI.icon("res://assets/icons/icon_%s.svg" % str(p[0]), 24.0,
			Color("#7BE0FF") if str(p[0]) == "gem" else Color("#FFC94A"))
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cr.add_child(ic)
		var l := UI.label(UI.fmt_num(int(p[2])), 21, UI.CREAM, 6)
		l.name = str(p[1])
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cr.add_child(l)


## 资源面板：这一页真正会花掉的四样东西
func _build_resource_panel(hud: Control) -> void:
	var panel := _mk(hud, UI.panel(PANEL_BG_SOFT, 20, 2, PANEL_BORDER_SOFT, 10), "ResourcePanel")
	UI.place(panel, RESOURCE_PANEL.position.x, RESOURCE_PANEL.position.y,
		RESOURCE_PANEL.size.x, RESOURCE_PANEL.size.y)

	var title := UI.label("召唤资源", 22, Color("#FFD98A"), 5)
	UI.place(title, 18, 10, 260, 30)
	panel.add_child(title)

	var row := UI.label("资源不足时按钮会变灰，券优先于钻石", 16, Color(1, 1, 1, 0.55), 4)
	row.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UI.place(row, 120, 14, 310, 24)
	panel.add_child(row)

	var rows := [
		["ticket_basic", "TicketBasicLabel", "基础召唤券", "res://assets/icons/icon_gift.svg", "#7BE0FF", "常驻召唤 ×1"],
		["ticket_advanced", "TicketAdvancedLabel", "高级召唤卷轴", "res://assets/icons/icon_gift.svg", "#C08BFF", "限时 UP ×1"],
		["bound_gem", "BoundGemLabel", "绑定钻石", "res://assets/icons/icon_gem.svg", "#9AA7FF", "×160 / 次"],
		["wish_crystal", "CrystalLabel", "心愿水晶", "res://assets/icons/icon_gem.svg", "#FFD45E", "每抽 +1"],
	]
	var y := 48.0
	for raw in rows:
		var r: Array = raw
		var accent := Color(str(r[4]))
		var box := Panel.new()
		box.name = "Res_%s" % str(r[0])
		box.add_theme_stylebox_override("panel",
			UI.style(Color(0.07, 0.06, 0.11, 0.55), 14, 1, Color(accent.r, accent.g, accent.b, 0.35)))
		UI.place(box, 16, y, RESOURCE_PANEL.size.x - 32, 46)
		panel.add_child(box)

		var ic := UI.icon(str(r[3]), 26.0, accent)
		UI.place(ic, 12, 10, 26, 26)
		box.add_child(ic)

		var nm := UI.label(str(r[2]), 20, UI.CREAM, 5)
		UI.place(nm, 46, 9, 168, 28)
		box.add_child(nm)

		var val := UI.label("--", 22, accent.lightened(0.25), 6)
		val.name = str(r[1])
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		UI.place(val, 220, 8, 92, 30)
		box.add_child(val)

		var note := UI.label(str(r[5]), 15, Color(1, 1, 1, 0.45), 3)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		UI.place(note, 314, 12, 100, 24)
		box.add_child(note)
		y += 48.0


# ---------------------------------------------------------------- 左中：最近获得

func _build_recent_panel(hud: Control) -> void:
	var panel := _mk(hud, UI.panel(PANEL_BG_SOFT, 20, 2, PANEL_BORDER_SOFT, 10), "RecentPanel")
	UI.place(panel, RECENT_PANEL.position.x, RECENT_PANEL.position.y,
		RECENT_PANEL.size.x, RECENT_PANEL.size.y)

	var title := UI.label("最近获得", 22, Color("#FFD98A"), 5)
	UI.place(title, 18, 10, 200, 30)
	panel.add_child(title)

	var hint := UI.label("召唤记录（最近 30 条）", 15, Color(1, 1, 1, 0.5), 4)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UI.place(hint, 180, 14, 250, 24)
	panel.add_child(hint)

	var row := _mk(panel, HBoxContainer.new(), "RecentRow")
	row.add_theme_constant_override("separation", 10)
	UI.place(row, 18, 48, RECENT_PANEL.size.x - 36, 270)

	# 空态提示：没有任何记录时显示，有记录时由 gacha.gd 隐藏
	var empty := UI.label("还没有召唤记录，先抽一发试试", 18, Color(1, 1, 1, 0.5), 5)
	empty.name = "RecentEmpty"
	empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.place(empty, 18, 150, RECENT_PANEL.size.x - 36, 30)
	panel.add_child(empty)


# ---------------------------------------------------------------- 顶部：标题 / 卡池 / 保底

func _build_title(hud: Control) -> void:
	var group := _mk(hud, Control.new(), "TitleGroup")
	UI.anchor_top_center(group, TITLE_BOX.x, 230, 14)

	var title: Control = UI.label_shadow(
		str(_gacha().get("title", "群星召唤")), 62, Color("#FFE9A8"), 13,
		Color("#6B3A16"), Vector2(0, 6), Color("#3A1B05"), Vector2(TITLE_BOX.x, 76))
	title.name = "TitleLabel"
	UI.place(title, 0, 0, TITLE_BOX.x, 76)
	group.add_child(title)

	var sub := UI.label(str(_gacha().get("subtitle", "")), 22, Color("#FFD98A"), 6,
		Color(0.28, 0.14, 0.03, 0.85))
	sub.name = "SubTitle"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.place(sub, 0, 76, TITLE_BOX.x, 28)
	group.add_child(sub)

	var tabs := _mk(group, HBoxContainer.new(), "PoolTabs")
	tabs.add_theme_constant_override("separation", 12)
	var n := maxi(1, _pools().size())
	var tw := 172.0
	var total := tw * float(n) + 12.0 * float(n - 1)
	UI.place(tabs, (TITLE_BOX.x - total) * 0.5, 110, total, 46)

	var nm := UI.label("", 32, Color("#FFE9A8"), 7)
	nm.name = "PoolName"
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.place(nm, 0, 162, TITLE_BOX.x, 40)
	group.add_child(nm)

	var desc := UI.label("", 18, Color(0.90, 0.93, 1.0, 0.78), 5)
	desc.name = "PoolDesc"
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UI.place(desc, 40, 202, TITLE_BOX.x - 80, 26)
	group.add_child(desc)


func _build_pity_badge(hud: Control) -> void:
	var badge := _mk(hud, UI.panel(Color(0.08, 0.06, 0.12, 0.72), 18, 2, PANEL_BORDER_SOFT, 8),
		"PityBadge")
	UI.place(badge, PITY_BADGE.position.x, PITY_BADGE.position.y,
		PITY_BADGE.size.x, PITY_BADGE.size.y)

	var pairs := [
		["PitySmall", "PitySmallBar", "PitySmallHalf", 0.0],
		["PityLarge", "PityLargeBar", "PityLargeHalf", PITY_BADGE.size.x * 0.5],
	]
	for raw in pairs:
		var p: Array = raw
		var half := Panel.new()
		half.name = str(p[2])
		half.add_theme_stylebox_override("panel", UI.style(Color(0, 0, 0, 0), 14,
			1, Color(1.0, 0.85, 0.45, 0.22)))
		UI.place(half, float(p[3]) + 8.0, 6, PITY_BADGE.size.x * 0.5 - 16.0, PITY_BADGE.size.y - 12.0)
		badge.add_child(half)

		var l := UI.label("--", 19, UI.CREAM, 5)
		l.name = str(p[0])
		UI.place(l, 12, 2, PITY_BADGE.size.x * 0.5 - 40.0, 24)
		half.add_child(l)

		var bar := ProgressBar.new()
		bar.name = str(p[1])
		bar.max_value = 50.0
		bar.value = 0.0
		bar.show_percentage = false
		bar.add_theme_stylebox_override("background", UI.style(Color(0, 0, 0, 0.55), 5))
		bar.add_theme_stylebox_override("fill", UI.style(Color("#FFC94A"), 5))
		UI.place(bar, 12, 28, PITY_BADGE.size.x * 0.5 - 40.0, 10)
		half.add_child(bar)


# ---------------------------------------------------------------- 底部：单抽 / 十连

func _build_pull_buttons(hud: Control) -> void:
	var one := _mk_pull_button("PullOneButton", "召唤 ×1", "SUMMON x1",
		Color("#7BE0FF"), Color("#2A5C74"), false)
	UI.place(one, PULL_ONE.position.x, PULL_ONE.position.y, PULL_ONE.size.x, PULL_ONE.size.y)
	hud.add_child(one)

	var ten := _mk_pull_button("PullTenButton", "召唤 ×10", "SUMMON x10",
		Color("#FFC94A"), Color("#8A5410"), true)
	UI.place(ten, PULL_TEN.position.x, PULL_TEN.position.y, PULL_TEN.size.x, PULL_TEN.size.y)
	hud.add_child(ten)


func _mk_pull_button(node_name: String, text: String, sub: String, accent: Color,
		outline: Color, primary: bool) -> Button:
	var btn := Button.new()
	btn.name = node_name
	btn.text = text
	btn.tooltip_text = sub
	btn.add_theme_font_override("font", load(UI.FONT_MAIN))
	btn.add_theme_font_size_override("font_size", 40 if primary else 36)
	btn.add_theme_color_override("font_color", outline)
	btn.add_theme_color_override("font_hover_color", outline.darkened(0.2))
	btn.add_theme_color_override("font_pressed_color", outline)
	btn.add_theme_constant_override("outline_size", 0)
	btn.add_theme_stylebox_override("normal",
		UI.style(accent, 22, 5, outline, 16, Color(0, 0, 0, 0.45)))
	btn.add_theme_stylebox_override("hover",
		UI.style(accent.lightened(0.12), 22, 5, outline, 22, Color(0, 0, 0, 0.5)))
	btn.add_theme_stylebox_override("pressed",
		UI.style(accent.darkened(0.10), 22, 5, outline, 8, Color(0, 0, 0, 0.45)))
	btn.add_theme_stylebox_override("disabled",
		UI.style(accent.darkened(0.45), 22, 3, outline.darkened(0.3), 0))
	btn.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.45))
	btn.focus_mode = Control.FOCUS_NONE
	_shift_button_text(btn, 20)

	var cost := UI.label("", 22, outline, 4)
	cost.name = "PullOneCost" if node_name == "PullOneButton" else "PullTenCost"
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.place(cost, 0, 74, 340, 30)
	btn.add_child(cost)

	if primary:
		var tag := UI.panel(Color("#FF6B6B"), 12, 2, Color("#7A1F1F"), 8, Color(0, 0, 0, 0.45))
		tag.name = "TenTag"
		UI.place(tag, 200, -16, 158, 36)
		btn.add_child(tag)

		var tl := UI.label(str(_ten_guarantee().get("label", "必得 SR 及以上")), 17,
			Color("#FFF3D6"), 5)
		tl.name = "TenTagLabel"
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		UI.fill(tl)
		tag.add_child(tl)

	return btn


## Button 的自有文字永远垂直居中，靠样式盒的下内边距把它顶上去，
## 给按钮底部的消耗文案让位（否则两行字会叠在一起）。
func _shift_button_text(btn: Button, pad: float) -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := btn.get_theme_stylebox(state)
		if sb is StyleBoxFlat:
			(sb as StyleBoxFlat).content_margin_bottom = pad


# ---------------------------------------------------------------- 右栏：公示 / 商店 / 规则

func _build_right_rail(hud: Control) -> void:
	var rate := UI.text_button("概率公示", 24, Color(0.10, 0.08, 0.14, 0.82),
		Color(1.0, 0.85, 0.45, 0.5), UI.CREAM, 18)
	rate.name = "RateButton"
	UI.place(rate, RATE_BUTTON.position.x, RATE_BUTTON.position.y,
		RATE_BUTTON.size.x, RATE_BUTTON.size.y)
	hud.add_child(rate)

	var shop := Button.new()
	shop.name = "ShopButton"
	shop.tooltip_text = str(_shop().get("subtitle", "WISH CRYSTAL SHOP"))
	shop.add_theme_stylebox_override("normal",
		UI.style(Color(0.12, 0.08, 0.20, 0.85), 18, 2, Color(0.75, 0.55, 1.0, 0.6), 10))
	shop.add_theme_stylebox_override("hover",
		UI.style(Color(0.18, 0.12, 0.28, 0.9), 18, 2, Color(0.85, 0.65, 1.0, 0.8), 14))
	shop.add_theme_stylebox_override("pressed",
		UI.style(Color(0.09, 0.06, 0.16, 0.9), 18, 2, Color(0.75, 0.55, 1.0, 0.6), 6))
	shop.add_theme_stylebox_override("focus", UI.style(Color(0, 0, 0, 0), 18))
	shop.focus_mode = Control.FOCUS_NONE
	UI.place(shop, SHOP_BUTTON.position.x, SHOP_BUTTON.position.y,
		SHOP_BUTTON.size.x, SHOP_BUTTON.size.y)
	hud.add_child(shop)

	var sic := UI.icon(str(_crystal().get("icon", "")), 30.0,
		Color(str(_crystal().get("color", "#C08BFF"))))
	UI.place(sic, 18, 22, 30, 30)
	shop.add_child(sic)

	var sl := UI.label(str(_shop().get("title", "心愿水晶商店")), 22, Color("#F0E6FF"), 5)
	UI.place(sl, 56, 8, 250, 30)
	shop.add_child(sl)

	var sv := UI.label("--", 19, Color("#FFD45E"), 5)
	sv.name = "ShopCrystalLabel"
	UI.place(sv, 56, 40, 250, 26)
	shop.add_child(sv)

	var rule := _mk(hud, UI.panel(PANEL_BG_SOFT, 20, 2, PANEL_BORDER_SOFT, 10), "RulePanel")
	UI.place(rule, RULE_PANEL.position.x, RULE_PANEL.position.y,
		RULE_PANEL.size.x, RULE_PANEL.size.y)

	var rt := UI.label("卡池规则", 22, Color("#FFD98A"), 5)
	UI.place(rt, 18, 10, 200, 30)
	rule.add_child(rt)

	var body := UI.label("", 17, Color(0.92, 0.94, 1.0, 0.82), 4)
	body.name = "RuleBody"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	UI.place(body, 18, 46, RULE_PANEL.size.x - 36, RULE_PANEL.size.y - 60)
	rule.add_child(body)


# ---------------------------------------------------------------- 返回 / 提示 / 页脚

func _build_back_button(hud: Control) -> void:
	var cfg: Dictionary = _gacha().get("back_button", {})
	var btn := UI.text_button("◀  " + str(cfg.get("text", "返回主界面")), 25,
		Color(0.10, 0.08, 0.14, 0.80), Color(1.0, 0.85, 0.45, 0.5), UI.CREAM, 18)
	btn.name = "BackButton"
	UI.place(btn, BACK_BUTTON.position.x, BACK_BUTTON.position.y,
		BACK_BUTTON.size.x, BACK_BUTTON.size.y)
	_mk(hud, btn, "BackButton", true)


func _build_toast(hud: Control) -> void:
	var toast := _mk(hud, UI.panel(Color(0.09, 0.07, 0.13, 0.92), 20, 2,
		Color(1.0, 0.85, 0.45, 0.5), 12), "Toast")
	UI.place(toast, TOAST.position.x, TOAST.position.y, TOAST.size.x, TOAST.size.y)
	toast.visible = false

	var l := UI.label("", 20, UI.CREAM, 6)
	l.name = "ToastLabel"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UI.fill(l)
	l.offset_left = 16
	l.offset_right = -16
	toast.add_child(l)


func _build_footer(hud: Control) -> void:
	var info := UI.label("", 18, Color(1, 1, 1, 0.78), 5)
	info.name = "FooterInfo"
	info.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	UI.place(info, 300, 1032, 900, 24)
	_mk(hud, info, "FooterInfo", true)

	var stat := UI.label("", 18, Color(1, 1, 1, 0.6), 5)
	stat.name = "FooterStat"
	stat.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stat.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	UI.place(stat, 1560, 1032, 340, 24)
	_mk(hud, stat, "FooterStat", true)


# ---------------------------------------------------------------- 白闪（撕包时的散射光）

func _build_flash(hud: Control) -> void:
	var flash := ColorRect.new()
	flash.name = "FlashRect"
	flash.color = Color(1.0, 0.96, 0.84, 0.0)
	UI.fill(flash)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.visible = false
	_mk(hud, flash, "FlashRect", true)


# ---------------------------------------------------------------- 结算展示层

func _build_reveal_layer(hud: Control) -> void:
	var layer := _mk(hud, Control.new(), "RevealLayer")
	UI.fill(layer)
	layer.visible = false

	var back := _mk(layer, ColorRect.new(), "RevealBackdrop")
	back.color = Color(0.03, 0.02, 0.06, 0.94)
	UI.fill(back)

	# 顶层压暗：结果层要盖住底下的界面标题与按钮，别让它们透上来抢戏
	var vignette := UI.gradient_rect(Color(0.02, 0.01, 0.04, 0.85), Color(0.02, 0.01, 0.04, 0.0), true)
	UI.place(vignette, 0, 0, 1920, 300)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(vignette)
	var vignette2 := UI.gradient_rect(Color(0.02, 0.01, 0.04, 0.0), Color(0.02, 0.01, 0.04, 0.85), true)
	UI.place(vignette2, 0, 780, 1920, 300)
	vignette2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(vignette2)

	# 光柱：中间一条实心柱 + 两侧渐隐边，SSR 紫、UR 彩虹（颜色由界面脚本刷）
	var pillar := _mk(layer, Control.new(), "LightPillar")
	UI.place(pillar, 960 - 190.0, -40.0, 380, 1160)
	pillar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var fringe := UI.glow_rect(Color.WHITE, 0.28)
	fringe.name = "PillarFringe"
	UI.place(fringe, 0, 0, 380, 1160)
	pillar.add_child(fringe)

	for i in 5:
		var strip := UI.gradient_rect(Color.WHITE, Color(1, 1, 1, 0), false)
		strip.name = "Strip%d" % i
		strip.modulate = Color(1, 1, 1, 0.0)
		UI.place(strip, 40.0 + float(i) * 60.0, 0, 72, 1160)
		pillar.add_child(strip)

	var core := UI.gradient_rect(Color(1, 1, 1, 0.95), Color(1, 1, 1, 0.05), true)
	core.name = "PillarCore"
	UI.place(core, 176, 0, 28, 1160)
	pillar.add_child(core)

	var base := UI.glow_rect(Color.WHITE, 0.55)
	base.name = "PillarBase"
	UI.place(base, 560, 860, 800, 320)
	layer.add_child(base)

	var cards := _mk(layer, Control.new(), "RevealCards")
	UI.fill(cards)
	cards.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var title: Control = UI.label_shadow("召唤结果", 52, Color("#FFE9A8"), 12,
		Color("#6B3A16"), Vector2(0, 5), Color("#3A1B05"), Vector2(700, 64))
	title.name = "RevealTitle"
	UI.anchor_top_center(title, 700, 64, 40)
	layer.add_child(title)

	var sub := UI.label("", 24, Color("#FFD98A"), 7, Color(0.28, 0.14, 0.03, 0.85))
	sub.name = "RevealSub"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.anchor_top_center(sub, 900, 30, 112)
	layer.add_child(sub)

	var summary := UI.label("", 21, Color(0.95, 0.96, 1.0, 0.9), 5)
	summary.name = "RevealSummary"
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.place(summary, 460, 852, 1000, 30)
	layer.add_child(summary)

	var skip := UI.text_button("跳过", 22, Color(0.10, 0.08, 0.14, 0.85),
		Color(1, 1, 1, 0.35), UI.CREAM, 16)
	skip.name = "RevealSkipButton"
	UI.place(skip, 1690, 36, 190, 54)
	layer.add_child(skip)

	var again := UI.text_button("再抽一次", 26, Color(0.13, 0.10, 0.18, 0.88),
		Color(1.0, 0.85, 0.45, 0.55), UI.CREAM, 18)
	again.name = "RevealAgainButton"
	UI.place(again, 600, 900, 340, 76)
	layer.add_child(again)

	var close := UI.text_button("确定", 30, Color("#FFC94A"), Color("#B8791F"),
		Color("#4A2408"), 20)
	close.name = "RevealCloseButton"
	UI.place(close, 980, 900, 340, 76)
	layer.add_child(close)

	_mark_unique_recursive(layer)


# ---------------------------------------------------------------- 弹层：公示 / 商店

func _build_popups(hud: Control) -> void:
	var layer := _mk(hud, Control.new(), "PopupLayer")
	UI.fill(layer)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# ---- 概率公示 ----
	var rp := _mk(layer, UI.panel(Color(0.06, 0.05, 0.10, 0.98), 24, 3, PANEL_BORDER, 22), "RatePanel")
	UI.place(rp, RATE_PANEL.position.x, RATE_PANEL.position.y,
		RATE_PANEL.size.x, RATE_PANEL.size.y)
	rp.visible = false

	var rt := UI.label("概率公示", 32, Color("#FFD98A"), 7)
	rt.name = "RateTitle"
	UI.place(rt, 28, 16, 400, 42)
	rp.add_child(rt)

	var rhint := UI.label("", 19, Color(1, 1, 1, 0.6), 4)
	rhint.name = "RatePoolName"
	rhint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UI.place(rhint, RATE_PANEL.size.x - 428, 24, 400, 30)
	rp.add_child(rhint)

	var rb := _mk(rp, VBoxContainer.new(), "RateBody")
	rb.add_theme_constant_override("separation", 8)
	UI.place(rb, 28, 70, RATE_PANEL.size.x - 56, RATE_PANEL.size.y - 148)

	var rc := UI.text_button("关闭", 24, Color(0.13, 0.10, 0.18, 0.9),
		Color(1, 1, 1, 0.3), UI.CREAM, 18)
	rc.name = "RateCloseButton"
	UI.place(rc, RATE_PANEL.size.x - 200.0, RATE_PANEL.size.y - 74.0, 172, 54)
	rp.add_child(rc)

	# ---- 心愿水晶商店 ----
	var sp := _mk(layer, UI.panel(Color(0.07, 0.05, 0.12, 0.98), 24, 3,
		Color(0.78, 0.58, 1.0, 0.6), 22), "ShopPanel")
	UI.place(sp, SHOP_PANEL.position.x, SHOP_PANEL.position.y,
		SHOP_PANEL.size.x, SHOP_PANEL.size.y)
	sp.visible = false

	var st := UI.label(str(_shop().get("title", "心愿水晶商店")), 32, Color("#F0E6FF"), 7)
	st.name = "ShopTitle"
	UI.place(st, 28, 16, 500, 42)
	sp.add_child(st)

	var shint := UI.label(str(_shop().get("hint", "")), 18, Color(1, 1, 1, 0.6), 4)
	shint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UI.place(shint, 28, 62, SHOP_PANEL.size.x - 56, 26)
	sp.add_child(shint)

	var scy := UI.label("", 22, Color("#FFD45E"), 6)
	scy.name = "ShopBalanceLabel"
	scy.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UI.place(scy, SHOP_PANEL.size.x - 428, 22, 400, 30)
	sp.add_child(scy)

	var sb := _mk(sp, VBoxContainer.new(), "ShopBody")
	sb.add_theme_constant_override("separation", 8)
	UI.place(sb, 28, 100, SHOP_PANEL.size.x - 56, SHOP_PANEL.size.y - 180)

	var sc := UI.text_button("关闭", 24, Color(0.13, 0.10, 0.18, 0.9),
		Color(1, 1, 1, 0.3), UI.CREAM, 18)
	sc.name = "ShopCloseButton"
	UI.place(sc, SHOP_PANEL.size.x - 200.0, SHOP_PANEL.size.y - 74.0, 172, 54)
	sp.add_child(sc)

	_mark_unique_recursive(layer)


# ---------------------------------------------------------------- 弹层内容（构造期预览用）

func _mark_unique_recursive(node: Node) -> void:
	if str(node.name) in UNIQUE_NAMES:
		node.unique_name_in_owner = true
	for c in node.get_children():
		_mark_unique_recursive(c)


# ---------------------------------------------------------------- 工具

## 上下半张卡包：只圆外侧的两个角
func _half_style(bg: Color, border: Color, top_half: bool) -> StyleBoxFlat:
	var sb := UI.style(bg, 0, 3, border, 14, Color(0, 0, 0, 0.5))
	var r := 22
	sb.corner_radius_top_left = r if top_half else 6
	sb.corner_radius_top_right = r if top_half else 6
	sb.corner_radius_bottom_left = 6 if top_half else r
	sb.corner_radius_bottom_right = 6 if top_half else r
	return sb


func _ellipse_style(bg: Color, border: Color, w: int) -> StyleBoxFlat:
	var sb := UI.style(bg, 0, w, border, 10, Color(0, 0, 0, 0.42))
	sb.set_corner_radius_all(120)
	return sb


func _mk_particles(parent: Node, node_name: String, color: Color, amount: int, radius: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.name = node_name
	p.amount = amount
	p.lifetime = 2.6
	p.preprocess = 1.2
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius
	p.gravity = Vector2(0, -26)
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 20.0
	# 粒子贴图是 256×256 的径向渐变，缩放必须往小里给，
	# 否则一颗就是 256px 的大光斑（整片糊成一块黄饼）。
	p.scale_amount_min = 0.02
	p.scale_amount_max = 0.075
	p.color = color
	p.texture = UI.radial_tex(Color(1, 1, 1, 1), Color(1, 1, 1, 0))
	parent.add_child(p)
	p.owner = _root
	return p


func _mk(parent: Node, node: Node, name: String, unique: bool = false) -> Node:
	node.name = name
	parent.add_child(node)
	node.owner = _root
	if unique:
		(node as Node).unique_name_in_owner = true
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


func _gacha() -> Dictionary:
	return _section("gacha")


func _menu() -> Dictionary:
	return _section("menu")


func _shop() -> Dictionary:
	var v: Variant = _gacha().get("shop", {})
	return v if v is Dictionary else {}


func _crystal() -> Dictionary:
	var v: Variant = _gacha().get("crystal", {})
	return v if v is Dictionary else {}


func _ten_guarantee() -> Dictionary:
	var v: Variant = _gacha().get("ten_guarantee", {})
	return v if v is Dictionary else {}


func _pools() -> Array:
	var v: Variant = _gacha().get("pools", [])
	return v if v is Array else []


func _player() -> Dictionary:
	return _menu().get("player", {})


func _player_avatar() -> String:
	return str(_player().get("avatar", "res://assets/art/characters/char_knight.png"))
