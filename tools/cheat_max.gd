extends SceneTree
## cheat_max.gd —— 修改存档：玩家等级 → 99，全部卡片满级满星
##
## 用法：
##   Godot --headless --path <项目> --script res://tools/cheat_max.gd
##
## 效果：
##   1. 玩家等级设为 99，经验清零，exp_max 按等级曲线重算
##   2. 持有全部角色卡（不存在则补发），每张卡等级 = 品质 level_cap，星级 = 品质 star_max

var _frames := 0

func _process(_delta: float) -> bool:
	if _frames < 4:
		_frames += 1
		return false
	# 等 autoload 注册完成后执行
	_run()
	return true


func _run() -> void:
	var game_db = root.get_node("GameDB")
	var save_db = root.get_node("SaveDB")

	# ---------- 1. 玩家等级 → 99 ----------
	var target_level: int = 99
	var p: Dictionary = save_db.player()
	p["level"] = target_level
	p["exp"] = 0
	p["exp_max"] = game_db.player_exp_max(target_level)
	print("[cheat] 玩家等级 → %d, exp_max=%d" % [target_level, p["exp_max"]])

	# ---------- 2. 全部卡片满级满星 ----------
	var characters: Array = game_db.characters()
	var added: int = 0
	var upgraded: int = 0

	for cfg_variant in characters:
		var cfg: Dictionary = cfg_variant
		var char_id := str(cfg.get("id", ""))
		if char_id == "":
			continue

		var rarity_id := str(cfg.get("rarity", "R"))
		var rarity_cfg: Dictionary = game_db.rarity(rarity_id)
		var max_star: int = int(rarity_cfg.get("star_max", 3))
		var max_level: int = int(rarity_cfg.get("level_cap", 50))

		# 查找已有卡片
		var card: Dictionary = save_db.find_card(char_id)
		if card.is_empty():
			# 不存在则补发
			card = save_db.grant_card(char_id, false)
			added += 1

		# 设为满级满星
		card["level"] = max_level
		card["star"] = max_star
		card["exp"] = 0
		upgraded += 1

	# 统一落盘
	save_db.save_profile()
	print("[cheat] 卡片处理完成：新增 %d 张，满级满星 %d 张（共 %d 个角色）" % [added, upgraded, characters.size()])

	# ---------- 3. 上阵编队填满（等级99 → team_max 应为 9） ----------
	var team_max: int = save_db.team_max()
	var cards: Array = save_db.cards()
	var entries: Array = []
	var slot: int = 1
	for c in cards:
		if slot > team_max:
			break
		var cid: String = str(c.get("char_id", ""))
		var ccfg: Dictionary = game_db.character(cid)
		var prefer: int = int(ccfg.get("prefer_slot", slot))
		# 使用 prefer_slot，若冲突则顺序填
		var final_slot: int = prefer if prefer >= 1 and prefer <= 9 else slot
		# 简单去重：确保槽位不冲突
		while any_slot_taken(entries, final_slot):
			final_slot += 1
			if final_slot > 9:
				break
		if final_slot <= 9:
			entries.append({"slot": final_slot, "char_id": cid})
			slot += 1
	var fixed: Array = save_db.set_team(entries)
	print("[cheat] 上阵编队 → %d 人（上限 %d）" % [fixed.size(), team_max])

	print("[cheat] 全部完成 ✓")
	quit(0)


func any_slot_taken(entries: Array, s: int) -> bool:
	for e in entries:
		if int(e.get("slot", 0)) == s:
			return true
	return false
