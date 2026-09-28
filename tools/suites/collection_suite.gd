extends RefCounted
## collection_suite.gd —— 卡片图鉴（全部卡片：已获取 / 未获取）冒烟测试
##
## 由 tools/smoke_collection.gd 在主循环起来之后动态 load()（原因见 smoke 入口注释）。
##
## 覆盖四层：
##   配置层 —— menu.system_entries 里的图鉴入口 / 全卡目录与 rarities 一致性
##   数据层 —— _build_entries：持卡判定位、未持有回落展演态、筛选集合
##   场景层 —— 唯一名节点齐备、弹层默认隐藏、网格重建数与锁章
##   交互层 —— 筛选按钮、点开详情、上一张 / 下一张环游、返回不切场景
##
## 发卡全部走 save=false，测试不写档、可重复运行。

var passed := 0
var failed := 0

var _tree: SceneTree
var _scene: Control


func run(tree: SceneTree) -> Dictionary:
	_tree = tree
	print("\n========== 卡牌大冒险 · 卡片图鉴冒烟测试 ==========")

	SaveDB.reset_profile()

	_check_config()
	_check_scene()
	_check_data()
	_check_grid()
	_check_detail()
	print("\n---------- 结果：通过 %d / 失败 %d ----------" % [passed, failed])
	return { "passed": passed, "failed": failed }


