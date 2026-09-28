extends SceneTree
## smoke_main_menu.gd —— 主界面冒烟测试入口
##
## 用法：
##   Godot --headless --path <项目> --script res://tools/smoke_main_menu.gd
##
## 本文件刻意不引用任何 autoload：--script 模式下被直接加载的脚本，编译期
## 拿不到 autoload 全局标识符。所以先等主循环跑起来，再动态 load() 测试套件。

const SUITE_PATH := "res://tools/suites/main_menu_suite.gd"

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
