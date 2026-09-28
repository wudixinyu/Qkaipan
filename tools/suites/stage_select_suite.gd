extends RefCounted
## stage_select_suite.gd —— 冒险关卡选择页冒烟测试
##
## 由 tools/smoke_stage_select.gd 在第一帧之后动态 load()。
##
## 覆盖：场景骨架与唯一名、UI 脚本是否真的挂上（解析失败会静默退回静态骨架）、
##       关卡节点按配置锚点落位、引导线段数、标签行序、星数与角标、
##       默认选中态、队伍面板，以及「选中 → 进入关卡 → 校验体力 → 交接给编队页」的闭环。

var passed := 0
var failed := 0

## 与 scripts/stage_select.gd 的 NODE_BOX / ANCHOR_IN_BOX 对应：
## 节点按钮以「盒内 (150, 150)」对准配置锚点，锚点即该关浮岛在背景里的中心
const ANCHOR_IN_BOX := Vector2(150, 150)
const LABEL_LH := 44.0

var _tree: SceneTree
var _scene: Node

## 用例会把体力打空再填满，并写 user:// 存档；先留底，结尾还原
const SAVE_PATH := "user://save.json"
var _save_backup := ""
var _had_save := false


func run(tree: SceneTree) -> Dictionary:
	_tree = tree
	print("\n========== 卡牌大冒险 · 冒险关卡选择页冒烟 ==========")

	# 让测试可重复：回到默认存档与满体力，避免上一次运行的残留污染断言
	_backup_save()
	SaveDB.reset_profile()
	StaminaSys.fill()

	_check_skeleton()
	_check_background()
	_check_map_nodes()
	_check_guides()
	_check_labels_and_stars()
	_check_sync_stats()
	_check_selection()
	_check_team()
	_check_interact()
	print("\n---------- 结果：通过 %d / 失败 %d ----------" % [passed, failed])
	_restore_save()
	return { "passed": passed, "failed": failed }


func _backup_save() -> void:
	_had_save = FileAccess.file_exists(SAVE_PATH)
	if not _had_save:
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f != null:
		_save_backup = f.get_as_text()
		f.close()


func _restore_save() -> void:
	if not _had_save:
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(_save_backup)
		f.close()
		print("[smoke] 已还原测试前的存档")


