extends RefCounted
## adventure_data_suite.gd —— 冒险关卡选择页数据冒烟测试
##
## 由 tools/smoke_adventure_data.gd 在第一帧之后动态 load()。
## 校验参考图落库的 adventure.select_map：字段完整性、坐标合法性、
## 引导链与前置关系一致、队伍面板与按钮文案可读。

var passed := 0
var failed := 0

const BASE := Vector2(1920, 1080)

var _tree: SceneTree


func run(tree: SceneTree) -> Dictionary:
	_tree = tree
	print("\n========== 卡牌大冒险 · 冒险关卡选择数据冒烟 ==========")

	_check_section()
	_check_team_and_button()
	_check_nodes()
	_check_links()
	_check_decor()
	_check_accessors()
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


func _in_screen(pos: Vector2) -> bool:
	return pos.x > 0.0 and pos.x < BASE.x and pos.y > 0.0 and pos.y < BASE.y


func _pos_of(node: Dictionary) -> Vector2:
	var p: Variant = node.get("pos", [])
	if p is Array and p.size() == 2:
		return Vector2(float(p[0]), float(p[1]))
	return Vector2.ZERO


# ---------------------------------------------------------------- 段落

func _check_section() -> void:
	print("\n· adventure 段落")
	var adv: Dictionary = GameDB.adventure()
	_ok("adventure 段存在", not adv.is_empty())
	_eq("冒险模式", str(adv.get("mode", "")), "chapter_stage")
	_eq("每关体力", int(adv.get("stamina_per_stage", 0)), 6)
	_eq("章节数", adv.get("chapters", []).size(), 3)

	var sm: Dictionary = GameDB.select_map()
	_ok("select_map 段存在", not sm.is_empty())
	_eq("页面标题", str(sm.get("title", "")), "冒险关卡选择")
	_eq("归属章节", str(sm.get("chapter_id", "")), "ch1")
	_ok("坐标基准说明非空", str(sm.get("coord_note", "")) != "")


# ---------------------------------------------------------------- 队伍 / 按钮

func _check_team_and_button() -> void:
	print("\n· 底部队伍面板与进入按钮")
	var tp: Dictionary = GameDB.select_map().get("team_panel", {})
	_eq("阵型行", int(tp.get("rows", 0)), 3)
	_eq("阵型列", int(tp.get("cols", 0)), 3)
	_eq("上阵人数", int(tp.get("deployed", 0)), 3)
	_eq("面板角标文案", str(tp.get("label", "")), "3x3 3")

	var lineup: Array = tp.get("lineup", [])
	_eq("上阵名单长度", lineup.size(), 3)
	for cid in lineup:
		_ok("上阵角色 %s 在角色配置里存在" % str(cid), not GameDB.character(str(cid)).is_empty())

	var btn: Dictionary = GameDB.enter_button()
	_eq("按钮主文案", str(btn.get("text", "")), "进入关卡")
	_eq("按钮副文案", str(btn.get("sub_text", "")), "START LEVEL")

	var promo: Dictionary = GameDB.select_map().get("promo_entry", {})
	_eq("右侧活动入口名", str(promo.get("name", "")), "活动")
	_ok("活动入口图标已导入", ResourceLoader.exists(str(promo.get("icon", ""))))


# ---------------------------------------------------------------- 节点

