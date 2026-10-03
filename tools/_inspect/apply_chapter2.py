#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""apply_chapter2.py —— 把第二章《机械迷城》全关卡设计落进 game_data.json

用法：
    python tools/_inspect/apply_chapter2.py            # 幂等写入并打印核对表

与 apply_chapter1.py 的关系（沿用第一章的结构，但**只增量、不覆写第一章**）：
  - monsters.table：MERGE 17 只新怪（ch1 的 14 只原样保留），并追加 order；
  - chapter_stages：ch1 的那份原样不动，新增 adventure.extra_chapter_stages 挂 ch2 的 10 关，
    GameDB.chapter_stages() 会把两份聚合成一张跨章的表，chapter_stage(id) 自然跨章命中；
  - select_map.sections：ch1 的 3 节原样保留，追加 ch2 的 3 节（3-3-4，带 chapter_id）；
  - chapter_tabs / chapters：ch2 元信息改名为《机械迷城》，补 unlock_stage=1010（通关一章 Boss 解锁）。

power_scale 反解口径与第一章完全一致（复用同一 power_of / solve_scale）：
  使「缩放后敌方总战力」= 建议战力 × difficulty。只缩放 hp/atk/def/mres，
  spd/crit 不参与强度缩放。

机制表达（沿用第一章「描述性机制 + 现有 skill/traits/env」的取舍）：
  - 能量电容器【电脉冲】→ 可执行：skill 用 attack/all_foes/stun_chance=1，引擎真能全队眩晕；
  - 防御塔核心【真实伤害】、机械洪流【召唤】、移动地砖【交换】、传送带【非机械减速】、
    符文核心/巨神兵【免疫控制】→ 引擎暂无对应原语，写进 mechanic 文本描述，战斗用可执行技能近似。
