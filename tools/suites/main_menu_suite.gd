extends RefCounted
## main_menu_suite.gd —— 主界面冒烟测试套件
##
## 由 tools/smoke_main_menu.gd 在第一帧之后动态 load()。
## 拆两层的原因：--script 模式下被 --script 直接加载的脚本，在编译期
## 看不到 autoload 的全局标识符（GameDB / SaveDB / …），必须等主循环
## 起来之后再编译本文件，才能正常引用它们。
##
## 覆盖：配置层数值语义（元素克制 / 九宫格站位）、存档层语义（装备空槽、
##       发卡升星）、派生层属性换算、体力恢复速率、主界面节点树完整性。

var passed := 0
var failed := 0

var _tree: SceneTree
var _scene: Node


func run(tree: SceneTree) -> Dictionary:
	_tree = tree
	print("\n========== 卡牌大冒险 · 主界面冒烟测试 ==========")

	# 让测试可重复：先回到默认存档，避免上一次运行的持卡 / 体力残留污染断言
	SaveDB.reset_profile()
	StaminaSys.fill()

	_check_config()
	_check_board()
	_check_save()
	_check_realm()
	_check_stamina()
	_check_scene()
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

func _check_config() -> void:
	print("\n· 配置层 GameDB")
	_ok("game_data.json 已载入", GameDB.loaded)
	_eq("版本", GameDB.version(), "0.1.0")
	_ok("角色数 ≥ 4（GDD 图鉴持续扩充）", GameDB.characters().size() >= 4,
		str(GameDB.characters().size()))
	_ok("4 大职业归类齐全",
		_count_class("front") > 0 and _count_class("dps") > 0
			and _count_class("agile") > 0 and _count_class("support") > 0,
		"front=%d dps=%d agile=%d support=%d" % [_count_class("front"), _count_class("dps"),
			_count_class("agile"), _count_class("support")])
	_eq("元素数", GameDB.elements().size(), 6)
	_eq("品质档数", GameDB.rarities().size(), 4)

	# 图鉴字段完整性：每条英雄都要有立绘、品质、元素、职业与战斗定位
	var broken: Array = []
	for raw in GameDB.characters():
		var c: Dictionary = raw
		var cid := str(c.get("id", ""))
		if cid == "" or str(c.get("portrait", "")) == "" \
				or str(c.get("rarity", "")) == "" or str(c.get("element", "")) == "" \
				or str(c.get("role", "")) == "" or GameDB.card_battle_role(cid) == "":
			broken.append(cid)
	_eq("每条英雄的图鉴字段齐全", broken, [])

	# 元素循环：水→火→风→地→水
	_ok("水克火", GameDB.is_counter("water", "fire"))
	_ok("火克风", GameDB.is_counter("fire", "wind"))
	_ok("风克地", GameDB.is_counter("wind", "earth"))
	_ok("地克水", GameDB.is_counter("earth", "water"))
	_ok("火不克水", not GameDB.is_counter("fire", "water"))
	# 光暗互克
	_ok("光克暗", GameDB.is_counter("light", "dark"))
	_ok("暗克光", GameDB.is_counter("dark", "light"))

	_eq("克制伤害倍率", GameDB.damage_multiplier("water", "fire"), 1.25)
	_eq("非克制伤害倍率", GameDB.damage_multiplier("fire", "water"), 1.0)
	_eq("克制额外暴击", GameDB.crit_bonus("light", "dark"), 0.10)
	_eq("非克制额外暴击", GameDB.crit_bonus("dark", "earth"), 0.0)

	for rid in ["R", "SR", "SSR", "UR"]:
		var r: Dictionary = GameDB.rarity(rid)
		var rect: Rect2 = GameDB.rarity_inner_rect(rid)
		_ok("品质 %s 卡框与内腔齐备" % rid,
			str(r.get("frame", "")) != "" and rect.size.x > 0.3 and rect.size.y > 0.3,
			"inner=%.2fx%.2f" % [rect.size.x, rect.size.y])


