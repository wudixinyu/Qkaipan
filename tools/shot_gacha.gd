extends SceneTree
## shot_gacha.gd —— 抽卡界面截图自检
##
## 用法（必须带窗口：headless 的假渲染器取不到画面）：
##   Godot --path <项目> --resolution 1920x1080 --script res://tools/shot_gacha.gd -- [mode] [wait]
##
##   mode = page        静止界面（默认）           → shots/gacha.png
##          reveal1     单抽结果展示              → shots/gacha_reveal1.png
##          reveal10    十连结果展示（2×5 紧凑卡） → shots/gacha_reveal10.png
##          pillar_ssr  紫光柱（先设小保底 49）    → shots/gacha_pillar_ssr.png
##          pillar_ur   彩虹光柱（先设大保底 99）  → shots/gacha_pillar_ur.png
##          rate        概率公示弹层              → shots/gacha_rate.png
##          shop        心愿水晶商店弹层          → shots/gacha_shop.png
##
## 注意：抽卡会真实写档（扣券 / 发卡 / 累水晶）。跑之前先备份
##   %APPDATA%/Godot/app_userdata/卡牌大冒险/save.json，跑完还原。
##
## 光柱没法靠运气 —— 先用存档层的保底计数把它逼出来：
##   小保底计到 49 → 下一抽必出 SSR（紫柱）；大保底计到 99 → 下一抽必出当期 UP（UR 彩虹柱）。

const SCENE_PATH := "res://scenes/gacha.tscn"

## 演出：抬起 0.55s + 撕包 0.42s×0.75 → 约 0.9s 后开结果层；光柱持续约 1.3s
const PILLAR_DELAY := 1.35
const SETTLE_DELAY := 3.4
const TIMEOUT_SECONDS := 30.0

var _stage := 0
var _elapsed := 0.0
var _wait_at := 0.0
var _capture := false
var _saved := false
var _mode := "page"
var _out := "res://shots/gacha.png"


func _initialize() -> void:
	RenderingServer.frame_post_draw.connect(_on_frame_drawn)
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_mode = str(args[0])
	if args.size() >= 2:
		var w := float(args[1])
		if w > 0.0:
			_wait_at = w
	_out = "res://shots/%s.png" % ("gacha" if _mode == "page" else "gacha_" + _mode)
	if _wait_at <= 0.0:
		_wait_at = PILLAR_DELAY if _mode.begins_with("pillar") else SETTLE_DELAY


func _process(delta: float) -> bool:
	if _stage == 0:
		var ps: PackedScene = load(SCENE_PATH)
		if ps == null:
			push_error("[shot] 无法加载 %s" % SCENE_PATH)
			quit(1)
			return true
		var scene := ps.instantiate()
		root.add_child(scene)
		_stage = 1
		_trigger(scene)
		return false

	_elapsed += delta
	if _saved:
		quit(0)
		return true
	if _stage == 1 and _elapsed >= _wait_at:
		_stage = 2
		_capture = true
		return false
	if _elapsed >= TIMEOUT_SECONDS:
		push_error("[shot] 超时未取到画面")
		quit(1)
		return true
	return false


## 触发要拍的画面。进场先等一帧：界面脚本 _ready 里才建标签页 / 刷资源，
## 紧接着点按钮会拿不到还没建好的池子。
func _trigger(scene: Node) -> void:
	_top_up()
	match _mode:
		"page":
			pass
		"reveal1":
			scene.call_deferred("_on_pull", 1)
		"reveal10":
			scene.call_deferred("_on_pull", 10)
		"rate":
			scene.call_deferred("_toggle_rate_panel", true)
		"shop":
			scene.call_deferred("_toggle_shop_panel", true)
		"pillar_ssr":
			_force_pity("standard", 49, 0)
			scene.call_deferred("_on_pull", 1)
		"pillar_ur":
			_force_pity("limited", 0, 99)
			var tabs: Node = scene.get_node_or_null("%PoolTabs")
			if tabs != null and tabs.get_child_count() > 1:
				(tabs.get_child(1) as Button).pressed.emit()
			scene.call_deferred("_on_pull", 1)
		_:
			push_error("[shot] 未知模式 %s" % _mode)
			quit(1)


func _force_pity(group: String, small: int, large: int) -> void:
	var save := root.get_node_or_null("SaveDB")
	if save == null:
		return
	save.call("set_pity", group, small, large)
	save.call("save_profile")
	print("[shot] 已把 %s 组保底设为 小 %d / 大 %d" % [group, small, large])


## 截图不能靠运气，也不能靠存档恰好有钱：先把券 / 钻石补足，保证每次都能真抽出来
func _top_up() -> void:
	var save := root.get_node_or_null("SaveDB")
	if save == null:
		return
	save.call("add_material", "ticket_basic", 200, false)
	save.call("add_material", "ticket_advanced", 200, false)
	save.call("add_currency", "bound_gem", 100000, false)
	save.call("add_currency", "guild_token", 100000, false)
	save.call("save_profile")
	print("[shot] 已补足召唤资源")


func _on_frame_drawn() -> void:
	if not _capture or _saved:
		return
	var tex := root.get_texture()
	if tex == null:
		push_error("[shot] 视口纹理为空")
		return
	var img := tex.get_image()
	if img == null:
		push_error("[shot] 视口图像为空（渲染器可能未初始化）")
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	var err := img.save_png(_out)
	if err != OK:
		push_error("[shot] 保存失败：%s" % error_string(err))
		return
	_capture = false
	_saved = true
	print("[shot] 已保存 %s  尺寸=%s" % [_out, str(img.get_size())])
