extends SceneTree
## build_battle.gd —— 程序化构建「战斗」场景
##
## 用法（headless）：
##   Godot --headless --path <项目> --script res://tools/build_battle.gd
##
## 产出：res://scenes/battle.tscn
##
## 与 build_main_menu.gd / build_stage_select.gd 同一套约定：
##   1. 不依赖任何 autoload（--script 模式下 autoload 全局名不可见），配置直接读 JSON；
##   2. 静态布局用「锚点 + 偏移」写死；动态内容（战场单位、格子、战报行、队伍卡）
##      只留空容器，运行时由 battle.gd 按关卡配置填充；
##   3. 文案能取自配置就不写死（关卡编号 / 名称 / 机制说明 / 结算按钮）。
##
## 布局分区（1920x1080）：
##   顶部信息条 0-108 ｜ 营 我方队伍 24-324 ｜ 战场 400-1340 ｜ 战报 1344-1896
##   战场只占中间一条：两侧面板把「选哪一关、打得怎么样」和「发生了什么」分开放，
##   单位立绘不会被面板压住，也不会盖住战报。

const UI := preload("res://tools/ui_kit.gd")

const BATTLE_SCRIPT_PATH := "res://scripts/battle.gd"
const DATA_PATH := "res://data/game_data.json"
const OUT_PATH := "res://scenes/battle.tscn"
const BASE := Vector2(1920, 1080)

