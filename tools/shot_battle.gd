extends SceneTree
## shot_battle.gd —— 战斗界面截图自检
##
## 用法（必须带窗口，headless 的假渲染器取不到画面）：
##   Godot --path <项目> --resolution 1920x1080 --script res://tools/shot_battle.gd -- 1003 4.0 3
##   参数：<关卡 id> <抓图前等待秒数> <初始倍速索引 0/1/2> [skip]
##   第 4 个参数给 "skip" 时，加载后直接跳到战斗结束，抓的是结算面板
##   （星级评分行 / 战利品持有量 / 物资统计都在这一屏，等待秒数要给够 1.5s 以上）。
##
## 产出：res://shots/battle.png
## 说明：战斗是逐拍演出的，截图前等待的秒数决定了画面停在「第几拍」——
##       想抓「第一回合齐射」就等短一点，想抓「双方残阵」就等长一点。

const SCENE_PATH := "res://scenes/battle.tscn"
const OUT_PATH := "res://shots/battle.png"
const RESULT_OUT_PATH := "res://shots/battle_result.png"
const TIMEOUT_SECONDS := 60.0

var _stage_id := 1003
var _wait := 4.0
var _speed := 2
var _skip := false
var _out_path := OUT_PATH
var _elapsed := 0.0
var _capture := false
var _saved := false
var _spawned := false
var _scene: Node = null


func _initialize() -> void:
	RenderingServer.frame_post_draw.connect(_on_frame_drawn)
	_parse_args()


func _parse_args() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() >= 1 and int(a[0]) > 0:
		_stage_id = int(a[0])
	if a.size() >= 2 and float(a[1]) > 0.0:
		_wait = float(a[1])
	if a.size() >= 3:
		_speed = clampi(int(a[2]), 0, 2)
	if a.size() >= 4:
		_skip = str(a[3]).to_lower() == "skip"
	if _skip:
		_out_path = RESULT_OUT_PATH


func _process(delta: float) -> bool:
	if not _spawned:
		_spawn()
		_spawned = true
		return false

	_elapsed += delta
	if _saved:
		quit(0)
		return true
	if not _capture and _elapsed >= _wait:
		_capture = true
		return false
	if _elapsed >= TIMEOUT_SECONDS:
		push_error("[shot] 超时未取到画面")
		quit(1)
		return true
	return false


## --script 模式下本文件在编译期看不到 autoload 的全局名（BattleCtx 会报
## "Identifier not found"），所以这里必须走运行期节点查找 + 动态调用。
func _begin_battle() -> void:
	var ctx := get_root().get_node_or_null("/root/BattleCtx")
	if ctx == null:
		push_error("[shot] 找不到 BattleCtx autoload")
		return
	ctx.call("begin_from_stage", _stage_id, "shot")


func _spawn() -> void:
	var ps: PackedScene = load(SCENE_PATH)
	if ps == null:
		push_error("[shot] 无法加载 %s" % SCENE_PATH)
		quit(1)
		return
	_begin_battle()
	_scene = ps.instantiate()
	get_root().add_child(_scene)
	# 直接推倍速，省得为截图等太久（1× 每拍 0.72s，3× 是 0.24s）
	_scene.set("_speed_index", _speed)
	var btn: Button = _scene.get_node_or_null("%SpeedButton")
	if btn != null:
		btn.text = "速度 %s" % ["1×", "2×", "3×"][_speed]
	if _skip:
		# 结算面板要等 SETTLE_DELAY 才弹，所以这里的等待秒数得给够（≥1.5s）
		_scene.call_deferred("_on_skip")
		print("[shot] 跳过战斗，直接抓结算面板（等待 %.1fs）" % _wait)
	print("[shot] 已加载战斗场景：关卡 %d，等待 %.1fs 后抓图" % [_stage_id, _wait])


func _on_frame_drawn() -> void:
	if not _capture or _saved:
		return
	var tex := get_root().get_texture()
	if tex == null:
		push_error("[shot] 视口纹理为空")
		return
	var img := tex.get_image()
	if img == null:
		push_error("[shot] 视口图像为空")
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	var err := img.save_png(_out_path)
	if err != OK:
		push_error("[shot] 保存失败：%s" % error_string(err))
		return
	_capture = false
	_saved = true
	print("[shot] 已保存 %s  尺寸=%s" % [_out_path, str(img.get_size())])