"""

import io
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DATA = os.path.join(ROOT, "data", "game_data.json")
ICON_BASE = "res://assets/icons/monsters"

ISLE_PLAIN = "res://assets/icons/stage_isle_plain.svg"
ISLE_CASTLE = "res://assets/icons/stage_isle_castle.svg"
ISLE_STORM = "res://assets/icons/stage_isle_storm.svg"

# --------------------------------------------------------------------------- 怪物表（17 只，MERGE 进 ch1）
# base 面板口径与 characters[].base / apply_chapter1.MONSTERS 一致，便于 RealmDB 战力估值复用。
MONSTERS = {
    "mech_spider": {
        "name": "机械蜘蛛", "element": "earth", "role": "warrior",
        "desc": "八条节肢、发条驱动的巡逻机械，扑上来越靠越近。",
        "base": {"hp": 520, "atk": 62, "def": 70, "mres": 40, "crit": 0.05, "crit_dmg": 1.5, "spd": 96},
        "action": {"kind": "attack", "target": "nearest_front", "damage": "phys", "mult": 1.0},
    },
    "clockwork_soldier": {
        "name": "发条步兵", "element": "wind", "role": "warrior",
        "desc": "上了发条的机械士兵，动作僵硬但胜在源源不绝。",
        "base": {"hp": 600, "atk": 66, "def": 90, "mres": 50, "crit": 0.04, "crit_dmg": 1.5, "spd": 88},
        "action": {"kind": "attack", "target": "nearest_front", "damage": "phys", "mult": 1.0},
    },
    "repair_dog": {
        "name": "机械维修犬", "element": "light", "role": "healer",
        "desc": "叼着扳手在机械堆里穿梭，只要它还在，周围的机械就修不完。",
        "base": {"hp": 560, "atk": 70, "def": 70, "mres": 110, "crit": 0.04, "crit_dmg": 1.5, "spd": 110},
        "action": {"kind": "attack", "target": "nearest_front", "damage": "magic", "mult": 0.6},
        "skill": {"kind": "heal_lowest", "interval": 1, "mult": 1.8,
                  "name": "焊修", "desc": "每次行动修复己方血量最低的机械单位，修复量为攻击力 180%"},
    },
    "steam_archer": {
        "name": "蒸汽弓箭手", "element": "fire", "role": "archer",
        "desc": "蒸汽助力的弩手，专挑阵型最后排最脆的那一个。",
        "base": {"hp": 480, "atk": 108, "def": 55, "mres": 48, "crit": 0.12, "crit_dmg": 1.6, "spd": 120},
        "action": {"kind": "attack", "target": "lowest_hp_back", "damage": "phys", "mult": 1.0},
    },
    "heavy_gear_guard": {
        "name": "重型齿轮卫兵", "element": "earth", "role": "tank",
        "desc": "浑身齿轮的重装机械，正面几乎推不动。",
        "base": {"hp": 1200, "atk": 80, "def": 260, "mres": 90, "crit": 0.02, "crit_dmg": 1.5, "spd": 60},
        "action": {"kind": "attack", "target": "nearest_front", "damage": "phys", "mult": 1.0},
        "traits": [
            {"id": "gear_plate", "name": "齿轮装甲", "desc": "物理减伤 25%", "phys_reduction": 0.25},
        ],
    },
    "energy_capacitor": {
        "name": "能量电容器", "element": "wind", "role": "support",
        "desc": "蓄满电荷的枢纽，每 3 回合放一道电脉冲，把对面全队电到当场定住。",
        "base": {"hp": 700, "atk": 130, "def": 70, "mres": 120, "crit": 0.06, "crit_dmg": 1.5, "spd": 92},
        "action": {"kind": "attack", "target": "nearest_front", "damage": "magic", "mult": 0.7},
        "skill": {"kind": "attack", "target": "all_foes", "damage": "magic", "mult": 0.5, "aoe": True,
                  "interval": 3, "offset": 2, "stun_chance": 1.0, "stun_actions": 1,
                  "name": "电脉冲", "desc": "每 3 回合释放电脉冲，使敌方全队无法行动 1 回合"},
    },
    "steam_gunner": {
        "name": "蒸汽枪手", "element": "fire", "role": "warrior",
        "desc": "扛着蒸汽枪的机械兵，一枪顶得前排直往后退。",
        "base": {"hp": 640, "atk": 96, "def": 80, "mres": 60, "crit": 0.08, "crit_dmg": 1.5, "spd": 108},
        "action": {"kind": "attack", "target": "nearest_front", "damage": "phys", "mult": 1.05},
    },
    "supply_cart": {
        "name": "发条补给车", "element": "earth", "role": "support",
        "desc": "慢吞吞的补给机械，每到间隙就给全队打一轮气。",
        "base": {"hp": 720, "atk": 50, "def": 90, "mres": 100, "crit": 0.03, "crit_dmg": 1.5, "spd": 80},
        "action": {"kind": "attack", "target": "nearest_front", "damage": "magic", "mult": 0.5},
        "skill": {"kind": "buff_atk", "interval": 2, "offset": 1, "target": "all_allies", "value": 0.1,
                  "max_stacks": 3, "name": "补给", "desc": "每 2 回合为己方全队提升 10% 攻击力，最多叠 3 层"},
    },
    "ancient_gargoyle": {
        "name": "远古石像鬼", "element": "dark", "role": "tank",
        "desc": "遗迹里苏醒的石像，翅膀一收就往跟前压。",
        "base": {"hp": 1100, "atk": 92, "def": 200, "mres": 120, "crit": 0.04, "crit_dmg": 1.5, "spd": 70},
        "action": {"kind": "attack", "target": "nearest_front", "damage": "phys", "mult": 1.0},
    },
    "ancient_runemaster": {
        "name": "远古符文师", "element": "dark", "role": "mage",
        "desc": "刻满符文的施法者，一挥手符文乱流就扫过中排。",
        "base": {"hp": 720, "atk": 150, "def": 80, "mres": 150, "crit": 0.08, "crit_dmg": 1.5, "spd": 100},
        "action": {"kind": "attack", "target": "middle_row", "damage": "magic", "mult": 0.9, "aoe": True},
    },
    "rune_core": {
        "name": "符文核心", "element": "light", "role": "support",
        "desc": "悬浮的符文水晶，为周围的符文单位撑起魔法减伤盾，自身不吃任何控制。",
        "base": {"hp": 900, "atk": 60, "def": 100, "mres": 200, "crit": 0.03, "crit_dmg": 1.5, "spd": 70},
        "action": {"kind": "attack", "target": "nearest_front", "damage": "magic", "mult": 0.5},
        "skill": {"kind": "shield_all", "interval": 3, "offset": 2, "target": "all_allies", "mult": 1.0,
                  "name": "符文护盾", "desc": "每 3 回合为己方符文单位附加护盾（魔法减伤盾）"},
    },
    "steam_mgner": {
        "name": "蒸汽机枪手", "element": "fire", "role": "archer",
        "desc": "双管蒸汽机枪，一轮扫射压住对面一整排。",
        "base": {"hp": 700, "atk": 110, "def": 90, "mres": 60, "crit": 0.08, "crit_dmg": 1.5, "spd": 116},
        "action": {"kind": "attack", "target": "front_row", "damage": "phys", "mult": 0.7, "aoe": True},
    },
    "tower_core": {
        "name": "防御塔核心", "element": "earth", "role": "mage",
        "desc": "防御塔的中枢炮台，每 2 回合对来犯全队轰一发（真实伤害）。",
        "base": {"hp": 850, "atk": 168, "def": 120, "mres": 160, "crit": 0.05, "crit_dmg": 1.5, "spd": 84},
        "action": {"kind": "attack", "target": "nearest_front", "damage": "magic", "mult": 0.8},
        "skill": {"kind": "attack", "target": "all_foes", "damage": "magic", "mult": 1.6, "aoe": True,
                  "interval": 2, "offset": 1, "name": "炮击", "desc": "每 2 回合对敌方全队造成一轮轰击（描述为真实伤害）"},
    },
    "auto_shield_guard": {
        "name": "自动化盾卫", "element": "light", "role": "tank",
        "desc": "举着能量塔盾的自律机械，是巨神兵身前最后一堵墙。",
        "base": {"hp": 1300, "atk": 84, "def": 240, "mres": 110, "crit": 0.02, "crit_dmg": 1.5, "spd": 62},
        "action": {"kind": "attack", "target": "nearest_front", "damage": "phys", "mult": 1.0},
        "traits": [
            {"id": "auto_armor", "name": "复合装甲", "desc": "物理减伤 30%", "phys_reduction": 0.30},
        ],
    },
    "energy_relay": {
        "name": "能量中继站", "element": "wind", "role": "support",
        "desc": "战场后方的供能塔，源源不断给机械单位充能加劲。",
        "base": {"hp": 760, "atk": 70, "def": 90, "mres": 140, "crit": 0.04, "crit_dmg": 1.5, "spd": 90},
        "action": {"kind": "attack", "target": "nearest_front", "damage": "magic", "mult": 0.6},
        "skill": {"kind": "buff_atk", "interval": 1, "target": "all_allies", "value": 0.07,
                  "max_stacks": 4, "name": "能量供给", "desc": "每次行动为己方全队供能，提升 7% 攻击力，最多叠 4 层"},
    },
    "rune_priest": {
        "name": "符文祭司", "element": "dark", "role": "healer",
        "desc": "捧着符文经卷的祭司，只要它站着，符文单位就死不完。",
        "base": {"hp": 820, "atk": 82, "def": 90, "mres": 170, "crit": 0.04, "crit_dmg": 1.5, "spd": 106},
        "action": {"kind": "attack", "target": "nearest_front", "damage": "magic", "mult": 0.7},
        "skill": {"kind": "heal_lowest", "interval": 1, "mult": 1.9,
                  "name": "符文续命", "desc": "每次行动治疗己方血量百分比最低的单位，治疗量为攻击力 190%"},
    },
    "mech_colossus": {
        "name": "机械堡垒巨神兵", "element": "fire", "role": "tank",
        "desc": "机械迷城的镇城巨神兵，一具会坍塌重力的战争堡垒。",
        "boss": True,
        "base": {"hp": 5200, "atk": 240, "def": 340, "mres": 220, "crit": 0.05, "crit_dmg": 1.5, "spd": 70},
        "action": {"kind": "attack", "target": "nearest_front", "damage": "phys", "mult": 1.1},
        "traits": [
            {"id": "clock_heart", "name": "发条之心",
             "desc": "机械减伤 40%（物理），且不受任何控制效果影响",
             "phys_reduction": 0.40},
            {"id": "gravity_collapse", "name": "重力坍塌",
             "desc": "满能量释放，对敌方全队造成 250% 真实伤害并降低 30% 行动速度（持续 2 回合）",
             "mult": 2.5, "target": "all_foes", "damage": "magic", "aoe": True},
        ],
    },
}

# --------------------------------------------------------------------------- 关卡表
STAGES = [
    {
        "id": 2001, "name": "机械迷城·入口", "kind": "battle", "subtitle": "新场景机制引导关",
        "recommend_power": 13500, "stamina": 8, "pre_stage_id": 0, "is_boss": False,
        "difficulty": 0.85,
        "enemies": [{"slot": 1, "mob": "mech_spider"}, {"slot": 3, "mob": "mech_spider"},
                    {"slot": 5, "mob": "clockwork_soldier"}],
        "mechanic": "引导玩家了解新场景机制——【移动地砖】：每 2 回合，部分棋盘网格上的地砖会交换位置，站上的单位随之改变所在排。",
        "tactics": "开局会交换地砖的是前场两格，把输出别一次性压在最前排；两只机械蜘蛛扑上来得快，先手点掉中排的发条步兵更稳。",
        "rewards": [
            {"id": "gold", "name": "金币", "count": 3000, "icon": "res://assets/icons/icon_coin.svg"},
            {"id": "hero_exp", "name": "英雄经验", "count": 3500, "icon": "res://assets/icons/icon_star.svg"},
            {"id": "break_stone_2", "name": "2阶突破石", "count": 5, "icon": "res://assets/icons/icon_def.svg"},
        ],
    },
    {
        "id": 2002, "name": "发条车间", "kind": "battle", "subtitle": "普通战斗",
        "recommend_power": 14200, "stamina": 8, "pre_stage_id": 2001, "is_boss": False,
        "difficulty": 0.85,
        "enemies": [{"slot": 1, "mob": "clockwork_soldier"}, {"slot": 3, "mob": "clockwork_soldier"},
                    {"slot": 5, "mob": "repair_dog"}, {"slot": 8, "mob": "steam_archer"}],
        "mechanic": "【机械维修犬】每回合持续修复己方血量最低的机械单位，是这一关的续航核心。",
        "tactics": "两只发条步兵顶前、维修犬在中间续命、蒸汽弓箭手点你后排 —— 优先集火把维修犬摘掉，否则前排磨半天血条又满回去。",
        "rewards": [
            {"id": "gold", "name": "金币", "count": 3200, "icon": "res://assets/icons/icon_coin.svg"},
            {"id": "hero_exp", "name": "英雄经验", "count": 3800, "icon": "res://assets/icons/icon_star.svg"},
            {"id": "break_stone_2", "name": "2阶突破石", "count": 8, "icon": "res://assets/icons/icon_def.svg"},
        ],
    },
    {
        "id": 2003, "name": "核心枢纽", "kind": "elite", "subtitle": "精英挑战 · 小精英",
        "recommend_power": 15500, "stamina": 10, "pre_stage_id": 2002, "is_boss": False,
        "difficulty": 0.85,
        "enemies": [{"slot": 1, "mob": "heavy_gear_guard"}, {"slot": 4, "mob": "clockwork_soldier"},
                    {"slot": 5, "mob": "clockwork_soldier"}, {"slot": 8, "mob": "energy_capacitor"}],
        "mechanic": "【能量电容器】每 3 回合释放一道电脉冲，使我方全队无法行动 1 回合。",
        "tactics": "电容器定住全队的那一回合几乎等于白送一轮伤害，务必在它充能的间隙抢输出；重型齿轮卫兵正面减伤厚，绕不过就先清中排两个发条步兵。",
        "rewards": [
            {"id": "bound_gem", "name": "绑钻", "count": 80, "icon": "res://assets/icons/icon_gem.svg"},
            {"id": "equip_acrylic_pauldron", "name": "SR级套装装备【亮面亚克力护肩】", "count": 1,
             "icon": "res://assets/icons/icon_def.svg"},
            {"id": "hero_exp", "name": "英雄经验", "count": 4500, "icon": "res://assets/icons/icon_star.svg"},
        ],
    },
    {
        "id": 2004, "name": "自动化仓库", "kind": "battle", "subtitle": "支线 · 普通战斗",
        "recommend_power": 16000, "stamina": 8, "pre_stage_id": 2003, "is_boss": False,
        "difficulty": 0.85,
        "enemies": [{"slot": 1, "mob": "mech_spider"}, {"slot": 3, "mob": "mech_spider"},
                    {"slot": 5, "mob": "steam_gunner"}, {"slot": 8, "mob": "supply_cart"}],
        "mechanic": "环境效果【传送带】：所有非机械单位的行动速度降低 15%（描述性环境机制）。",
        "tactics": "仓库里全是机械，己方英雄都算“非机械单位”会被传送带拖慢出手；发条补给车还会持续给全队加攻，抢在提速前把补给车端掉。",
        "rewards": [
            {"id": "bound_gem", "name": "绑钻", "count": 120, "icon": "res://assets/icons/icon_gem.svg"},
            {"id": "scroll_light", "name": "光元素召唤卷轴", "count": 1, "icon": "res://assets/icons/icon_light.svg"},
        ],
    },
    {
        "id": 2005, "name": "蒸汽工坊", "kind": "event", "subtitle": "随机事件 · Rogue-lite 变体",
        "recommend_power": 0, "stamina": 0, "pre_stage_id": 2004, "is_boss": False,
        "enemies": [],
        "mechanic": "非战斗节点：在蒸汽工坊里做出选择，代价与收益都由选择决定。",
        "options": [
            {"id": "repair", "name": "尝试修复机甲", "cost": {"currency": "gem", "count": 50},
             "grant": {"buff": {"stat": "crit", "mult": 1.1, "scope": "team", "battles": 1,
                                "name": "机甲校准", "desc": "随机使一名英雄暴击率大幅提升（临时增益，持续 2 回合）"}}},
            {"id": "scavenge", "name": "搜索废料", "cost": {"stamina": 30},
             "grant": {"item": {"id": "scrap_cache", "name": "废料回收包（金币与英雄经验）", "count": 1,
                                "icon": "res://assets/icons/icon_coin.svg"}}},
            {"id": "leave", "name": "离开", "cost": {}, "grant": {}},
        ],
        "rewards": [],
    },
    {
        "id": 2006, "name": "破碎遗迹", "kind": "battle", "subtitle": "新敌人类型引导关",
        "recommend_power": 17200, "stamina": 8, "pre_stage_id": 2005, "is_boss": False,
        "difficulty": 0.85,
        "enemies": [{"slot": 1, "mob": "ancient_gargoyle"}, {"slot": 5, "mob": "ancient_runemaster"},
                    {"slot": 8, "mob": "rune_core"}],
        "mechanic": "引导玩家了解新敌人类型——【符文单位】：【符文核心】为周围的符文单位提供魔法减伤盾，且自身不受控制效果影响。",
        "tactics": "石像鬼顶前、符文师中排扫射、符文核心在后撑盾 —— 核心免疫控制又难缠，先手爆发把它打掉，符文单位的魔法盾就断了来源。",
        "rewards": [
            {"id": "gold", "name": "金币", "count": 4000, "icon": "res://assets/icons/icon_coin.svg"},
            {"id": "hero_exp", "name": "英雄经验", "count": 5000, "icon": "res://assets/icons/icon_star.svg"},
        ],
    },
    {
        "id": 2007, "name": "齿轮之心", "kind": "rest", "subtitle": "宝箱 / 休息节点",
        "recommend_power": 0, "stamina": 0, "pre_stage_id": 2006, "is_boss": False,
        "enemies": [],
        "mechanic": "节点效果：随机复活一名阵亡英雄并恢复其 50% 生命值，同时获得【机械宝箱】。",
        "restore": {"hp_pct": 0.5, "scope": "team"},
        "rewards": [
            {"id": "bound_gem", "name": "绑钻", "count": 100, "icon": "res://assets/icons/icon_gem.svg"},
            {"id": "shard_sr", "name": "SR英雄碎片", "count": 10, "icon": "res://assets/icons/icon_star.svg"},
        ],
    },
    {
        "id": 2008, "name": "精英防御塔", "kind": "elite", "subtitle": "高难支线 · 精英挑战",
        "recommend_power": 18800, "stamina": 12, "pre_stage_id": 2007, "is_boss": False,
        "difficulty": 0.85,
        "enemies": [{"slot": 1, "mob": "heavy_gear_guard"}, {"slot": 5, "mob": "steam_mgner"},
                    {"slot": 8, "mob": "tower_core"}],
        "mechanic": "【防御塔核心】每 2 回合对己方全队造成一轮真实伤害（无视护甲）。",
        "tactics": "全队周期性挨一发真实伤害，考验群体治疗与耐受力：奶量跟不上就撑不到把防御塔核心拆掉。机枪手还会横扫前排，前排换血扛不住。",
        "rewards": [
            {"id": "equip_foil_gauntlet", "name": "SSR级装备【炫彩烫金护手】", "count": 1,
             "icon": "res://assets/icons/icon_atk.svg"},
            {"id": "shard_ssr", "name": "SSR英雄碎片", "count": 8, "icon": "res://assets/icons/icon_star.svg"},
        ],
    },
    {
        "id": 2009, "name": "骷髅门前哨", "kind": "battle", "subtitle": "Boss 前夜 · 常规战斗",
        "recommend_power": 19500, "stamina": 8, "pre_stage_id": 2008, "is_boss": False,
        "difficulty": 0.85,
        "enemies": [{"slot": 1, "mob": "ancient_gargoyle"}, {"slot": 3, "mob": "ancient_gargoyle"},
                    {"slot": 5, "mob": "rune_priest"}, {"slot": 8, "mob": "rune_core"}],
        "mechanic": "最终 Boss 战前的阵容调配测试，确保队伍具备“多点爆发 + 群体治疗”完整体系。",
        "tactics": "两只石像鬼顶前、符文祭司续命、符文核心撑盾，是 Boss 阵容的缩水版；能稳切祭司又扛得住石像鬼，2010 才有得打。",
        "rewards": [
            {"id": "gold", "name": "金币", "count": 4800, "icon": "res://assets/icons/icon_coin.svg"},
            {"id": "break_stone_2", "name": "2阶突破石", "count": 15, "icon": "res://assets/icons/icon_def.svg"},
        ],
    },
    {
        "id": 2010, "name": "机械堡垒·巨神兵", "kind": "boss", "subtitle": "章节最终 Boss 战",
        "recommend_power": 20500, "stamina": 10, "pre_stage_id": 2009, "is_boss": True,
        "difficulty": 0.85, "first_clear_only": True,
        "enemies": [{"slot": 2, "mob": "auto_shield_guard"}, {"slot": 4, "mob": "clockwork_soldier"},
                    {"slot": 5, "mob": "mech_colossus"}, {"slot": 6, "mob": "clockwork_soldier"},
                    {"slot": 8, "mob": "energy_relay"}],
        "mechanic": "Boss 特性：【发条之心】机械减伤 40%，不受控制效果影响；【重力坍塌】满能量释放，"
                    "对己方全队造成 250% 真实伤害并降低 30% 行动速度（持续 2 回合）；"
                    "【机械洪流】每 3 回合召唤 2 名发条步兵（描述性召唤机制）。",
        "tactics": "物理队被发条之心吃掉四成伤害，控制又对它无效；能量中继站一直在给全队加攻，"
                   "盾卫挡正面、发条步兵源源不断 —— 先切中继站和盾卫压住增援，抢在重力坍塌满能量前把巨神兵带走。",
        "rewards": [
            {"id": "gem", "name": "彩虹钻石", "count": 500, "icon": "res://assets/icons/icon_gem.svg"},
            {"id": "ticket_advanced", "name": "高级召唤卷轴", "count": 8, "icon": "res://assets/icons/icon_gift.svg"},
            {"id": "hero_shadow_assassin", "name": "SSR英雄【暗夜刺客】", "count": 1,
             "icon": "res://assets/icons/icon_dark.svg", "first_clear": True},
        ],
    },
]

# --------------------------------------------------------------------------- 小节布局（3-3-4，克隆第一章成熟坐标）
SECTION_DEFS = [
    {"id": "ch2_s1", "label": "第一节", "name": "齿轮黎明",
     "chain": [(2001, (620, 700)), (2002, (950, 540)), (2003, (1280, 700))]},
    {"id": "ch2_s2", "label": "第二节", "name": "符文回响",
     "chain": [(2004, (620, 700)), (2005, (950, 540)), (2006, (1280, 700))]},
    {"id": "ch2_s3", "label": "第三节", "name": "巨神兵要塞",
     "chain": [(2007, (560, 680)), (2008, (820, 470)), (2009, (1080, 680)), (2010, (1340, 470))]},
]

# 每个节点的展示口径（图标按类型分派，与第一章同规范）
KIND_NODE = {
    "battle": {"icon": ISLE_PLAIN, "icon_size": 180, "radius": 90, "tag": ""},
    "elite":  {"icon": ISLE_CASTLE, "icon_size": 190, "radius": 100, "tag": "精"},
    "event":  {"icon": ISLE_PLAIN, "icon_size": 180, "radius": 90, "tag": "福"},
    "rest":   {"icon": ISLE_PLAIN, "icon_size": 180, "radius": 90, "tag": "休"},
    "boss":   {"icon": ISLE_CASTLE, "icon_size": 190, "radius": 100, "tag": "王"},
}
LABEL_DY = 110

# 战场环境配色（机械迷城偏冷钢 + 蒸汽暖光）
THEMES = {
    2001: {"sky_top": "#9FB3C8", "sky_bottom": "#E8EEF4", "sun": "#D8C79A",
           "ground": "#7C8A99", "rim": "#4A5560", "haze": "#5E6B7A"},
    2002: {"sky_top": "#C4A877", "sky_bottom": "#F2E6CE", "sun": "#F0D9A8",
           "ground": "#8A7A5E", "rim": "#55492F", "haze": "#6E6350"},
    2003: {"sky_top": "#7E93C4", "sky_bottom": "#DCE7F5", "sun": "#B7C9EE",
           "ground": "#6E7A94", "rim": "#454E66", "haze": "#3E4C6E"},
    2004: {"sky_top": "#A6BFB2", "sky_bottom": "#EAF4EC", "sun": "#D6EAC8",
           "ground": "#7E9488", "rim": "#4E6158", "haze": "#4C6A5E"},
    2005: {"sky_top": "#D8B48C", "sky_bottom": "#F6EBD8", "sun": "#F2D9A8",
           "ground": "#8C7B66", "rim": "#5A4E3E", "haze": "#6E5F4A"},
    2006: {"sky_top": "#B0A2C6", "sky_bottom": "#EDE6F6", "sun": "#D8C8EC",
           "ground": "#847A96", "rim": "#524A62", "haze": "#4E4560"},
    2007: {"sky_top": "#9FC4C0", "sky_bottom": "#E6F4F2", "sun": "#C8EDE6",
           "ground": "#748E8C", "rim": "#465E5C", "haze": "#3E6462"},
    2008: {"sky_top": "#C79A86", "sky_bottom": "#F5E4DA", "sun": "#F0C79A",
           "ground": "#8A6E64", "rim": "#5A433C", "haze": "#6B4A3C"},
    2009: {"sky_top": "#A88FB0", "sky_bottom": "#EEE4F2", "sun": "#D6C2E0",
           "ground": "#7E6E88", "rim": "#4E4458", "haze": "#48384E"},
    2010: {"sky_top": "#8A5F4A", "sky_bottom": "#E4B78A", "sun": "#F2C86E",
           "ground": "#5E4A42", "rim": "#382A26", "haze": "#4A2E28"},
}
DEFAULT_THEME = {"sky_top": "#8FB4D8", "sky_bottom": "#F2F7FB", "sun": "#FFF0C0",
                 "ground": "#9AA3AE", "rim": "#5E6670", "haze": "#5A6C86"}


# --------------------------------------------------------------------------- 战力计算（与第一章同一把尺）
def power_of(stats):
    return (float(stats["hp"]) * 0.12 + float(stats["atk"]) * 2.4 + float(stats["def"]) * 1.6
            + float(stats["mres"]) * 1.1 + float(stats["spd"]) * 2.0 + float(stats.get("crit", 0.0)) * 600.0)


def solve_scale(enemies, target):
    fixed = 0.0
    var = 0.0
    for e in enemies:
        b = MONSTERS[e["mob"]]["base"]
        p = power_of(b)
        f = float(b["spd"]) * 2.0 + float(b.get("crit", 0.0)) * 600.0
        fixed += f
        var += p - f
    if var <= 0.0:
        return 1.0
    return max(0.15, (float(target) - fixed) / var)


# --------------------------------------------------------------------------- 小节构建 + 校验
def _build_section(sec):
    nodes = []
    prev_id = 0
    for z, (sid, pos) in enumerate(sec["chain"], start=1):
        stage = next(s for s in STAGES if s["id"] == sid)
        kn = KIND_NODE[stage["kind"]]
        nodes.append({
            "stage_id": sid,
            "name": stage["name"],
            "level": 1,
            "kind": stage["kind"],
            "tag": kn["tag"],
            "icon": kn["icon"],
            "icon_size": kn["icon_size"],
            "label_order": "name_level",
            "pos": list(pos),
            "label_dy": LABEL_DY,
            "radius": kn["radius"],
            "z": z,
            "pre_stage_id": prev_id,
            "demo_stars": 0,
            "demo_selected": False,
            "stamina": stage["stamina"],
            "recommend_power": stage["recommend_power"],
        })
        prev_id = sid
    return {
        "id": sec["id"],
        "label": sec["label"],
        "name": sec["name"],
        "chapter_id": "ch2",
        "stage_ids": [sid for sid, _ in sec["chain"]],
        "gate_stage_id": sec["chain"][-1][0],
        "nodes": nodes,
    }


def _dist(p, q):
    return ((p[0] - q[0]) ** 2 + (p[1] - q[1]) ** 2) ** 0.5


def _validate(built):
    errors = []
    for s in built:
        nodes = s["nodes"]
        for n in nodes:
            x, y = n["pos"]
            if not (400 < x < 1500 and 250 < y < 900):
                errors.append("%s 节点 %d 越界 pos=%s" % (s["id"], n["stage_id"], n["pos"]))
        for i in range(len(nodes)):
            for j in range(i + 1, len(nodes)):
                d = _dist(nodes[i]["pos"], nodes[j]["pos"])
                if d < 200.0:
                    errors.append("%s 节点 %d/%d 重叠 d=%.0f" % (s["id"], nodes[i]["stage_id"], nodes[j]["stage_id"], d))
        by_id = {n["stage_id"]: n for n in nodes}
        for n in nodes:
            pre = n["pre_stage_id"]
            if pre <= 0 or pre not in by_id:
                continue
            a, b = by_id[pre], n
            d = _dist(a["pos"], b["pos"])
            visible = d - (a["radius"] + b["radius"])
            if not (24.0 <= visible < 260.0):
                errors.append("%s 引导线 %d->%d 可见段 %.0f 越界" % (s["id"], pre, b["stage_id"], visible))
    if errors:
        raise SystemExit("[FAIL] 布局校验未通过：\n  " + "\n  ".join(errors))


# --------------------------------------------------------------------------- 主流程
def main():
    with io.open(DATA, encoding="utf-8") as f:
        data = json.load(f)

    # 1. 怪物表：MERGE（不清掉第一章 14 只），补齐 icon/portrait 字段
    mtbl = data.setdefault("monsters", {}).setdefault("table", {})
    order = data["monsters"].setdefault("order", [])
    for k, v in MONSTERS.items():
        entry = dict(v)
        entry["id"] = k
        entry["icon"] = "%s/mob_%s.svg" % (ICON_BASE, k)
        entry["portrait"] = ""
        entry["portrait_note"] = "暂无立绘，战场用 icon 占位；有立绘后填 portrait 即可切过去"
        mtbl[k] = entry
        if k not in order:
            order.append(k)

    # 2. 关卡表：算 power_scale + 补 theme / no
    stages = []
    for idx, s in enumerate(STAGES):
        st = dict(s)
        st["no"] = idx + 1
        st["power_scale"] = round(solve_scale(s["enemies"], s["recommend_power"] * s["difficulty"]), 4) \
            if s["enemies"] else 0.0
        st["theme"] = dict(THEMES.get(s["id"], DEFAULT_THEME))
        st["theme_note"] = "战场环境配色。填了 bg（整张背景图路径）时 theme 失效，直接换成美术图。"
        st["bg"] = ""
        stages.append(st)

    # 3. extra_chapter_stages：追加/覆写 ch2 那份块（幂等：按 chapter_id 去重）
    extras = data["adventure"].setdefault("extra_chapter_stages", [])
    block = {
        "chapter_id": "ch2",
        "title": "机械迷城 · 齿轮与符文",
        "note": "第二章全 10 关。power_scale 反解口径与第一章一致，由 tools/_inspect/apply_chapter2.py 生成。",
        "slot_note": "enemies[].slot 取 combat.board.row_slots（1-3 前排 / 4-6 中排 / 7-9 后排）",
        "list": stages,
    }
    extras = [b for b in extras if str(b.get("chapter_id", "")) != "ch2"]
    extras.append(block)
    data["adventure"]["extra_chapter_stages"] = extras

    # 4. sections：把 ch2 的 3 节追加到 select_map.sections（幂等：按 id 去重）
    built = [_build_section(sec) for sec in SECTION_DEFS]
    _validate(built)
    sm = data["adventure"]["select_map"]
    ch2_ids = {s["id"] for s in built}
    sections = [s for s in sm.get("sections", []) if str(s.get("id", "")) not in ch2_ids]
    # 保证第一章 3 节在前、第二章 3 节紧随（按章节顺序）
    sections = [s for s in sections if str(s.get("chapter_id", "")) == "ch1"] + built \
        + [s for s in sections if str(s.get("chapter_id", "")) != "ch1"]
    sm["sections"] = sections
    # legacy 镜像：拼平所有小节节点
    sm["nodes"] = [n for s in sections for n in s["nodes"]]
    sm["nodes_note"] = (
        "各章按 3-3-4 拆成小节，每小节一张独立子地图；本 nodes 为各小节节点拼平的 legacy 镜像，"
        "渲染以 sections 为准（chapter_id 过滤当前章）。")

    # 5. chapter_tabs：ch2 改名《机械迷城》、有地图、通关一章 Boss(1010) 解锁
    for tab in sm.get("chapter_tabs", {}).get("items", []):
        if str(tab.get("id", "")) == "ch2":
            tab["name"] = "机械迷城"
            tab["locked"] = False
            tab["unlock_stage"] = 1010

    # 6. chapters 元信息对齐
    for ch in data["adventure"].get("chapters", []):
        if ch.get("id") == "ch2":
            ch["name"] = "机械迷城"
            ch["stages"] = 10
            ch["recommend_power"] = 13500
            ch["boss"] = "机械堡垒巨神兵"
            ch["unlock_stage"] = 1010
            ch["chapter_stages"] = "res://data/game_data.json#adventure.extra_chapter_stages"

    # 7. stage_kinds 补全（ch2 用到 battle/elite/event/rest/boss，第一章已具备）
    kinds = data["adventure"].get("stage_kinds", [])
    have = {str(k.get("id")) for k in kinds}
    for kid, kn in [("boss", "章节 Boss 战"), ("rest", "休息 / 宝箱"), ("event", "随机事件")]:
        if kid not in have:
            kinds.append({"id": kid, "name": kn})
    data["adventure"]["stage_kinds"] = kinds

    with io.open(DATA, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")

    # ------------------------------------------------------------------ 核对表
    print("已写入 %s" % os.path.relpath(DATA, ROOT))
    print("%-6s %-16s %-6s %8s %5s %9s %8s  %s" %
          ("编号", "名称", "类型", "建议战力", "体力", "敌方战力", "power_s", "阵容"))
    for s in stages:
        if not s["enemies"]:
            print("%-6d %-16s %-6s %8d %5d %9s %8s  %s" %
                  (s["id"], s["name"], s["kind"], s["recommend_power"], s["stamina"], "-", "-", "非战斗节点"))
            continue
        total = 0.0
        lineup = []
        for e in s["enemies"]:
            b = MONSTERS[e["mob"]]["base"]
            sc = s["power_scale"]
            scaled = {k: float(b[k]) * sc for k in ("hp", "atk", "def", "mres")}
            scaled["spd"] = b["spd"]
            scaled["crit"] = b["crit"]
            total += power_of(scaled)
            lineup.append("%d:%s" % (e["slot"], MONSTERS[e["mob"]]["name"]))
        print("%-6d %-16s %-6s %8d %5d %9d %8.3f  %s" %
              (s["id"], s["name"], s["kind"], s["recommend_power"], s["stamina"],
               int(round(total)), s["power_scale"], " ".join(lineup)))
    print("\n新增怪物 %d 只（现共 %d 只），关卡 %d 关，小节 %d 节" %
          (len(MONSTERS), len(data["monsters"]["table"]), len(STAGES), len(built)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
