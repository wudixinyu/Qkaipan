extends SceneTree
## smoke_adventure_data.gd —— 冒险关卡选择数据冒烟测试入口
##
## 用法：
##   Godot --headless --path <项目> --script res://tools/smoke_adventure_data.gd
##
## 与 smoke_main_menu.gd 同构：本文件不引用任何 autoload，等主循环起来后
## 再动态 load() 测试套件，绕开 --script 模式下 autoload 全局名不可见的问题。

const SUITE_PATH := "res://tools/suites/adventure_data_suite.gd"

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
