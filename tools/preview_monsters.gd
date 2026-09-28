extends SceneTree
## preview_monsters.gd —— 怪物图标预览图（视觉自检用）
##
## 用法（必须带窗口）：
##   Godot --path <项目> --resolution 1600x900 --script res://tools/preview_monsters.gd
##
## 产出：res://shots/monsters_sheet.png
## 目的：14 只怪是脚本参数化生成的，肉眼过一遍轮廓/配色是否区分得开，
##       再进战场；否则战场截图里分不清「图标糊了」还是「布局歪了」。

const OUT_PATH := "res://shots/monsters_sheet.png"
const ICON_DIR := "res://assets/icons/monsters"
const COLS := 7
const CELL := Vector2(200, 200)
const ORIGIN := Vector2(70, 120)

var _elapsed := 0.0
var _capture := false
var _saved := false


func _initialize() -> void:
	RenderingServer.frame_post_draw.connect(_on_frame_drawn)
	_build()


func _build() -> void:
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	get_root().add_child(root)

	var bg := ColorRect.new()
	bg.color = Color("#141026")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	var names: Array = _icon_names()
	var i := 0
	for nm in names:
		var col := i % COLS
		var row := i / COLS
		var pos := ORIGIN + Vector2(float(col) * CELL.x, float(row) * (CELL.y + 30.0))

		var tr := TextureRect.new()
		tr.texture = load("%s/%s" % [ICON_DIR, nm])
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.position = pos
		tr.size = CELL
		root.add_child(tr)

		var l := Label.new()
		l.text = str(nm).trim_prefix("mob_")
		l.position = pos + Vector2(0, CELL.y)
		l.size = Vector2(CELL.x, 26)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 17)
		l.add_theme_color_override("font_color", Color("#CFE6FF"))
		root.add_child(l)
		i += 1

	print("[preview] 预览 %d 只怪" % names.size())


func _icon_names() -> Array:
	var out: Array = []
	var d := DirAccess.open(ICON_DIR)
	if d == null:
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if f.ends_with(".svg"):
			out.append(f)
		f = d.get_next()
	d.list_dir_end()
	out.sort()
	return out


func _process(delta: float) -> bool:
	_elapsed += delta
	if _saved:
		quit(0)
		return true
	if not _capture and _elapsed >= 1.2:
		_capture = true
	if _elapsed >= 12.0:
		push_error("[preview] 超时未取到画面")
		quit(1)
		return true
	return false


func _on_frame_drawn() -> void:
	if not _capture or _saved:
		return
	var tex := get_root().get_texture()
	if tex == null:
		return
	var img := tex.get_image()
	if img == null:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	var err := img.save_png(OUT_PATH)
	if err != OK:
		push_error("[preview] 保存失败：%s" % error_string(err))
		return
	_capture = false
	_saved = true
	print("[preview] 已保存 %s  尺寸=%s" % [OUT_PATH, str(img.get_size())])