const UNIQUE_NAMES := [
	"Background", "TopBar", "StageNo", "StageName", "StageKind", "PowerMine", "PowerRec",
	"CellLayer", "UnitLayer", "PlateLayer", "FloatLayer",
	"TeamTitle", "TeamBox", "InfoTitle", "InfoBody",
	"LogTitle", "LogScroll", "LogBox",
	"TurnLabel", "AllyCount", "EnemyCount",
	"OrderStrip", "OrderTitle", "OrderLayer",
	"SpeedButton", "PauseButton", "SkipButton", "RetreatButton", "HintLabel", "EnvLabel",
	"ResultPanel", "ResultTitle", "ResultSub", "ResultRewardBox", "ResultRetry", "ResultClose",
	"Toast", "ToastLabel", "FooterInfo",
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


func _build() -> void:
	_root = Control.new()
	_root.name = "Battle"
	var script: Script = load(BATTLE_SCRIPT_PATH)
	if script == null:
		push_error("[build] 无法加载 %s" % BATTLE_SCRIPT_PATH)
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

	var bg := _mk(_root, Control.new(), "Background")
	UI.fill(bg)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var hud := _mk(_root, Control.new(), "Hud")
	UI.fill(hud)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 绘制顺序 = 战场从下往上：格子 -> 立绘 -> 名牌血条 -> 飘字
	# 名牌单独一层是必须的：2.5D 棋盘上后排单位的血条一定会被前一排的立绘压住，
	# 拆到独立图层后，「谁还剩多少血」永远读得到。
	var cells := _mk(_root, Control.new(), "CellLayer")
	UI.fill(cells)
	cells.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var units := _mk(_root, Control.new(), "UnitLayer")
	UI.fill(units)
	units.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var plates := _mk(_root, Control.new(), "PlateLayer")
	UI.fill(plates)
	plates.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var floats := _mk(_root, Control.new(), "FloatLayer")
	UI.fill(floats)
	floats.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var overlay := _mk(_root, Control.new(), "Overlay")
	UI.fill(overlay)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_build_top_bar(overlay)
	_build_team_panel(overlay)
	_build_info_panel(overlay)
	_build_log_panel(overlay)
	_build_status_panel(overlay)
	_build_order_strip(overlay)
	_build_result_panel(overlay)
	_build_footer(overlay)
	_build_toast(overlay)

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


# ---------------------------------------------------------------- 顶部信息条

func _build_top_bar(hud: Control) -> void:
	var bar := _mk(hud, UI.panel(Color(0.06, 0.05, 0.10, 0.80), 0, 0, Color(0, 0, 0, 0), 12), "TopBar")
	UI.anchor_top_left(bar, 0, 0, BASE.x, 108)
	var line := ColorRect.new()
	line.color = Color(1.0, 0.85, 0.45, 0.5)
	UI.place(line, 0, 106, BASE.x, 2)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(line)

	var pill := UI.panel(UI.GOLD, 16, 2, UI.GOLD_DEEP)
	UI.place(pill, 26, 30, 108, 48)
	bar.add_child(pill)
	var no := UI.label("----", 28, UI.INK, 0)
	no.name = "StageNo"
	no.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	no.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UI.fill(no)
	pill.add_child(no)

	var nm := UI.label("", 46, UI.CREAM, 8, Color("#4A2408"))
	nm.name = "StageName"
	UI.place(nm, 152, 14, 640, 62)
	bar.add_child(nm)

	var kind := UI.label("", 22, Color("#FFD98A"), 6)
	kind.name = "StageKind"
	UI.place(kind, 156, 74, 640, 28)
	bar.add_child(kind)

	var mine := UI.label("", 28, Color("#EAF4FF"), 6)
	mine.name = "PowerMine"
	mine.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UI.anchor_top_right(mine, 26, 22, 620, 36)
	bar.add_child(mine)

	var rec := UI.label("", 21, Color(0.88, 0.92, 0.98, 0.78), 5)
	rec.name = "PowerRec"
	rec.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UI.anchor_top_right(rec, 26, 66, 620, 30)
	bar.add_child(rec)


# ---------------------------------------------------------------- 左侧：我方队伍

func _build_team_panel(hud: Control) -> void:
	var panel := _mk(hud, UI.panel(Color(0.06, 0.05, 0.10, 0.74), 20, 2,
		Color(0.42, 0.72, 1.0, 0.42), 10), "TeamPanel")
	UI.anchor_top_left(panel, 24, 140, 300, 668)

	var title := UI.label("我方队伍", 25, Color("#BFE3FF"), 6)
	title.name = "TeamTitle"
	UI.place(title, 18, 12, 264, 34)
	panel.add_child(title)

	var box := VBoxContainer.new()
	box.name = "TeamBox"
	box.add_theme_constant_override("separation", 12)
	UI.place(box, 12, 54, 276, 600)
	panel.add_child(box)


# ---------------------------------------------------------------- 左下：关卡机制 / 单位详情

## 一块面板两种用途：默认显示关卡机制（策划表原文），
## 点场上单位则切成该单位的详情（属性 + 技能描述），点空白回到机制。
func _build_info_panel(hud: Control) -> void:
	var panel := _mk(hud, UI.panel(Color(0.06, 0.05, 0.10, 0.74), 20, 2,
		Color(1.0, 0.85, 0.45, 0.40), 10), "InfoPanel")
	UI.anchor_top_left(panel, 24, 820, 300, 180)

	var title := UI.label("关卡机制", 23, Color("#FFD98A"), 6)
	title.name = "InfoTitle"
	UI.place(title, 18, 10, 264, 30)
	panel.add_child(title)

	var body := UI.label("", 18, Color(0.92, 0.94, 0.98, 0.86), 5)
	body.name = "InfoBody"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	UI.place(body, 16, 46, 268, 124)
	panel.add_child(body)


# ---------------------------------------------------------------- 右侧：战报

func _build_log_panel(hud: Control) -> void:
	var panel := _mk(hud, UI.panel(Color(0.06, 0.05, 0.10, 0.74), 20, 2,
		Color(1.0, 0.85, 0.45, 0.40), 10), "LogPanel")
	UI.anchor_top_left(panel, 1344, 140, 552, 596)

	var title := UI.label("战报", 25, Color("#FFD98A"), 6)
	title.name = "LogTitle"
	UI.place(title, 18, 12, 200, 34)
	panel.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.name = "LogScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	UI.place(scroll, 14, 54, 524, 528)
	panel.add_child(scroll)

	var box := VBoxContainer.new()
	box.name = "LogBox"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)


# ---------------------------------------------------------------- 右下：状态与控制

func _build_status_panel(hud: Control) -> void:
	var panel := _mk(hud, UI.panel(Color(0.06, 0.05, 0.10, 0.78), 20, 2,
		Color(1.0, 0.85, 0.45, 0.40), 10), "StatusPanel")
	UI.anchor_top_left(panel, 1344, 748, 552, 252)

	var turn := UI.label("第 0 拍", 22, UI.CREAM, 5)
	turn.name = "TurnLabel"
	UI.place(turn, 20, 14, 160, 30)
	panel.add_child(turn)

	var ally := UI.label("我方 0/0", 22, Color("#9BE0FF"), 5)
	ally.name = "AllyCount"
	ally.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.place(ally, 186, 14, 180, 30)
	panel.add_child(ally)

	var enemy := UI.label("敌方 0/0", 22, Color("#FFB0A0"), 5)
	enemy.name = "EnemyCount"
	enemy.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UI.place(enemy, 372, 14, 160, 30)
	panel.add_child(enemy)

	var w := 126.0
	var gap := 16.0
	var labels := [
		["SpeedButton", "速度 1×"], ["PauseButton", "暂停"],
		["SkipButton", "跳过"], ["RetreatButton", "撤退"],
	]
	for i in labels.size():
		var nm := str(labels[i][0])
		var b := UI.text_button(str(labels[i][1]), 24,
			Color(0.13, 0.11, 0.18, 0.92), Color(1.0, 0.85, 0.45, 0.55), UI.CREAM, 16)
		b.name = nm
		UI.place(b, 20.0 + float(i) * (w + gap), 56, w, 76)
		panel.add_child(b)

	var hint := UI.label("点击场上单位可看详情；点空白恢复关卡机制", 17,
		Color(0.90, 0.93, 0.98, 0.66), 5)
	hint.name = "HintLabel"
	UI.place(hint, 20, 146, 512, 26)
	panel.add_child(hint)

	var env := UI.label("", 17, Color("#FFE0A0"), 5)
	env.name = "EnvLabel"
	env.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UI.place(env, 20, 176, 512, 60)
	panel.add_child(env)