func _check_board() -> void:
	print("\n· 九宫格站位 Combat")
	_eq("1号位=前排", GameDB.row_of_slot(1), "front")
	_eq("3号位=前排", GameDB.row_of_slot(3), "front")
	_eq("5号位=中排", GameDB.row_of_slot(5), "middle")
	_eq("9号位=后排", GameDB.row_of_slot(9), "back")
	# 己方镜向：1 号位落在最右列
	_eq("己方1号位格", GameDB.slot_cell("player", 1), Vector2i(2, 3))
	_eq("己方3号位格", GameDB.slot_cell("player", 3), Vector2i(0, 3))
	_eq("敌方1号位格", GameDB.slot_cell("enemy", 1), Vector2i(0, 2))
	_ok("中线两侧同列不同行",
		GameDB.slot_cell("player", 5).x == GameDB.slot_cell("enemy", 5).x
		and GameDB.slot_cell("player", 5).y > GameDB.slot_cell("enemy", 5).y)


# ---------------------------------------------------------------- 存档层

func _check_save() -> void:
	print("\n· 存档层 SaveDB")
	var p: Dictionary = SaveDB.profile.get("player", {})
	_eq("玩家名", str(p.get("name", "")), "云上旅人")
	_eq("等级", int(p.get("level", 0)), 10)
	_eq("金币", SaveDB.balance("gold"), 12500)
	_eq("钻石", SaveDB.balance("gem"), 1280)

	# 新号默认档：初始三卡已发放（名单 = menu.demo_team_slots），
	# 图鉴 / 编队 / 主界面三处对「默认有哪些卡」共用这一份事实
	_eq("新号默认持卡 = 初始三卡", SaveDB.cards().size(), 3)

	var before: int = SaveDB.cards().size()
	var card: Dictionary = SaveDB.grant_card("arcane_girl")
	_eq("发卡后持卡数 +1", SaveDB.cards().size(), before + 1)
	var slot_count := GameDB.equipment_slot_count()
	_eq("装备槽位数量", (card.get("equipment", []) as Array).size(), slot_count)
	_ok("空槽写空字符串（显式卸下语义）",
		(card.get("equipment", []) as Array).all(func(x): return x == ""),
		str(card.get("equipment", [])))

	# 新卡初始星级取品质表的 star_default，不取角色的 demo_star（那是展演值）
	var ur: Dictionary = SaveDB.grant_card("holy_priest")
	_eq("新卡初始星级 = 品质 star_default", int(ur.get("star", 0)),
		int(GameDB.rarity("UR").get("star_default", 0)))
	_eq("新卡初始等级 1", int(ur.get("level", 0)), 1)

	# grant_card 返回的是存档里那份字典的引用，升星会原地改写，
	# 所以先把首次星级取成值再比对
	var star_first := int(card.get("star", 0))
	var again: Dictionary = SaveDB.grant_card("arcane_girl")
	_eq("重复发卡为升星", int(again.get("star", 0)), star_first + 1)
	_eq("重复发卡不增加持卡数", SaveDB.cards().size(), before + 2)

	_ok("扣金币成功", SaveDB.spend_currency("gold", 500))
	_eq("金币扣减正确", SaveDB.balance("gold"), 12000)
	_ok("余额不足时扣款失败", not SaveDB.spend_currency("gold", 999999))
	SaveDB.add_currency("gold", 500)

	# 清理：把测试发出的卡移出存档，还原成初始三卡。
	# RealmDB.showcase_lineup() 会优先采用存档里的卡，留着会顶掉展演用的
	# demo_level / demo_star，导致后续断言拿到 Lv.1 的数据。
	SaveDB.profile["cards"] = SaveDB._starter_cards()
	SaveDB.save_profile()
	_eq("清理后只剩初始三卡", SaveDB.cards().size(), 3)


# ---------------------------------------------------------------- 派生层