func _ok(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  [PASS] %s%s" % [label, ("  " + detail) if detail != "" else ""])
	else:
		failed += 1
		print("  [FAIL] %s%s" % [label, ("  " + detail) if detail != "" else ""])


func _eq(label: String, got, want) -> void:
	_ok(label, got == want, "got=%s want=%s" % [str(got), str(want)])


# ---------------------------------------------------------------- 骨架

func _check_skeleton() -> void:
	print("\n· 场景骨架")
	var ps: PackedScene = load("res://scenes/stage_select.tscn")
	_ok("场景可加载", ps != null)
	if ps == null:
		return

	_scene = ps.instantiate()
	_ok("场景根节点为 Control", _scene is Control, str(_scene.get_class()))
	_tree.root.add_child(_scene)

	# 陷阱：UI 脚本解析失败时，场景会静默退回静态骨架（动态节点为 0、图标全无），
	# 控制台只有一行 Parse Error。先确认脚本真的挂上了。
	var scr: Script = _scene.get_script()
	_ok("根节点已挂脚本", scr != null)
	if scr != null:
		_ok("挂的是 stage_select.gd", str(scr.resource_path).ends_with("stage_select.gd"),
			str(scr.resource_path))

	for u in ["NodeLayer", "GuideLayer", "DecorLayer", "TeamSlots", "TeamLabel",
			"EnterButton", "EnterSub", "BackButton", "Toast", "ToastLabel",
			"FooterInfo", "StaminaValue", "PlayerName"]:
		_ok("唯一名 %%%s 可解析" % u, _scene.get_node_or_null("%%%s" % u) != null)


# ---------------------------------------------------------------- 背景

## 选关页背景 = 概念稿底图，节点锚点就是按这张图的浮岛位置量出来的。
## 一旦背景被换回 bg_islands.png 或别的图，锚点就全错位了，所以这里钉死。
func _check_background() -> void:
	print("\n· 背景底图")
	var bg: TextureRect = _scene.get_node_or_null("Background")
	_ok("Background 存在", bg != null)
	if bg == null:
		return
	var tex := bg.texture
	_ok("背景纹理已加载", tex != null)
	if tex == null:
		return
	_ok("用的是选关页专用底图",
		str(tex.resource_path).ends_with("bg_stage_select.png"), str(tex.resource_path))
	_ok("已预处理成 1920x1080，运行时 1:1 无缩放",
		tex.get_width() == 1920 and tex.get_height() == 1080,
		"%dx%d" % [tex.get_width(), tex.get_height()])
	_eq("铺满模式为 cover",
		bg.stretch_mode, TextureRect.STRETCH_KEEP_ASPECT_COVERED)


# ---------------------------------------------------------------- 节点落位

func _check_map_nodes() -> void:
	print("\n· 关卡节点落位")
	var layer: Control = _scene.get_node_or_null("%NodeLayer")
	_ok("NodeLayer 存在", layer != null)
	if layer == null:
		return

	var nodes: Array = GameDB.stage_nodes()
	_eq("实例化节点数 = 配置节点数", layer.get_child_count(), nodes.size())

	var with_icon := 0
	for raw in nodes:
		var cfg: Dictionary = raw
		var sid := int(cfg.get("stage_id", 0))
		var btn := _node(sid)
		_ok("节点 #%d 已实例化" % sid, btn != null)
		if btn == null:
			continue

		var anchor := GameDB.stage_node_pos(sid)
		var got := btn.position + ANCHOR_IN_BOX
		_ok("节点 #%d 锚点与配置一致" % sid, got.distance_to(anchor) < 0.5,
			"got=(%.0f,%.0f) want=(%.0f,%.0f)" % [got.x, got.y, anchor.x, anchor.y])
		_ok("节点 #%d 落在视口内" % sid,
			anchor.x > 0.0 and anchor.x < 1920.0 and anchor.y > 0.0 and anchor.y < 1080.0,
			"anchor=(%.0f,%.0f)" % [anchor.x, anchor.y])
		# 锚点是按背景里浮岛的位置定的，越界说明又跑回概念稿的旧坐标了
		_ok("节点 #%d 锚点落在 1920x1080 的浮岛区" % sid,
			anchor.x > 400.0 and anchor.x < 1500.0 and anchor.y > 250.0 and anchor.y < 900.0,
			"anchor=(%.0f,%.0f)" % [anchor.x, anchor.y])

		# pivot 必须落在锚点上，否则选中放大 / 入场缩放的锚点会漂
		_ok("节点 #%d 缩放中心在锚点上" % sid,
			btn.pivot_offset.distance_to(ANCHOR_IN_BOX) < 0.5,
			"pivot=(%.0f,%.0f)" % [btn.pivot_offset.x, btn.pivot_offset.y])

		# 叠加图标是可选的：icon 为空表示该关浮岛由背景自带，不该再叠一层
		var isle: TextureRect = btn.get_node_or_null("IsleIcon")
		var icon_path := str(cfg.get("icon", ""))
		if icon_path == "":
			_ok("节点 #%d 不叠加图标（浮岛由背景自带）" % sid, isle == null)
		else:
			with_icon += 1
			_ok("节点 #%d 叠加图标已加载" % sid, isle != null and isle.texture != null,
				icon_path)

		# 标签不再用色块底衬，可读性靠描边撑
		_ok("节点 #%d 标签无底衬" % sid, btn.get_node_or_null("LabelPlate") == null)
		var la: Label = btn.get_node_or_null("LabelA")
		_ok("节点 #%d 标签带描边" % sid,
			la != null and la.get_theme_constant("outline_size") > 0)

		# 标签纵向落点由该节点自己的 label_dy 决定，三个值各不相同
		if la != null:
			var want_y := ANCHOR_IN_BOX.y + float(cfg.get("label_dy", 56))
			var got_y := la.position.y + la.size.y * 0.5
			_ok("节点 #%d 首行标签落在 label_dy" % sid, absf(got_y - want_y) < 1.5,
				"got=%.1f want=%.1f" % [got_y, want_y])

		_ok("节点 #%d 层级 z 与配置一致" % sid,
			btn.z_index == int(cfg.get("z", 1)),
			"z=%d" % btn.z_index)

	# 两种情形都要有：既有靠背景的，也有需要补图标的。
	# 否则一旦配置被批量改成空 icon，上面那些断言会"全部通过"却什么都没验。
	_ok("既有关卡靠背景浮岛", with_icon < nodes.size(), "叠加图标 %d / 共 %d" % [with_icon, nodes.size()])
	_ok("也有关卡需要叠加图标", with_icon > 0, "%d 个" % with_icon)

	for i in nodes.size():
		for j in range(i + 1, nodes.size()):
			var a: Dictionary = nodes[i]
			var b: Dictionary = nodes[j]
			var sid_a := int(a.get("stage_id", 0))
			var sid_b := int(b.get("stage_id", 0))
			var d := GameDB.stage_node_pos(sid_a).distance_to(GameDB.stage_node_pos(sid_b))
			_ok("节点 %d 与 %d 浮岛不重叠" % [sid_a, sid_b], d >= 200.0, "锚点距离 %.0fpx" % d)


# ---------------------------------------------------------------- 引导线

func _check_guides() -> void:
	print("\n· 引导线")
	var layer: Control = _scene.get_node_or_null("%GuideLayer")
	_ok("GuideLayer 存在", layer != null)
	if layer == null:
		return

	var links: Array = GameDB.stage_links()
	_eq("线节点数 = 链路数 × 4 层", layer.get_child_count(), links.size() * 4)
	for child in layer.get_children():
		var ln := child as Line2D
		_ok("引导线 %s 是 Line2D" % str(child.name), ln != null)
		if ln != null:
			_ok("引导线 %s 有两个端点" % str(child.name), ln.points.size() == 2,
				"pts=%d" % ln.points.size())

	# 端点不是节点中心，而是「中心沿连线方向收回 radius」——
	# 概念稿里的引导线只是两座浮岛之间露出来的一小段，不收会横穿城堡和关卡名。
	for raw in links:
		var pair: Array = raw
		var a := int(pair[0])
		var b := int(pair[1])
		var pa := GameDB.stage_node_pos(a)
		var pb := GameDB.stage_node_pos(b)
		var dir := (pb - pa).normalized()
		var expect_a := pa + dir * float(GameDB.stage_node(a).get("radius", 110))
		var expect_b := pb - dir * float(GameDB.stage_node(b).get("radius", 90))

		var hit := false
		for child in layer.get_children():
			var ln := child as Line2D
			if ln != null and ln.points.size() == 2 \
					and ln.points[0].distance_to(expect_a) < 1.0 \
					and ln.points[1].distance_to(expect_b) < 1.0:
				hit = true
				break
		_ok("引导线 %d→%d 两端按 radius 收回" % [a, b], hit,
			"want (%.0f,%.0f)→(%.0f,%.0f)" % [expect_a.x, expect_a.y, expect_b.x, expect_b.y])

		var visible := expect_a.distance_to(expect_b)
		_ok("引导线 %d→%d 是可见的一小段" % [a, b],
			visible >= 24.0 and visible < 260.0, "可见长度 %.0fpx" % visible)

	var decor: Control = _scene.get_node_or_null("%DecorLayer")
	_ok("DecorLayer 存在（预留容器）", decor != null)
	if decor != null:
		_eq("装饰岛暂不渲染（背景自带浮岛美术）", decor.get_child_count(), 0)
	_ok("装饰岛配置仍保留", GameDB.decor_islands().size() >= 3)


# ---------------------------------------------------------------- 标签与星数

func _check_labels_and_stars() -> void:
	print("\n· 标签行序与星数")
	_ok("1001 名称行在上", _label_a(_node(1001)) == "初始之地", _label_a(_node(1001)))
	_ok("1001 等级行在下", _label_b(_node(1001)) == "1级 1001", _label_b(_node(1001)))
	_ok("1003 名称行在上", _label_a(_node(1003)) == "云端城堡", _label_a(_node(1003)))
	_ok("1003 等级行在下", _label_b(_node(1003)) == "1级 1003", _label_b(_node(1003)))
	# 参考图里这一处是反的：等级在上、名称在下
	_ok("1004 等级行在上", _label_a(_node(1004)) == "1级 1004", _label_a(_node(1004)))
	_ok("1004 名称行在下", _label_b(_node(1004)) == "风暴元素", _label_b(_node(1004)))

	_eq("1001 未通关不显示星", _lit_stars(_node(1001)), -1)
	# 概念稿里 1003 只点亮一颗（刚打过精英关），1004 点亮两颗；
	# 这两处曾被误读成全三星，放大核对后按稿子订正
	_eq("1003 一星（后两颗暗）", _lit_stars(_node(1003)), 1)
	_eq("1004 两星（一颗暗）", _lit_stars(_node(1004)), 2)

	_eq("1003 挂精英角标「精」", _tag_text(_node(1003)), "精")
	_eq("1001 无角标", _tag_text(_node(1001)), "")
	_eq("1004 无角标", _tag_text(_node(1004)), "")


# ---------------------------------------------------------------- 统计同步

## 统计同步：底部统计行与「历史最佳」都取存档口径；
## 展演值（demo_stars）只负责地图好看，不能被当成通关记录。
func _check_sync_stats() -> void:
	print("\n· 统计同步：星级与材料")
	var footer: Label = _scene.get_node_or_null("%FooterInfo")
	_ok("底部统计行存在", footer != null)
	if footer != null:
		_ok("统计行报出了累计星级", footer.text.contains("★"), footer.text)
		_ok("统计行报出了材料仓", footer.text.contains("材料"), footer.text)
		_ok("统计行仍带着体力", footer.text.contains("体力"), footer.text)

	_eq("存档无记录时历史最佳为 0", int(_scene.call("_best_stars_of", 1003)), 0)
	_eq("展演星仍照常画在地图上", int(_scene.call("_stars_of", 1003)), 1)

	# 模拟战斗结算写档：地图星与历史最佳都必须换成存档值
	SaveDB.record_stage_stars(1001, 2)
	_eq("写档后历史最佳取存档值", int(_scene.call("_best_stars_of", 1001)), 2)
	_eq("写档后地图星取存档值", int(_scene.call("_stars_of", 1001)), 2)

	# 进入按钮的 tooltip 要能看出这一关打到过几星
	var enter: Button = _scene.get_node_or_null("%EnterButton")
	var n3 := _node(1003)
	if enter != null and n3 != null:
		n3.pressed.emit()
		_ok("tooltip 写出了历史最佳", enter.tooltip_text.contains("历史最佳"), enter.tooltip_text)
		_ok("tooltip 写出了体力消耗", enter.tooltip_text.contains("体力"), enter.tooltip_text)


# ---------------------------------------------------------------- 选中态

func _check_selection() -> void:
	print("\n· 默认选中与切换")
	var default_id := 0
	for raw in GameDB.stage_nodes():
		var cfg: Dictionary = raw
		if bool(cfg.get("demo_selected", false)):
			default_id = int(cfg.get("stage_id", 0))
	_eq("配置标记的默认选中节点", default_id, 1003)

	_ok("默认选中节点光晕可见", _glow_visible(_node(default_id)))
	_ok("默认选中节点为全亮", _is_bright(_node(default_id)))
	_ok("默认选中节点被放大", _scale_target(_node(default_id)) > 1.0,
		"scale_target=%.2f" % _scale_target(_node(default_id)))
	for raw in GameDB.stage_nodes():
		var sid := int(raw.get("stage_id", 0))
		if sid != default_id:
			_ok("未选中节点 #%d 光晕隐藏" % sid, not _glow_visible(_node(sid)))
			_ok("未选中节点 #%d 不放大" % sid, is_equal_approx(_scale_target(_node(sid)), 1.0),
				"scale_target=%.2f" % _scale_target(_node(sid)))

	# 点击另一关应把选中态整块切过去
	var n1 := _node(1001)
	if n1 != null:
		n1.pressed.emit()
		_ok("点击 1001 后其光晕可见", _glow_visible(_node(1001)))
		_ok("点击 1001 后 1003 光晕隐藏", not _glow_visible(_node(1003)))
		_ok("点击 1001 后其亮度全开", _is_bright(_node(1001)))
		_ok("点击 1001 后放大态切过去", _scale_target(_node(1001)) > 1.0
			and is_equal_approx(_scale_target(_node(1003)), 1.0),
			"1001=%.2f 1003=%.2f" % [_scale_target(_node(1001)), _scale_target(_node(1003))])


# ---------------------------------------------------------------- 队伍与按钮

func _check_team() -> void:
	print("\n· 队伍面板与按钮文案")
	var slots: HBoxContainer = _scene.get_node_or_null("%TeamSlots")
	_ok("TeamSlots 存在", slots != null)
	if slots != null:
		_eq("上阵 3 个槽位", slots.get_child_count(), 3)

	var tp: Dictionary = GameDB.select_map().get("team_panel", {})
	var grid: Label = _scene.get_node_or_null("%TeamLabel")
	_eq("队伍角标文案取自配置", grid.text if grid != null else "<null>", str(tp.get("label", "")))

	var btn_cfg: Dictionary = GameDB.enter_button()
	var enter: Button = _scene.get_node_or_null("%EnterButton")
	_eq("进入按钮主文案", enter.text if enter != null else "<null>", str(btn_cfg.get("text", "")))
	var sub: Label = _scene.get_node_or_null("%EnterSub")
	_eq("进入按钮副文案", sub.text if sub != null else "<null>", str(btn_cfg.get("sub_text", "")))

	var back: Button = _scene.get_node_or_null("%BackButton")
	_ok("返回按钮存在且已接信号", back != null and back.pressed.get_connections().size() > 0)


# ---------------------------------------------------------------- 交互闭环

func _check_interact() -> void:
	print("\n· 交互闭环：进入关卡 → 校验体力 → 交接给编队页")
	var enter: Button = _scene.get_node_or_null("%EnterButton")
	var toast: Panel = _scene.get_node_or_null("%Toast")
	var tl: Label = _scene.get_node_or_null("%ToastLabel")
	if enter == null or toast == null or tl == null:
		_ok("进入按钮与提示条齐备", false)
		return

	# 真跑的话会切场景，把后续断言全打断；这里关掉自动跳转，
	# 只验「校验体力 + 记录关卡」这一半，跳转目标用常量钉住。
	_scene.set("auto_transition", false)
	_ok("进入关卡的路由指向编队页",
		str(_scene.FORMATION_SCENE).ends_with("formation.tscn"), str(_scene.FORMATION_SCENE))
	_ok("编队页场景真实存在", ResourceLoader.exists(_scene.FORMATION_SCENE))
	_ok("编队页的下一站（战斗场景）也存在",
		ResourceLoader.exists(str(GameDB.formation().get("battle_scene", ""))),
		str(GameDB.formation().get("battle_scene", "")))

	# 扣体力的位置由配置决定；默认在编队页「确认选择」时扣，
	# 所以这一步只校验、不扣 —— 玩家还没出发就不该已经被扣掉。
	_eq("扣体力位置取自配置", GameDB.spend_stamina_at(), "formation")

	# 切到 1004（每关 6 点）
	var n4 := _node(1004)
	if n4 != null:
		n4.pressed.emit()
	_eq("选中切到 1004", int(_scene.get("_selected")), 1004)

	var cost := GameDB.stage_stamina(1004)
	_eq("1004 的体力消耗取自关卡配置", cost, 6)
	var before := StaminaSys.current()
	enter.pressed.emit()
	_eq("进入关卡这一步不扣体力（改由编队页确认时扣）", StaminaSys.current(), before)
	_ok("进入关卡弹出提示条", toast.visible)
	_ok("提示条写出了当前选中关卡", tl.text.contains("风暴元素"),
		tl.text.replace("\n", " / "))
	_eq("把选中关卡交接给战斗上下文", int(BattleCtx.stage_id), 1004)

	# 免费关：1001 体力消耗为 0，同样放行
	var n1 := _node(1001)
	if n1 != null:
		n1.pressed.emit()
	_eq("1001 引导关免费", GameDB.stage_stamina(1001), 0)
	var mid := StaminaSys.current()
	enter.pressed.emit()
	_eq("免费关不扣体力", StaminaSys.current(), mid)
	_eq("免费关也照样交接", int(BattleCtx.stage_id), 1001)

	# 体力不足时应在选关页就被拦下：不交接关卡，也不放行到编队页
	# （必须切回一个真正要花体力的关卡 —— 停在免费关的话这条永远验不到）
	BattleCtx.begin_from_stage(1004, "smoke")
	if n4 != null:
		n4.pressed.emit()
	StaminaSys.spend(StaminaSys.current())
	_eq("体力已压到 0", StaminaSys.current(), 0)
	enter.pressed.emit()
	_ok("体力不足时拦在选关页", tl.text.contains("体力不足"), tl.text.replace("\n", " / "))
	_eq("体力不足时不交接关卡", int(BattleCtx.stage_id), 1004)

	# 恢复满体力，别把不足状态留给后续用例
	StaminaSys.fill()


# ---------------------------------------------------------------- 取节点与判定

func _node(stage_id: int) -> Button:
	return _scene.get_node_or_null("Hud/MapLayer/NodeLayer/StageNode_%d" % stage_id)


func _label_a(btn: Node) -> String:
	if btn == null:
		return "<null>"
	var l: Label = btn.get_node_or_null("LabelA")
	return l.text if l != null else "<null>"


func _label_b(btn: Node) -> String:
	if btn == null:
		return "<null>"
	var l: Label = btn.get_node_or_null("LabelB")
	return l.text if l != null else "<null>"


## 亮星数；没有 StarRow 时返回 -1（表示这一关不显示星）
func _lit_stars(btn: Node) -> int:
	if btn == null:
		return -2
	var row: Node = btn.get_node_or_null("StarRow")
	if row == null:
		return -1
	var lit := 0
	for c in row.get_children():
		var tr := c as TextureRect
		if tr != null and tr.modulate.r > 0.8 and tr.modulate.g > 0.6:
			lit += 1
	return lit


func _tag_text(btn: Node) -> String:
	if btn == null:
		return "<null>"
	var badge: Node = btn.get_node_or_null("TagBadge")
	if badge == null or badge.get_child_count() == 0:
		return ""
	var l := badge.get_child(0) as Label
	return l.text if l != null else ""


func _glow_visible(btn: Node) -> bool:
	if btn == null:
		return false
	var g: TextureRect = btn.get_node_or_null("SelectionGlow")
	return g != null and g.visible


## 选中态是 modulate 全白，未选中被压到 0.94
func _is_bright(btn: Node) -> bool:
	if btn == null:
		return false
	return btn.modulate.r > 0.99


## 节点被设置的缩放目标值（见 stage_select.gd 的 _scale_node）
func _scale_target(btn: Node) -> float:
	if btn == null or not btn.has_meta("scale_target"):
		return -1.0
	return float(btn.get_meta("scale_target"))
