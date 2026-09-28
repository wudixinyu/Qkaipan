extends SceneTree
## shot_collection.gd —— 卡片图鉴界面截图自检
##
## 用法（必须带窗口：headless 的假渲染器取不到画面）：
##   Godot --path <项目> --resolution 1920x1080 --script res://tools/shot_collection.gd -- [mode] [wait]
##
##   mode = page      全部卡片（默认）            → shots/collection.png
##          owned     已获取筛选（先发卡再拍）     → shots/collection_owned.png
##          unowned   未获取筛选                  → shots/collection_unowned.png
##          detail    详情弹层（点开第一张卡）     → shots/collection_detail.png
##
## 注意：owned 模式会真实发卡写档。跑之前先备份
##   %APPDATA%/Godot/app_userdata/卡牌大冒险/save.json，跑完还原。

const SCENE_PATH := "res://scenes/collection.tscn"
const SETTLE_DELAY := 1.2
const TIMEOUT_SECONDS := 30.0

var _stage := 0
var _elapsed := 0.0
var _wait_at := 0.0
var _capture := false
var _saved := false
var _mode := "page"
var _out := "res://shots/collection.png"


func _initialize() -> void:
	RenderingServer.frame_post_draw.connect(_on_frame_drawn)
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_mode = str(args[0])
	if args.size() >= 2:
		var w := float(args[1])
		if w > 0.0:
			_wait_at = w
	_out = "res://shots/%s.png" % ("collection" if _mode == "page" else "collection_" + _mode)
	if _wait_at <= 0.0:
		_wait_at = SETTLE_DELAY


func _process(delta: float) -> bool:
	if _stage == 0:
		# 先发卡通档再进场：界面 _ready 里就按真实持有量重建网格
		_grant_cards()
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


## 触发要拍的画面（网格已由界面 _ready 建好）
func _trigger(scene: Node) -> void:
	match _mode:
		"page":
			pass
		"owned":
			scene.call("_apply_filter", "owned")
		"unowned":
			scene.call("_apply_filter", "unowned")
		"detail":
			scene.call("_open_detail", "knight_rock")
		_:
			push_error("[shot] 未知模式 %s" % _mode)
			quit(1)


## 已获取态要有卡可拍：发 3 张（与冒烟测试同一组），写档供界面读取。
## 已持有则跳过：重复拍图不会把星级一路叠上去（grant_card 对已有卡是升星）。
func _grant_cards() -> void:
	var save := root.get_node_or_null("SaveDB")
	if save == null:
		return
	var granted := 0
	for id in ["knight_rock", "pyro_girl", "elf_ranger"]:
		var owned: Dictionary = save.call("find_card", id)
		if owned.is_empty():
			save.call("grant_card", id, false)
			granted += 1
	save.call("save_profile")
	print("[shot] 新发 %d 张卡并写档（已持有则跳过）" % granted)


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
