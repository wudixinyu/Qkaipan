class_name GrowthCore
extends RefCounted
## GrowthCore —— 养成数值换算的纯函数层（不认识 autoload、不读盘、不碰节点）
##
## 存在的理由：属性公式原本在 RealmDB.stats_of、tools/build_main_menu.gd、
## tools/build_formation.gd 各有一份，战力公式在 RealmDB 与 BattleCore 各有一份。
## 构建脚本跑在没有 autoload 的 --script 环境里，只能自己抄一遍，于是「界面预览的数」
## 和「战斗里真正用的数」随时可能分叉。这里收成一份，两边都通过
## `const GROWTH := preload("res://scripts/growth_core.gd")` 调用。
##
## 最终属性 = (基础值 + 成长值 × (等级-1)) × 星级系数

const ATTR_KEYS := ["hp", "atk", "def", "mres"]
const RATE_KEYS := ["crit", "crit_dmg", "hit"]


## 星级系数：bonus 即 growth.star_up.per_star_attr_bonus，索引 = 星级-1，越界钳制
static func star_multiplier(bonus: Array, star: int) -> float:
	if bonus.is_empty():
		return 1.0
	return 1.0 + float(bonus[clampi(star - 1, 0, bonus.size() - 1)])


## cfg : characters 表里的一条（含 base / growth）
## bonus: growth.star_up.per_star_attr_bonus
static func stats_of(cfg: Dictionary, level: int, star: int, bonus: Array) -> Dictionary:
	var base: Dictionary = cfg.get("base", {})
	var growth: Dictionary = cfg.get("growth", {})
	var mult := star_multiplier(bonus, star)
	var scaled := ["hp", "atk", "def", "mres", "spd"]

	var out := {}
	for k in scaled:
		var v := float(base.get(k, 0)) + float(growth.get(k, 0)) * float(level - 1)
		out[k] = int(round(v * mult))
	# crit / crit_dmg / hit 是比率，配置里没有成长字段，原样透传
	for k in RATE_KEYS:
		out[k] = float(base.get(k, 0.0))
	return out


## 战力权重，全项目统一口径（选关建议战力 / 编队总战力 / 战斗内我方战力）
static func power_of(hp: float, atk: float, defense: float, mres: float,
		spd: float, crit: float) -> int:
	return int(round(hp * 0.12 + atk * 2.4 + defense * 1.6 + mres * 1.1
		+ spd * 2.0 + crit * 600.0))


static func battle_power(stats: Dictionary) -> int:
	return power_of(float(stats.get("hp", 0)), float(stats.get("atk", 0)),
		float(stats.get("def", 0)), float(stats.get("mres", 0)),
		float(stats.get("spd", 0)), float(stats.get("crit", 0.0)))