func _check_realm() -> void:
	print("\n· 派生层 RealmDB")
	_eq("星级系数 1★", RealmDB.star_multiplier(1), 1.0)
	_eq("星级系数 2★", RealmDB.star_multiplier(2), 1.15)
	_eq("星级系数 3★", RealmDB.star_multiplier(3), 1.30)

	var lineup: Array = RealmDB.showcase_lineup()
	_eq("主界面展演阵容 4 张", lineup.size(), 4)
	var first: Dictionary = lineup[0]
	var st: Dictionary = first.stats
	_eq("磐岩骑士 HP（基础+成长）", int(st.get("hp", 0)), int(round(1250 + 62.0 * 19)))
	_eq("磐岩骑士 DEF", int(st.get("def", 0)), int(round(330 + 18.0 * 19)))
	_eq("磐岩骑士 SPD（走成长并含星级取整）", int(st.get("spd", 0)),
		int(round((92.0 + 0.35 * 19) * 1.0)))
	_eq("暴击率不吃成长与星级", float(st.get("crit", 0.0)), 0.05)
	_eq("暴伤不吃成长与星级", float(st.get("crit_dmg", 0.0)), 1.5)
	_eq("磐岩骑士 星级", int((first.card as Dictionary).get("star", 0)), 1)
	_ok("战力估值 > 0", int(first.get("power", 0)) > 0,
		"power=%d" % int(first.get("power", 0)))

	# 无存档时的演示卡必须与存档卡同形（装备槽写满 ""），
	# 否则将来接装备读侧时，遍历 / 判空两条路径会给出相反结论
	var demo_eq: Array = (first.card as Dictionary).get("equipment", [])
	_eq("演示卡装备槽位数与存档一致", demo_eq.size(), GameDB.equipment_slot_count())
	_ok("演示卡空槽同为空字符串", demo_eq.all(func(x): return x == ""), str(demo_eq))

	var pyro: Dictionary = lineup[1]
	_eq("紫焰少女 HP（含 3★加成）", int((pyro.stats as Dictionary).get("hp", 0)),
		int(round((780.0 + 44.0 * 29) * 1.30)))

	_eq("队伍预览 3 个位置", RealmDB.showcase_team().size(), 3)


# ---------------------------------------------------------------- 体力

func _check_stamina() -> void:
	print("\n· 体力 StaminaSys")
	_eq("体力上限", StaminaSys.maximum(), 60)
	_eq("恢复间隔（秒）", StaminaSys.seconds_per_point(), 300)
	_eq("每小时恢复点数", StaminaSys.regen_per_hour(), 12)
	var cur: int = StaminaSys.current()
	_ok("当前体力在合法区间", cur >= 0 and cur <= StaminaSys.maximum(), "current=%d" % cur)

	var before: int = StaminaSys.current()
	_ok("扣 10 点成功", StaminaSys.spend(10))
	_eq("扣减后数值", StaminaSys.current(), before - 10)
	StaminaSys.grant(10)
	_eq("回补后数值", StaminaSys.current(), before)
	_ok("倒计时文案非空", StaminaSys.format_next() != "")


# ---------------------------------------------------------------- 卡面内部布局

## 三围条是卡面最容易出问题的地方：卡框（尤其 UR）开口很窄，
## 早期用 HBoxContainer 时容器最小宽 = 子节点最小宽之和，会把整行撑到
## 卡框外面，第三个数值（DEF）被直接切掉。这里逐张卡验证三围条
## 以及它的每个数值都完整落在「内腔」矩形之内。
func _check_stat_rows(fan: CardFan) -> void:
	print("\n· 卡面三围条边界")
	for c in fan.cards:
		var card_view: CardView = c
		var inner: Rect2 = card_view.inner_px()
		var row: Control = card_view.get_node_or_null("StatRow")
		_ok("%s 三围条节点存在" % card_view.char_id, row != null)
		if row == null:
			continue

		var r_left: float = row.position.x
		var r_right: float = row.position.x + row.size.x
		var r_bottom: float = row.position.y + row.size.y
		_ok("%s 三围条不超出内腔左右" % card_view.char_id,
			r_left >= 0.0 and r_right <= inner.position.x + inner.size.x + 0.5,
			"row=[%.0f,%.0f] inner=[%.0f,%.0f]" % [
				r_left, r_right, inner.position.x, inner.position.x + inner.size.x])
		_ok("%s 三围条不超出内腔底部" % card_view.char_id,
			r_bottom <= inner.position.y + inner.size.y + 0.5,
			"bottom=%.0f inner_bottom=%.0f" % [r_bottom, inner.position.y + inner.size.y])

		# 三个数值（HP/ATK/DEF）必须齐全，且最后一个的右边界仍在内腔里
		_ok("%s 三围条含 3 个数值" % card_view.char_id, row.get_child_count() == 6,
			"children=%d" % row.get_child_count())
		var last: Control = row.get_node_or_null("StatValue2")
		_ok("%s DEF 数值节点存在" % card_view.char_id, last != null)
		if last != null:
			var v_right: float = row.position.x + last.position.x + last.size.x
			_ok("%s DEF 数值未被卡框切掉" % card_view.char_id,
				v_right <= inner.position.x + inner.size.x + 0.5,
				"text=%s right=%.0f inner_right=%.0f" % [
					last.text, v_right, inner.position.x + inner.size.x])
			_ok("%s DEF 数值文案非空" % card_view.char_id, last.text != "",
				"text=%s" % last.text)

		var plate: Control = card_view.get_node_or_null("NamePlate")
		if plate != null:
			_ok("%s 名牌不超出内腔" % card_view.char_id,
				plate.position.x >= inner.position.x - 0.5
				and plate.position.x + plate.size.x <= inner.position.x + inner.size.x + 0.5,
				"plate=[%.0f,%.0f]" % [plate.position.x, plate.position.x + plate.size.x])


