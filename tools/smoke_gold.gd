extends SceneTree
## smoke_gold.gd —— 金币经济闭环冒烟测试入口
##
## 用法：
##   Godot --headless --path <项目> --script res://tools/smoke_gold.gd
##
## 本文件刻意不引用任何 autoload：--script 模式下被直接加载的脚本，编译期
## 拿不到 autoload 全局标识符。所以先等主循环跑起来，再动态 load() 测试套件。

const SUITE_PATH := "res://tools/suites/gold_suite.gd"

var _frames := 0
var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_frames += 1
	if _frames < 4:
		return false
	_done = true
	var suite: RefCounted = load(SUITE_PATH).new()
	var failed: int = int(suite.run(self))
	quit(0 if failed == 0 else 1)
	return true
