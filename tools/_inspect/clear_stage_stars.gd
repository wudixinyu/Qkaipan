extends SceneTree
## 一次性清理脚本：把用户存档里遗留的关卡星记录清空（默认无星）。
## 用法：Godot --headless --path <项目> --script res://tools/_inspect/clear_stage_stars.gd

var _frames := 0


func _process(_delta: float) -> bool:
	if _frames == 0:
		_frames += 1
		return false
	var game_db: Node = load("res://scripts/game_db.gd").new()
	root.add_child(game_db)  # _ready 里完成配置载入
	var save_db: Node = load("res://scripts/save_db.gd").new()
	root.add_child(save_db)  # _ready 里 load_profile()

	save_db.progress()["stage_stars"] = {}
	save_db.progress()["stage_clears"] = {}
	save_db.save_profile()
	print("[clear_stage_stars] 已清空 progress.stage_stars / stage_clears")
	quit(0)
	return true