# ---------------------------------------------------------------- 扇形叠压

## 「左卡的右半被右卡盖住」是跨节点的遮挡问题，卡面内部的断言看不出来。
## 这里把卡框与各信息块按 Control 的旋转/缩放换成正交到扇形父节点的多边形，
## 再逐对求交，算出信息块被更高 z 的邻卡吃掉的比例。
##
## 之所以在 headless 下也算得准：所有卡的 y 都等于 center.y + y_i - box/2，
## 彼此相减后 center.y（正比于视口高度）被消掉，因此**相对几何与视口高度无关**，
## 只有绝对 y 不同，而遮挡只取决于相对几何。
const PROTECTED_NODES := ["StatRow", "NamePlate", "LevelLabel", "ElementBadge"]

## 信息块被邻卡盖住的上限。留 2% 容忍亚像素级别的边框贴合。
const OCCLUSION_TOLERANCE := 0.02


func _check_occlusion(fan: CardFan) -> void:
	print("\n· 扇形叠压（信息块不被邻卡盖住）")
	var n := fan.cards.size()
	var boxes: Array = []
	var guards: Array = []
	for c in fan.cards:
		var cv: CardView = c
		boxes.append({ "poly": _card_poly(cv), "z": cv.z_index, "id": cv.char_id })
		var inner: Rect2 = cv.inner_px()
		# 三围条逐个数值单独看守：整条被盖 20% 可能只损失一个数字
		for i in range(3):
			var lb: Control = cv.get_node_or_null("StatRow/StatValue%d" % i)
			if lb != null:
				guards.append({ "cv": cv, "node": lb, "label": "%s 的第 %d 个数值" % [cv.char_id, i + 1] })
		for nm in ["NamePlate", "LevelLabel", "ElementBadge"]:
			var g: Control = cv.get_node_or_null(nm)
			if g != null:
				guards.append({ "cv": cv, "node": g, "label": "%s 的 %s" % [cv.char_id, nm] })
		_ok("%s 卡框为四边形" % cv.char_id, (boxes[-1].poly as PackedVector2Array).size() == 4,
			"inner=%.0fx%.0f" % [inner.size.x, inner.size.y])

	var worst := 0.0
	var worst_label := ""
	var checked := 0
	for g in guards:
		var cv: CardView = g.cv
		var rect: Control = g.node
		var poly := _control_poly(cv, rect)
		var area := _poly_area(poly)
		if area <= 0.0:
			continue
		checked += 1
		var covered := 0.0
		for b in boxes:
			if int(b.z) <= cv.z_index:
				continue
			covered += _poly_area(_intersect(poly, b.poly))
		var ratio: float = covered / area
		if ratio > worst:
			worst = ratio
			worst_label = str(g.label)
		if ratio > OCCLUSION_TOLERANCE:
			print("      · %s 被盖 %.0f%%" % [g.label, ratio * 100.0])

	var expected_guards := n * (3 + 3)  # 每卡：3 个数值 + 名牌 / 等级 / 元素徽章
	_ok("受保护信息块数量齐全（%d 张 × 6 块）" % n, checked == expected_guards,
		"checked=%d want=%d" % [checked, expected_guards])
	_ok("没有信息块被邻卡盖住（最大 %.0f%% ＜ %.0f%%）" % [
			worst * 100.0, OCCLUSION_TOLERANCE * 100.0],
		worst <= OCCLUSION_TOLERANCE,
		"worst=%s at %s" % [String.num(worst * 100.0, 1) + "%", worst_label])


