extends SceneTree
## shot_formation.gd —— 卡牌选择与编队页截图自检
##
## 用法（必须带窗口，headless 的假渲染器取不到画面）：
##   Godot --path <项目> --resolution 1920x1080 --script res://tools/shot_formation.gd
##
## 可选的第一个参数是「抓图前等待秒数」，默认 2.8（入场动效约 0.6s，留足余量）。
##
## 流程：载入场景 -> 等动效播完（按真实时间计）-> 抓视口 -> 存 res://shots/

const SCENE_PATH := "res://scenes/formation.tscn"
const OUT_PATH := "res://shots/formation.png"

const DEFAULT_SETTLE := 2.8
const TIMEOUT_SECONDS := 24.0

var _stage := 0
var _elapsed := 0.0
var _capture := false
var _saved := false
var _settle := DEFAULT_SETTLE


func _initialize() -> void:
	RenderingServer.frame_post_draw.connect(_on_frame_drawn)
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_settle = maxf(0.6, float(args[0]))


func _process(delta: float) -> bool:
	if _stage == 0:
		var ps: PackedScene = load(SCENE_PATH)
		if ps == null:
			push_error("[shot] 无法加载 %s" % SCENE_PATH)
			quit(1)
			return true
		get_root().add_child(ps.instantiate())
		_stage = 1
		return false

	_elapsed += delta

	if _saved:
		quit(0)
		return true

	if _stage == 1 and _elapsed >= _settle:
		_stage = 2
		_capture = true
		return false

	if _elapsed >= TIMEOUT_SECONDS:
		push_error("[shot] 超时未取到画面")
		quit(1)
		return true

	return false


func _on_frame_drawn() -> void:
	if not _capture or _saved:
		return
	var vp := get_root()
	var tex := vp.get_texture()
	if tex == null:
		push_error("[shot] 视口纹理为空")
		return
	var img := tex.get_image()
	if img == null:
		push_error("[shot] 视口图像为空（渲染器可能未初始化）")
		return

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	var err := img.save_png(OUT_PATH)
	if err != OK:
		push_error("[shot] 保存失败：%s" % error_string(err))
		return

	_capture = false
	_saved = true
	print("[shot] 已保存 %s  尺寸=%s  窗口=%s"
		% [OUT_PATH, str(img.get_size()), str(DisplayServer.window_get_size())])