func _check_nodes() -> void:
	print("\n· 关卡节点")
	var nodes: Array = GameDB.stage_nodes()
	_eq("节点数", nodes.size(), 3)

	var ids: Array = []
	var kinds: Dictionary = {}
	for raw in GameDB.adventure().get("stage_kinds", []):
		if raw is Dictionary:
			kinds[str(raw.get("id", ""))] = true

	for raw in nodes:
		var n: Dictionary = raw
		var sid := int(n.get("stage_id", 0))
		var pos := _pos_of(n)
		ids.append(sid)
		_ok("节点 #%d 有名称" % sid, str(n.get("name", "")) != "")
		_ok("节点 #%d 等级 >= 1" % sid, int(n.get("level", 0)) >= 1)
		_ok("节点 #%d 类型合法" % sid, kinds.has(str(n.get("kind", ""))),
			"kind=%s" % str(n.get("kind", "")))
		_ok("节点 #%d 锚点在屏内" % sid, _in_screen(pos), "pos=%s" % str(pos))
		_ok("节点 #%d 层级 z 为正" % sid, int(n.get("z", 0)) >= 1)
		# 锚点 = 该关浮岛在背景里的中心，标签另用 label_dy 定位；
		# 引导线两端按 radius 从中心收回，所以两个字段都必须有且为正
		_ok("节点 #%d 有 label_dy" % sid, float(n.get("label_dy", 0.0)) > 0.0,
			"label_dy=%s" % str(n.get("label_dy", "缺失")))
		_ok("节点 #%d 有 radius" % sid, float(n.get("radius", 0.0)) > 0.0,
			"radius=%s" % str(n.get("radius", "缺失")))

	_eq("节点编号集合", ids, [1001, 1003, 1004])
	_eq("编号无重复", ids.size(), _unique(ids).size())

	# 与图中画面对应的细节
	var n1: Dictionary = GameDB.stage_node(1001)
	_eq("初始之地 名称", str(n1.get("name", "")), "初始之地")
	_eq("初始之地 无前置", int(n1.get("pre_stage_id", -1)), 0)
	_eq("初始之地 无星", int(n1.get("demo_stars", -1)), 0)
	_eq("初始之地 不叠图标（浮岛由背景自带）", str(n1.get("icon", "")), "")

	var n3: Dictionary = GameDB.stage_node(1003)
	_eq("云端城堡 名称", str(n3.get("name", "")), "云端城堡")
	_eq("云端城堡 类型为精英", str(n3.get("kind", "")), "elite")
	_eq("云端城堡 角标", str(n3.get("tag", "")), "精")
	# 概念稿里这颗星只点亮第一颗，曾误读成三星，放大核对后订正
	_eq("云端城堡 一星", int(n3.get("demo_stars", -1)), 1)
	_ok("云端城堡 为默认选中", bool(n3.get("demo_selected", false)))
	_eq("云端城堡 不叠图标（城堡由背景自带）", str(n3.get("icon", "")), "")

	var n4: Dictionary = GameDB.stage_node(1004)
	_eq("风暴元素 名称", str(n4.get("name", "")), "风暴元素")
	_eq("风暴元素 两星", int(n4.get("demo_stars", -1)), 2)
	_eq("风暴元素 等级行在上", str(n4.get("label_order", "")), "level_name")
	_ok("风暴元素 图标已导入", ResourceLoader.exists(str(n4.get("icon", ""))),
		str(n4.get("icon", "")))
	_ok("风暴元素 图标尺寸为正", float(n4.get("icon_size", 0.0)) > 0.0)
	_eq("风暴元素 层级最高", int(n4.get("z", 0)), 3)

	# 三个浮岛的高度不同，标签落点不该是同一个值 ——
	# 否则说明又退回了「所有节点共用一套偏移」的老写法
	var dys: Array = [float(n1.get("label_dy", 0.0)), float(n3.get("label_dy", 0.0)),
		float(n4.get("label_dy", 0.0))]
	_eq("三个节点的 label_dy 互不相同", _unique(dys).size(), 3)
	# 引导线收回半径必须小于相邻节点的间距，否则线会被收成负长度
	for pair in GameDB.stage_links():
		var a := int(pair[0])
		var b := int(pair[1])
		var gap := _pos_of(GameDB.stage_node(a)).distance_to(_pos_of(GameDB.stage_node(b)))
		var cut := float(GameDB.stage_node(a).get("radius", 0.0)) \
			+ float(GameDB.stage_node(b).get("radius", 0.0))
		_ok("引导线 %d→%d 收回后仍可见" % [a, b], gap - cut >= 24.0,
			"间距 %.0f - 收回 %.0f = %.0fpx" % [gap, cut, gap - cut])

	# 节点两两不重叠
	for i in nodes.size():
		for j in range(i + 1, nodes.size()):
			var a: Dictionary = nodes[i]
			var b: Dictionary = nodes[j]
			var d := _pos_of(a).distance_to(_pos_of(b))
			_ok("节点 %d 与 %d 锚点不重叠" % [int(a.get("stage_id", 0)), int(b.get("stage_id", 0))],
				d > 100.0, "距离 %.0fpx" % d)

	# 节点编号应落在归属章节的关卡区间内
	var chapter_stages := 0
	for raw in GameDB.adventure().get("chapters", []):
		if raw is Dictionary and str(raw.get("id", "")) == "ch1":
			chapter_stages = int(raw.get("stages", 0))
	_ok("归属章节关卡数已知", chapter_stages > 0, "ch1 stages=%d" % chapter_stages)
	for sid in ids:
		_ok("节点 #%d 落在 ch1 区间" % int(sid),
			int(sid) >= 1001 and int(sid) < 1001 + chapter_stages)


