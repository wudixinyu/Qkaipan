extends SceneTree
## smoke_gacha.gd —— 抽卡系统冒烟测试入口
##
## 用法：
##   Godot --headless --path <项目> --script res://tools/smoke_gacha.gd
##
## 与其它 smoke_*.gd 同一套路：直接 --script 加载的脚本在编译期看不到 autoload
## 全局标识符，所以先等主循环跑起来，再动态 load() 测试套件。

const SUITE_PATH := "res://tools/suites/gacha_suite.gd"

var _frames := 0
var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_frames += 1
	if _frames < 4:
		return false
	_done = true

	if not ResourceLoader.exists(SUITE_PATH):
		push_error("[smoke] 找不到测试套件 %s" % SUITE_PATH)
		quit(1)
		return true

	var suite: RefCounted = load(SUITE_PATH).new()
	var result: Dictionary = suite.run(self)
	quit(0 if int(result.get("failed", 1)) == 0 else 1)
	return true