## Control 的局部矩形 -> 扇形父节点坐标系的多边形。
## 不手工拼 Transform2D：Control 的 position / pivot_offset / rotation / scale
## 复合顺序由引擎决定，自己复刻很容易在枢轴上出错。直接借引擎的全局变换，
## 再用父节点的逆变换拉回扇形局部坐标系。
func _control_poly(cv: CardView, node: Control) -> PackedVector2Array:
	var p := node.position
	var s := node.size
	var corners := PackedVector2Array([
		Vector2(p.x, p.y), Vector2(p.x + s.x, p.y),
		Vector2(p.x + s.x, p.y + s.y), Vector2(p.x, p.y + s.y)])
	return _to_fan(cv, corners)


func _card_poly(cv: CardView) -> PackedVector2Array:
	return _to_fan(cv, PackedVector2Array([
		Vector2.ZERO, Vector2(cv.size.x, 0.0),
		Vector2(cv.size.x, cv.size.y), Vector2(0.0, cv.size.y)]))


func _to_fan(cv: CardView, pts: PackedVector2Array) -> PackedVector2Array:
	var parent := cv.get_parent() as Control
	var inv := parent.get_global_transform().affine_inverse()
	var xf := cv.get_global_transform()
	var out := PackedVector2Array()
	for q in pts:
		out.append(inv * (xf * q))
	return out


func _intersect(a: PackedVector2Array, b: PackedVector2Array) -> PackedVector2Array:
	var parts: Array = Geometry2D.intersect_polygons(a, b)
	if parts.is_empty():
		return PackedVector2Array()
	# 求交可能返回多个碎片，取面积最大的那片即可（本场景下只会有一片）
	var best := PackedVector2Array()
	var best_area := 0.0
	for part in parts:
		var pl: PackedVector2Array = part
		var ar := _poly_area(pl)
		if ar > best_area:
			best_area = ar
			best = pl
	return best


func _poly_area(poly: PackedVector2Array) -> float:
	if poly.size() < 3:
		return 0.0
	var acc := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		acc += a.x * b.y - b.x * a.y
	return absf(acc) * 0.5


# ---------------------------------------------------------------- 右侧入口竖栏

## 竖栏 = 玩法模式（占位，点了弹待接入）+ 分隔线 + 系统入口（按 route 真的切场景）。
## 这两组的差别只在「点击行为」，所以分开数、分开断言。
func _check_right_rail(rail: Control) -> void:
	var mode_n := 0
	var sys_n := 0
	var divider_n := 0
	for c in rail.get_children():
		var nm := str(c.name)
		if nm.begins_with("Mode_"):
			mode_n += 1
		elif nm.begins_with("Sys_"):
			sys_n += 1
		else:
			divider_n += 1

	_eq("玩法入口数 = 配置的 modes", mode_n, GameDB.mode_entries().size())
	_eq("系统入口数 = menu.system_entries", sys_n, _system_entries().size())
	if mode_n > 0 and sys_n > 0:
		_eq("两组之间有且只有一条分隔线", divider_n, 1)
	else:
		_eq("只有一组时不画分隔线", divider_n, 0)

	# 系统入口：这一条是「真的能进」的，不是占位
	for raw in _system_entries():
		var e: Dictionary = raw
		var id := str(e.get("id", ""))
		var btn := rail.get_node_or_null("Sys_%s" % id) as Button
		_ok("系统入口「%s」已实例化" % str(e.get("name", id)), btn != null)
		if btn == null:
			continue
		_eq("系统入口「%s」名称取自配置" % id, _rail_entry_text(btn), str(e.get("name", "")))
		_ok("系统入口「%s」已接信号" % id, btn.pressed.get_connections().size() > 0)

		var route := str(e.get("route", ""))
		_ok("系统入口「%s」配了 route" % id, route != "",
			"route=%s" % route)
		_ok("系统入口「%s」的目标场景存在" % id, ResourceLoader.exists(route), route)
		_ok("系统入口「%s」带 tooltip 说明" % id, btn.tooltip_text != "", btn.tooltip_text)

		# 按下它不该走「模块待接入」那条分支（那条只给 modes 用）
		_scene.set("auto_transition", false)
		var toast: Label = _scene.get_node_or_null("%ToastLabel")
		var before := toast.text if toast != null else ""
		btn.pressed.emit()
		var after := toast.text if toast != null else ""
		_ok("系统入口「%s」不会报「模块待接入」" % id, not after.contains("模块待接入"),
			"before=%s after=%s" % [before, after])