func _ok(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  [PASS] %s%s" % [label, ("  " + detail) if detail != "" else ""])
	else:
		failed += 1
		print("  [FAIL] %s%s" % [label, ("  " + detail) if detail != "" else ""])


func _eq(label: String, got, want) -> void:
	_ok(label, got == want, "got=%s want=%s" % [str(got), str(want)])


# ---------------------------------------------------------------- 配置层

func _entry_cfg() -> Dictionary:
	for raw in GameDB.menu().get("system_entries", []):
		var e: Dictionary = raw
		if str(e.get("id", "")) == "collection":
			return e
	return {}


func _check_config() -> void:
	print("\n· 配置层：图鉴入口与全卡目录")
	var e := _entry_cfg()
	_ok("menu.system_entries 里有 collection 入口", not e.is_empty())
	_eq("入口路由", str(e.get("route", "")), "res://scenes/collection.tscn")
	_ok("入口图标存在", ResourceLoader.exists(str(e.get("icon", ""))),
		str(e.get("icon", "")))

	var all := GameDB.characters()
	_ok("全卡目录非空", all.size() >= 8, "%d 张" % all.size())
	var bad := 0
	for raw in all:
		var cfg: Dictionary = raw
		if GameDB.rarity(str(cfg.get("rarity", ""))).is_empty() \
				or GameDB.element(str(cfg.get("element", ""))).is_empty():
			bad += 1
	_eq("每张卡的 rarity / element 都能在配置表里查到", bad, 0)


# ---------------------------------------------------------------- 场景层

func _check_scene() -> void:
	print("\n· 场景层：collection.tscn")
	var path := str(_entry_cfg().get("route", "res://scenes/collection.tscn"))
	_ok("场景文件存在", ResourceLoader.exists(path), path)
	if not ResourceLoader.exists(path):
		return
	var ps: PackedScene = load(path)
	_ok("场景可加载", ps != null)
	if ps == null:
		return
	_scene = ps.instantiate()
	_tree.root.add_child(_scene)
	_ok("根节点已挂 collection.gd", _scene.get_script() != null)

	for n in ["TopPanel", "CollectLabel", "Filt_all", "Filt_owned", "Filt_unowned",
			"GridHolder", "DetailLayer", "DetailBackdrop", "DetailCardHolder",
			"DetailLockPanel", "DetailTitle", "DetailTags", "DetailState",
			"DetailPower", "DetailStats", "DetailSkills", "DetailAcquire",
			"DetailPrevButton", "DetailNextButton", "DetailCloseButton",
			"BackButton", "FooterInfo", "FooterStat", "Toast", "ToastLabel"]:
		_ok("唯一名 %%%s 可解析" % n, _scene.get_node_or_null("%" + n) != null)

	var detail: Control = _scene.get_node_or_null("%DetailLayer")
	_ok("详情弹层默认隐藏", detail != null and not detail.visible)
	var lock: Control = _scene.get_node_or_null("%DetailLockPanel")
	_ok("未获得提示牌默认隐藏", lock != null and not lock.visible)

	# Hud 是 IGNORE、背景层不拦鼠标，返回按钮才点得动（曾被全屏控件遮挡）
	var hud: Control = _scene.get_node_or_null("Hud")
	_ok("Hud 忽略鼠标", hud != null and hud.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	var bg: Control = _scene.get_node_or_null("Background")
	_ok("背景忽略鼠标", bg != null and bg.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	var tint: Control = _scene.get_node_or_null("DarkTint")
	_ok("暗角遮罩忽略鼠标", tint != null and tint.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	var grid_panel: Control = _scene.get_node_or_null("%GridPanel")
	_ok("网格底板忽略鼠标", grid_panel != null
		and grid_panel.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	var detail_layer: Control = _scene.get_node_or_null("%DetailLayer")
	_ok("弹层容器本身忽略鼠标", detail_layer != null
		and detail_layer.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	var backdrop: Control = _scene.get_node_or_null("%DetailBackdrop")
	_ok("弹层挡位接收鼠标（点空白关闭）", backdrop != null
		and backdrop.mouse_filter == Control.MOUSE_FILTER_STOP)


# ---------------------------------------------------------------- 数据层

func _entries() -> Array:
	return _scene.call("_build_entries")


func _check_data() -> void:
	print("\n· 数据层：全卡目录 × 存档持卡")
	var all := _entries()
	_eq("图鉴行数 = 配置卡数", all.size(), GameDB.characters().size())
	var owned0 := 0
	var owned_ids := {}
	for e in all:
		if bool(e["owned"]):
			owned0 += 1
			owned_ids[str(e["char_id"])] = true
	# 新档默认不发卡：卡片只能靠抽卡 / 兑换获得（十连保底保证至少一张人物卡）
	_eq("新档默认已获取 = 0", owned0, 0)
	_ok("默认档一张卡都没有", owned_ids.is_empty(), str(owned_ids.keys()))
	var demo_ok := true
	for e in all:
		if not bool(e["owned"]) \
				and int(e["card"].get("level", 0)) != int(e["config"].get("demo_level", 1)):
			demo_ok = false
	_ok("未持有的卡回落到展演态数据", demo_ok)

	# 发 3 张真卡（不写档），已获取判定要翻过来
	SaveDB.grant_card("knight_rock", false)
	SaveDB.grant_card("pyro_girl", false)
	SaveDB.grant_card("elf_ranger", false)
	_scene.call("reload")
	var after := _entries()
	var owned := 0
	var ids := {}
	for e in after:
		if bool(e["owned"]):
			owned += 1
			ids[str(e["char_id"])] = true
	_eq("发卡后已获取 = 3", owned, 3)
	_ok("已获取的正是那 3 张", ids.has("knight_rock") and ids.has("pyro_girl")
		and ids.has("elf_ranger"), str(ids.keys()))
	_scene.call("_refresh_footer")
	var fs: Label = _scene.get_node_or_null("%FooterStat")
	_ok("底栏统计反映持有数", fs != null and fs.text.contains("3"), fs.text if fs else "")


# ---------------------------------------------------------------- 网格与筛选

func _grid_children() -> Array:
	var grid: Control = _scene.get_node_or_null("%GridHolder")
	if grid == null:
		return []
	# 界面重建走「摘树 + queue_free」，被摘下的旧格子在真删除前仍会出现在
	# get_children 里（已脱离树但还没进删除队列），断言只数还在树上的活节点
	var out: Array = []
	for c in grid.get_children():
		var ctl := c as Control
		if ctl != null and is_instance_valid(ctl) and not ctl.is_queued_for_deletion() \
				and ctl.get_parent() == grid and ctl.is_inside_tree():
			out.append(ctl)
	return out


func _check_grid() -> void:
	print("\n· 网格层：筛选重建与未获取锁章")
	_scene.call("_apply_filter", "all")
	var all := _grid_children()
	_eq("全部 = 8 格", all.size(), GameDB.characters().size())

	var owned_cards := 0
	var locked_cards := 0
	var badges := 0
	for slot in all:
		for c in (slot as Control).get_children():
			var cv := c as CardView
			if cv != null:
				if cv.locked:
					locked_cards += 1
				else:
					owned_cards += 1
			elif str(c.name) == "LockBadge":
				badges += 1
	_eq("已获取卡面 3 张", owned_cards, 3)
	_eq("未获取剪影卡面 5 张", locked_cards, 5)
	_eq("锁章数量 = 未获取数量", badges, 5)

	# 未获取卡面：名牌 ???、无星级行
	for slot in all:
		for c in (slot as Control).get_children():
			var cv := c as CardView
			if cv != null and cv.locked:
				var plate: Panel = cv.get_node_or_null("NamePlate")
				var lb: Label = plate.get_child(0) if plate != null and plate.get_child_count() > 0 else null
				_eq("未获取卡名牌是 ???", lb.text if lb != null else "", "???")
				var lv: Label = cv.get_node_or_null("LevelLabel")
				_eq("未获取卡等级位显示「未获得」", lv.text if lv != null else "", "未获得")
				break

	_scene.call("_apply_filter", "owned")
	_eq("已获取筛选 = 3 格", _grid_children().size(), 3)
	_scene.call("_apply_filter", "unowned")
	_eq("未获取筛选 = 5 格", _grid_children().size(), 5)
	_scene.call("_apply_filter", "bogus")
	_eq("非法筛选回落全部 = 8 格", _grid_children().size(), 8)

	# 筛选按钮真的接在信号上（点击链路，不是只测内部方法）
	var btn: Button = _scene.get_node_or_null("%Filt_owned")
	_ok("筛选按钮已接信号", btn != null and btn.pressed.get_connections().size() > 0)
	btn.pressed.emit()
	_eq("点「已获取」按钮生效", _grid_children().size(), 3)
	var cl: Label = _scene.get_node_or_null("%CollectLabel")
	_ok("收集进度读数正确", cl != null and cl.text == "已收集 3 / 8", cl.text if cl else "")
	(_scene.get_node_or_null("%Filt_all") as Button).pressed.emit()
	_eq("点「全部」按钮回到 8 格", _grid_children().size(), 8)

	# 网格几何：4 列 × 2 行、整行水平居中、不越出网格底板
	var cols := {}
	var rows := {}
	var bottom := 0.0
	for slot in _grid_children():
		cols[str(round((slot as Control).position.x))] = true
		rows[str(round((slot as Control).position.y))] = true
		bottom = maxf(bottom, (slot as Control).position.y + (slot as Control).size.y)
	_eq("每行 4 列", cols.size(), 4)
	_eq("共 2 行", rows.size(), 2)
	var kids := _grid_children()
	var first: Control = kids[0]
	var last: Control = kids[-1]
	_ok("整行水平居中（左右留白对称）",
		absf(first.position.x - (1920.0 - last.position.x - last.size.x)) < 1.0,
		"left=%.0f right=%.0f" % [first.position.x, 1920.0 - last.position.x - last.size.x])
	_ok("末行不压出网格底板", bottom <= 1002.0, "bottom=%.0f" % bottom)


# ---------------------------------------------------------------- 详情弹层

func _check_detail() -> void:
	print("\n· 交互层：详情弹层")
	_scene.call("_apply_filter", "all")
	var layer: Control = _scene.get_node_or_null("%DetailLayer")

	# 点已获取卡：显示真实 Lv/★，锁牌不出现
	_scene.call("_open_detail", "knight_rock")
	_ok("点卡后弹层亮起", layer.visible)
	var state: Label = _scene.get_node_or_null("%DetailState")
	_ok("已获取显示真实等级", state.text.begins_with("已获取 · Lv."), state.text)
	var lock: Control = _scene.get_node_or_null("%DetailLockPanel")
	_ok("已获取不显示未获得提示牌", not lock.visible)
	var title: Label = _scene.get_node_or_null("%DetailTitle")
	_ok("标题含卡面名", title.text.contains("磐岩骑士"), title.text)
	var skills: Label = _scene.get_node_or_null("%DetailSkills")
	_ok("技能区有战斗定位", skills.text.contains("战斗定位"), skills.text.split("\n")[0])
	_ok("技能区有绝技文案", skills.text.contains("磐岩壁垒"), "")
	var holder: Control = _scene.get_node_or_null("%DetailCardHolder")
	_ok("详情卡面已就位", holder.get_child_count() == 1
		and holder.get_child(0) is CardView)

	# 点未获取卡：??? + 展演态提示 + 锁牌
	_scene.call("_open_detail", "holy_priest")
	_ok("未获取标题打码", title.text.contains("???"), title.text)
	_ok("未获取显示展演态提示", state.text.contains("未获取"), state.text)
	_ok("未获取亮起提示牌", lock.visible)
	var view: CardView = holder.get_child(0)
	_ok("详情卡面走剪影态", view.locked)
	var acq: Label = _scene.get_node_or_null("%DetailAcquire")
	_ok("未获取给获取途径", acq.text.contains("召唤"), acq.text)

	# 环游：上一张 / 下一张在筛选结果内打转
	_scene.call("_step_detail", -1)
	_ok("上一张回到列表末位", title.text.length() > 0, title.text)
	_scene.call("_apply_filter", "owned")
	_scene.call("_open_detail", "knight_rock")
	_scene.call("_step_detail", 1)
	var t2 := title.text
	_scene.call("_step_detail", 1)
	var t3 := title.text
	_ok("筛选内环游只走已获取的卡", not t2.contains("???") and not t3.contains("???"),
		"%s | %s" % [t2, t3])
	(_scene.get_node_or_null("%DetailNextButton") as Button).pressed.emit()
	_ok("下一张按钮已接信号", title.text != t3, title.text)

	# 关闭
	(_scene.get_node_or_null("%DetailCloseButton") as Button).pressed.emit()
	_ok("关闭按钮收起弹层", not layer.visible)
	_scene.call("_open_detail", "pyro_girl")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	_scene.call("_on_detail_backdrop", click)
	_ok("点空白遮罩收起弹层", not layer.visible)

	# 返回：auto_transition=false 时不切场景（测试里不真走跳转）
	_scene.set("auto_transition", false)
	var back: Button = _scene.get_node_or_null("%BackButton")
	_ok("返回按钮已接信号", back != null and back.pressed.get_connections().size() > 0)
	back.pressed.emit()
	_ok("关闭自动跳转后返回不切场景", is_instance_valid(_scene))
	_scene.queue_free()
