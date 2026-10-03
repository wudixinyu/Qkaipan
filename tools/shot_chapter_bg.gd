extends SceneTree
## shot_chapter_bg.gd —— 三章大地图背景连拍自检
##
## 用法（必须带窗口，headless 的假渲染器取不到画面）：
##   Godot --path <项目> --resolution 1920x1080 --script res://tools/shot_chapter_bg.gd
##
## 流程：载入选关页 -> 依次 _switch_chapter(ch1/ch2/ch3) -> 每章等背景与节点稳定 ->
##       抓视口存 res://shots/stage_select_chN.png。_switch_chapter 不校验解锁门禁，
##       故无需作弊存档即可预览各章底图。

const SCENE_PATH := "res://scenes/stage_select.tscn"
const CHAPTERS := ["ch1", "ch2", "ch3"]
const SETTLE_SECONDS := 1.8
const TIMEOUT_SECONDS := 30.0

var _scene: Node
var _stage := 0        ## 0=待实例化 1=等待稳定 2=待抓帧 ..
var _chap_idx := -1
var _elapsed := 0.0
var _capture := false
var _saved := false


func _initialize() -> void:
	RenderingServer.frame_post_draw.connect(_on_frame_drawn)


func _process(delta: float) -> bool:
	if _stage == 0:
		var ps: PackedScene = load(SCENE_PATH)
		if ps == null:
			push_error("[shot] 无法加载 %s" % SCENE_PATH)
			quit(1)
			return true
		_scene = ps.instantiate()
		get_root().add_child(_scene)
		_next_chapter()
		return false

	_elapsed += delta
	if _saved:
		_next_chapter()
		_saved = false
		return false

	if _stage == 1 and _elapsed >= SETTLE_SECONDS:
		_stage = 2
		_capture = true
		return false

	if _elapsed >= TIMEOUT_SECONDS:
		push_error("[shot] 超时未取到画面")
		quit(1)
		return true
	return false


## 推进到下一章：切章节 → 重置计时 → 回到等待稳定阶段；三章拍完退出
func _next_chapter() -> void:
	_chap_idx += 1
	if _chap_idx >= CHAPTERS.size():
		quit(0)
		return
	var id: String = CHAPTERS[_chap_idx]
	_scene.call("_switch_chapter", id)
	_elapsed = 0.0
	_stage = 1


func _out_path() -> String:
	return "res://shots/stage_select_%s.png" % CHAPTERS[_chap_idx]


func _on_frame_drawn() -> void:
	if not _capture or _saved:
		return
	var img := get_root().get_texture().get_image()
	if img == null:
		push_error("[shot] 视口图像为空")
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	var err := img.save_png(_out_path())
	if err != OK:
		push_error("[shot] 保存失败：%s" % error_string(err))
		return
	_capture = false
	_saved = true
	print("[shot] 已保存 %s  尺寸=%s" % [_out_path(), str(img.get_size())])