## 竖栏入口的名称：图标是 TextureRect，名称是第一个 Label
func _rail_entry_text(btn: Button) -> String:
	for c in btn.get_children():
		if c is Label:
			return (c as Label).text
	return "<null>"


func _system_entries() -> Array:
	var v: Variant = GameDB.menu().get("system_entries", [])
	return v if v is Array else []


## 某个四大职业分类（front / dps / agile / support）下的英雄数
func _count_class(class_id: String) -> int:
	var n := 0
	for raw in GameDB.characters():
		var c: Dictionary = raw
		if GameDB.class_of(str(c.get("role", ""))) == class_id:
			n += 1
	return n


# ---------------------------------------------------------------- 场景

func _check_scene() -> void:
	print("\n· 主界面场景")
	var ps: PackedScene = load("res://scenes/main_menu.tscn")
	_ok("场景可加载", ps != null)
	if ps == null:
		return

	_scene = ps.instantiate()
	_ok("场景根节点为 Control", _scene is Control, str(_scene.get_class()))
	_tree.root.add_child(_scene)
	_ok("根节点已挂 main_menu.gd", _scene.get_script() != null)

	var fan: CardFan = _scene.get_node_or_null("%CardFan")
	_ok("CardFan 唯一名可解析", fan != null)
	if fan != null:
		_eq("运行时重建卡牌 3 张（与出战阵容一致）", fan.cards.size(), 3)
		# 场景里烘焙了 3 张预览卡，运行时必须被清干净重建，否则会叠出幽灵卡
		_eq("CardFan 子节点只剩 3 个（预览卡已清）", fan.get_child_count(), 3)
		var ids: Array = []
		var rots: Array = []
		for c in fan.cards:
			ids.append(c.char_id)
			rots.append(c.rotation_degrees)
			print("      · %-14s pos=(%6.0f,%6.0f) rot=%6.1f scale=%.2f z=%d" % [
				c.char_id, c.position.x, c.position.y,
				c.rotation_degrees, c.scale.x, c.z_index])
		print("      卡牌顺序：%s" % str(ids))
		print("      扇形旋转：%s" % str(rots))
		# 扇形现在跟随出战阵容（展演队前 3 位），与底部阵容栏同一批
		_ok("卡牌顺序与出战阵容一致",
			ids == ["knight_rock", "pyro_girl", "elf_ranger"])
		_ok("扇形旋转有正有负", rots.size() == 3 and rots[0] < 0.0 and rots[2] > 0.0)

		# 只校验宽度：headless 下视口高度不是 1080，纵向尺寸不作断言。
		# 这条专门看守 UI.fill() 把 size 与 anchor 叠加成双倍尺寸那类塌陷。
		_ok("CardFan 宽度未被撑成两倍（1920 而非 3840）",
			absf(fan.size.x - 1920.0) < 1.0, "size=%s" % str(fan.size))

		# 横向位置完全由「扇心 + 索引偏移 × spacing」推得，所以断言也从配置现算，
		# 不再写死像素值——否则一调间距就要回来改测试。
		var fan_cfg: Dictionary = GameDB.menu().get("fan", {})
		# 扇形整体缩放（fan.scale）同时作用于间距，所以要一起乘进来，
		# 否则调一次卡牌大小就得回来改测试。
		var fan_scale := maxf(0.05, float(fan_cfg.get("scale", 1.0)))
		var spacing := float(fan_cfg.get("spacing_x", 296.0)) * fan_scale
		var cx := float(fan_cfg.get("center_x_offset", 0.0))
		var box_cfg: Dictionary = GameDB.menu().get("card_box", {})
		var box_w := float(box_cfg.get("w", 336))
		var view_w := fan.size.x
		var center_x := view_w * 0.5 + cx
		for i in fan.cards.size():
			var want_x: float = center_x + (float(i) - (fan.cards.size() - 1) * 0.5) * spacing - box_w * 0.5
			_ok("第 %d 张卡横向位置符合扇形公式" % i,
				absf(fan.cards[i].position.x - want_x) < 1.0,
				"got=%.0f want=%.0f" % [fan.cards[i].position.x, want_x])
		_ok("首卡在视口内且未贴边",
			fan.cards[0].position.x > 60.0 and fan.cards[0].position.x < center_x,
			"x=%.0f" % fan.cards[0].position.x)
		_ok("末卡在视口内且未贴边",
			fan.cards[2].position.x + box_w < view_w - 60.0 and fan.cards[2].position.x > center_x,
			"right=%.0f" % (fan.cards[2].position.x + box_w))

		# 末卡（含旋转外扩）不能压到右侧玩法入口栏上
		var rail: Control = _scene.get_node_or_null("Hud/RightRail")
		if rail != null:
			var rightmost := 0.0
			for c in fan.cards:
				var cv: CardView = c
				for q in _card_poly(cv):
					rightmost = maxf(rightmost, q.x + cv.get_parent().position.x)
			var rail_left: float = rail.position.x + rail.get_parent().position.x
			_ok("末卡不压右侧玩法入口栏",
				rightmost <= rail_left - 8.0,
				"卡牌最右=%.0f 入口栏最左=%.0f 间距=%.0f" % [rightmost, rail_left, rail_left - rightmost])

		_check_occlusion(fan)

		var cv: CardView = fan.find_card("pyro_girl")
		_ok("SSR 卡可定位", cv != null)
		if cv != null:
			var inner: Rect2 = cv.inner_px()
			_ok("SSR 卡内腔有效", inner.size.x > 100.0 and inner.size.y > 100.0,
				"inner=%.0fx%.0f" % [inner.size.x, inner.size.y])

			var kv: CardView = fan.find_card("knight_rock")
			if kv != null:
				var kin: Rect2 = kv.inner_px()
				_ok("R 卡内腔比 SSR 更宽（卡框更细）", kin.size.x > cv.inner_px().size.x,
					"R=%.0f SSR=%.0f" % [kin.size.x, cv.inner_px().size.x])

		_check_stat_rows(fan)

	var slots: HBoxContainer = _scene.get_node_or_null("%TeamSlots")
	_ok("TeamSlots 存在", slots != null)
	if slots != null:
		_eq("队伍预览铺满上阵上限槽位", slots.get_child_count(), GameDB.team_max())

	var start: Button = _scene.get_node_or_null("%StartButton")
	_ok("开始冒险按钮存在", start != null)
	if start != null:
		_eq("按钮文案", start.text, "进入冒险")

	var sv: Label = _scene.get_node_or_null("%StaminaValue")
	_ok("体力文本已绑定", sv != null and sv.text.contains("/"),
		"text=%s" % (sv.text if sv else "null"))

	var nx: Label = _scene.get_node_or_null("%StaminaNext")
	_ok("体力倒计时已绑定", nx != null and nx.text != "",
		"text=%s" % (nx.text if nx else "null"))

	var gold: Label = _scene.get_node_or_null("%GoldLabel")
	_eq("金币文本", gold.text if gold else "", "12,500")
	var gem: Label = _scene.get_node_or_null("%GemLabel")
	_eq("钻石文本", gem.text if gem else "", "1,280")

	var footer: Label = _scene.get_node_or_null("%FooterInfo")
	_ok("页脚数据层信息已刷新",
		footer != null and footer.text.contains("GameDB") and footer.text.contains("StaminaSys"),
		footer.text if footer else "null")

	var rail: Control = _scene.get_node_or_null("Hud/RightRail")
	_ok("右侧入口竖栏存在", rail != null)
	if rail != null:
		_check_right_rail(rail)

	var tr: Control = _scene.get_node_or_null("Hud/TopRight")
	_ok("右上功能入口存在", tr != null)
	if tr != null:
		_eq("功能入口 3 个", tr.get_child_count(), 3)

	# 交互：「进入冒险」不再直接扣体力，改为切到冒险关卡选择场景。
	# 体力扣除移到编队页的「确认选择」（覆盖见 stage_select_suite / formation_suite）。
	# 这里关掉自动跳转，免得把后面的断言打断（切了场景 = 又叠一棵节点树）。
	_scene.set("auto_transition", false)
	if start != null:
		var consts: Dictionary = _scene.get_script().get_script_constant_map()
		var stage_scene := str(consts.get("STAGE_SELECT_SCENE", ""))
		_ok("进入冒险的目标指向关卡选择页",
			stage_scene == "res://scenes/stage_select.tscn", "target=%s" % stage_scene)
		_ok("目标场景文件存在", ResourceLoader.exists(stage_scene))
		var st_before: int = StaminaSys.current()
		start.emit_signal("pressed")
		_eq("进入冒险不再扣体力（改由确认选择时扣）", StaminaSys.current(), st_before)

	# 交互：点击卡牌应弹出该卡详情
	if fan != null:
		var pyro_card: CardView = fan.find_card("pyro_girl")
		if pyro_card != null:
			pyro_card.card_pressed.emit("pyro_girl")
			var tl2: Label = _scene.get_node_or_null("%ToastLabel")
			_ok("点击卡牌弹出详情", tl2 != null and tl2.text.contains("紫焰少女"),
				tl2.text.replace("\n", " / ") if tl2 else "null")

	# ---- 编队同步：主界面必须反映「解析后的出战编队」，最多铺满上阵上限 ----
	_check_team_preview(fan, slots, rail)