func _unique(arr: Array) -> Array:
	var seen: Array = []
	for v in arr:
		if not seen.has(v):
			seen.append(v)
	return seen


# ---------------------------------------------------------------- 引导线

func _check_links() -> void:
	print("\n· 关卡引导线")
	var links: Array = GameDB.stage_links()
	_eq("引导线数量", links.size(), 2)
	_eq("引导线链路", links, [[1001, 1003], [1003, 1004]])
	for pair in links:
		var a: int = int(pair[0])
		var b: int = int(pair[1])
		_ok("引导线 %d -> %d 两端节点齐备" % [a, b],
			not GameDB.stage_node(a).is_empty() and not GameDB.stage_node(b).is_empty())
		_ok("引导线 %d -> %d 方向由前置指向后置" % [a, b],
			int(GameDB.stage_node(b).get("pre_stage_id", 0)) == a)


# ---------------------------------------------------------------- 装饰岛

func _check_decor() -> void:
	print("\n· 装饰浮岛")
	var deco: Array = GameDB.decor_islands()
	_ok("装饰岛数量 >= 3", deco.size() >= 3, "count=%d" % deco.size())

	var ids: Array = []
	for raw in deco:
		var d: Dictionary = raw
		var pos := _pos_of(d)
		ids.append(str(d.get("id", "")))
		_ok("装饰岛 %s 锚点在屏内" % str(d.get("id", "")), _in_screen(pos), "pos=%s" % str(pos))
		_ok("装饰岛 %s 缩放为正" % str(d.get("id", "")), float(d.get("scale", 0.0)) > 0.0)
	_eq("装饰岛 id 唯一", ids.size(), _unique(ids).size())

	for raw in deco:
		var d: Dictionary = raw
		var dpos := _pos_of(d)
		for raw2 in GameDB.stage_nodes():
			var n: Dictionary = raw2
			var dist := dpos.distance_to(_pos_of(n))
			_ok("装饰岛 %s 不压住关卡 #%d" % [str(d.get("id", "")), int(n.get("stage_id", 0))],
				dist > 120.0, "距离 %.0fpx" % dist)


# ---------------------------------------------------------------- 访问器

func _check_accessors() -> void:
	print("\n· GameDB 访问器")
	var p := GameDB.stage_node_pos(1003)
	_eq("stage_node_pos(1003)", p, Vector2(937, 400))
	_ok("stage_node(9999) 返回空", GameDB.stage_node(9999).is_empty())
	_ok("stage_node_pos(9999) 返回零", GameDB.stage_node_pos(9999) == Vector2.ZERO)
	_eq("关卡类型名 elite", GameDB.stage_kind_name("elite"), "精英 Boss 战")
	_eq("关卡类型名 battle", GameDB.stage_kind_name("battle"), "普通战斗")
	_eq("未知类型回退原值", GameDB.stage_kind_name("nope"), "nope")
