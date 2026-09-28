extends SceneTree
## shot_formation_scroll.gd —— 编队页卡排「左右拖拽滚动」截图自检
##
## 用法（必须带窗口，headless 的假渲染器取不到画面）：
##   Godot --path <项目> --resolution 1920x1080 --script res://tools/shot_formation_scroll.gd
##
## 流程：载入场景 -> 等入场动效 -> 抓「滚动前」-> 用 push_input 注入一段
## 真实的按下-拖动-松手（走完整 _input / GUI 路径，含惯性滑行）
## -> 等 0.9s 滑行停稳 -> 抓「滚动后」-> 打印滚动量。
##
## 产出：res://shots/formation_scroll_before.png / formation_scroll_after.png

const SCENE_PATH := "res://scenes/formation.tscn"
const BEFORE_PATH := "res://shots/formation_scroll_before.png"
const AFTER_PATH := "res://shots/formation_scroll_after.png"

const SETTLE := 2.4          ## 入场动效等待
const PRESS_AT := Vector2(960, 460)
const DRAG_TO := Vector2(640, 460)
const DRAG_FRAMES := 12      ## 拖动分几帧推完
const GLIDE_WAIT := 0.9      ## 松手惯性等待

var _stage := 0
var _elapsed := 0.0
var _drag_frame := 0
var _capture := ""
var _shots: Dictionary = {}
var _scroll_before := NAN
var _last_at := Vector2.ZERO
var _scene: Node


func _initialize() -> void:
	RenderingServer.frame_post_draw.connect(_on_frame_drawn)


func _fan() -> Node:
	return _scene.get_node_or_null("%CardStage")


func _push(ev: InputEvent) -> void:
	get_root().push_input(ev)


func _motion(at: Vector2, pressed: bool) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = at
	mm.global_position = at
	mm.relative = at - _last_at
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	_last_at = at
	_push(mm)


func _button(at: Vector2, pressed: bool) -> void:
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = pressed
	mb.position = at
	mb.global_position = at
	_push(mb)


func _process(delta: float) -> bool:
	_elapsed += delta
	match _stage:
		0:
			var ps: PackedScene = load(SCENE_PATH)
			if ps == null:
				push_error("[shot] 无法加载 %s" % SCENE_PATH)
				quit(1)
				return true
			_scene = ps.instantiate()
			get_root().add_child(_scene)
			_stage = 1
		1:
			if _elapsed >= SETTLE:
				_scroll_before = float(_fan().get("_scroll"))
				_capture = BEFORE_PATH
				_stage = 2
				# 先悬停一下再按下：拖拽武装依赖 gui_get_hovered_control()
				_last_at = PRESS_AT
				_motion(PRESS_AT, false)
				_button(PRESS_AT, true)
				_drag_frame = 0
		2:
			# 等抓完「滚动前」再开始拖（抓图在 frame_post_draw 回调里）
			if _capture == "":
				_stage = 3
		3:
			_drag_frame += 1
			var t := float(_drag_frame) / float(DRAG_FRAMES)
			var at := PRESS_AT.lerp(DRAG_TO, clampf(t, 0.0, 1.0))
			_motion(at, true)
			if _drag_frame >= DRAG_FRAMES:
				_button(DRAG_TO, false)
				_motion(DRAG_TO, false)
				_stage = 4
		4:
			if _elapsed >= SETTLE + DRAG_FRAMES / 60.0 + GLIDE_WAIT:
				_capture = AFTER_PATH
				_stage = 5
		5:
			if _capture == "":
				var moved := float(_fan().get("_scroll")) - _scroll_before
				print("[shot] _scroll %.1f -> %.1f（位移 %.1f px）"
					% [_scroll_before, float(_fan().get("_scroll")), moved])
				if absf(moved) < 50.0:
					push_error("[shot] 拖拽后滚动量过小，左右滚动可能没生效")
					quit(1)
					return true
				quit(0)
				return true

	if _elapsed >= 24.0:
		push_error("[shot] 超时")
		quit(1)
		return true
	return false


func _on_frame_drawn() -> void:
	if _capture == "":
		return
	var vp := get_root()
	var tex := vp.get_texture()
	if tex == null:
		return
	var img := tex.get_image()
	if img == null:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	var out: String = _capture
	var err := img.save_png(out)
	_capture = ""
	if err != OK:
		push_error("[shot] 保存失败：%s" % error_string(err))
		return
	_shots[out] = img.get_size()
	print("[shot] 已保存 %s  尺寸=%s" % [out, str(img.get_size())])