## 主界面与编队页共用 SaveDB.resolved_team：验证空档回落口径一致、
## 满编队时扇形与阵容栏都同步到 N 人（模拟从编队页返回后重跑接线）、
## 且 N 张扇形不压右侧入口栏。
func _check_team_preview(fan: CardFan, slots: HBoxContainer, rail: Control) -> void:
	print("\n· 主界面同步出战编队")
	if fan == null or slots == null:
		_ok("扇形与阵容栏齐备", false)
		return
	var max_members := GameDB.team_max()
	# 空档回落口径：存档 team 为空时，主界面取当前预设（与编队页同一份）
	SaveDB.profile["team"] = []
	_eq("空档回落 = 当前预设（与编队页同口径）",
		SaveDB.resolved_team().size(), SaveDB.preset_entries(SaveDB.active_preset()).size())

	# 造一套满编队（取前 N 个英雄），模拟「编队页保存后返回主界面」重跑数据接线
	var ids: Array = GameDB.characters().map(func(c: Dictionary) -> String: return str(c.get("id", "")))
	var entries: Array = []
	for i in mini(max_members, ids.size()):
		entries.append({"slot": i + 1, "char_id": str(ids[i])})
	SaveDB.set_team(entries)
	_scene.call("_build_showcase")
	_scene.call("_build_team")
	var want := entries.size()
	_eq("满编队时扇形显示 %d 张" % want, fan.cards.size(), want)
	_eq("满编队时阵容栏仍铺满上限", slots.get_child_count(), max_members)
	var shown: Array = []
	for c in fan.cards:
		shown.append((c as CardView).char_id)
	_ok("扇形反映最新保存的编队", shown == ids.slice(0, want), str(shown))

	# N 张扇形（含旋转外扩）不能压到右侧入口栏
	if rail != null:
		var rightmost := 0.0
		for c in fan.cards:
			var cv: CardView = c
			for q in _card_poly(cv):
				rightmost = maxf(rightmost, q.x + cv.get_parent().position.x)
			var rail_left: float = rail.position.x + rail.get_parent().position.x
			_ok("满编队扇形不压右侧入口栏", rightmost <= rail_left - 8.0,
				"最右=%.0f 栏左=%.0f" % [rightmost, rail_left])

	# 还原默认档，保持幂等（不污染后续）
	SaveDB.reset_profile()