# ---------------------------------------------------------------- 底部中间：行动顺序

## ATB 战斗里「接下来谁先动」是玩家最需要盯着的信息，
## 单独拉一条带子放在战场正下方，而不是塞进角落里。
func _build_order_strip(hud: Control) -> void:
	var panel := _mk(hud, UI.panel(Color(0.06, 0.05, 0.10, 0.72), 20, 2,
		Color(0.42, 0.72, 1.0, 0.35), 10), "OrderStrip")
	UI.anchor_top_left(panel, 400, 996, 940, 78)

	var title := UI.label("行动顺序", 20, Color("#BFE3FF"), 5)
	title.name = "OrderTitle"
	UI.place(title, 16, 24, 110, 30)
	panel.add_child(title)

	var layer := HBoxContainer.new()
	layer.name = "OrderLayer"
	layer.add_theme_constant_override("separation", 10)
	UI.place(layer, 132, 8, 792, 62)
	panel.add_child(layer)


# ---------------------------------------------------------------- 结算

## 结算面板：从上到下 = 标题 → 一句话战报 → 星级评分行 + 战利品 / 物资统计 → 按钮。
## 奖励区留 500 高，是因为星级行（96）与「持有 N」副行会把内容撑高，
## 只按 3 条奖励算高度的话，1010 那种带首通奖励的关会把按钮挤掉。
func _build_result_panel(hud: Control) -> void:
	var panel := _mk(hud, UI.panel(Color(0.07, 0.06, 0.11, 0.95), 28, 3,
		Color(1.0, 0.85, 0.45, 0.6), 18), "ResultPanel")
	UI.place(panel, 560, 140, 800, 790)
	panel.visible = false

	var title := UI.label("", 64, Color("#FFE9A8"), 14, Color("#6B3A16"))
	title.name = "ResultTitle"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.place(title, 20, 26, 760, 80)
	panel.add_child(title)

	var sub := UI.label("", 22, Color(0.92, 0.94, 0.98, 0.85), 5)
	sub.name = "ResultSub"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.place(sub, 20, 108, 760, 28)
	panel.add_child(sub)

	var box := VBoxContainer.new()
	box.name = "ResultRewardBox"
	box.add_theme_constant_override("separation", 10)
	UI.place(box, 160, 146, 480, 500)
	panel.add_child(box)

	var retry := UI.text_button("再次挑战", 30, Color("#FFC94A"), Color("#B8791F"),
		Color("#4A2408"), 22)
	retry.name = "ResultRetry"
	UI.place(retry, 170, 662, 210, 84)
	panel.add_child(retry)

	var close := UI.text_button("返回选关", 30, Color(0.16, 0.13, 0.22, 0.95),
		Color(1.0, 0.85, 0.45, 0.6), UI.CREAM, 22)
	close.name = "ResultClose"
	UI.place(close, 420, 662, 210, 84)
	panel.add_child(close)


# ---------------------------------------------------------------- 底部状态与提示

func _build_footer(hud: Control) -> void:
	var info := UI.label("", 17, Color(1, 1, 1, 0.82), 5)
	info.name = "FooterInfo"
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	info.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	UI.anchor_top_left(info, 1344, 1006, 552, 30)
	_mk(hud, info, "FooterInfo", true)


func _build_toast(hud: Control) -> void:
	var toast := _mk(hud, UI.panel(Color(0.08, 0.06, 0.12, 0.90), 20, 2,
		Color(1.0, 0.85, 0.45, 0.5), 12), "Toast")
	UI.anchor_top_center(toast, 720, 76, 124)
	toast.visible = false

	var l := UI.label("", 22, UI.CREAM, 6)
	l.name = "ToastLabel"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UI.fill(l)
	l.offset_left = 16
	l.offset_right = -16
	toast.add_child(l)


# ---------------------------------------------------------------- 工具

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
