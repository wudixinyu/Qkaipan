#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""apply_chapter3.py —— 把第三章《深渊暗界·影之迷宫》全关卡设计落进 game_data.json

用法：
    python tools/_inspect/apply_chapter3.py            # 幂等写入并打印核对表

沿用 apply_chapter2.py 的结构，**只增量、不覆写前两章**：
  - monsters.table：MERGE 13 只暗系新怪（ch1 的 14 只、ch2 的 17 只原样保留），追加 order；
  - chapter_stages：ch1/ch2 原样不动，新增 adventure.extra_chapter_stages 挂 ch3 的 10 关，
    GameDB.chapter_stages() 会把三份聚合成一张跨章表，chapter_stage(id) 自然跨章命中；
  - select_map.sections：ch1/ch2 的 6 节原样保留，追加 ch3 的 3 节（3-3-4，带 chapter_id）；
  - chapter_tabs / chapters：把占位的 ch3《星辉圣殿》改名为《深渊暗界·影之迷宫》，
    补 unlock_stage=2010（通关二章 Boss 解锁）、locked=false。

power_scale 反解口径与第一/二章完全一致（复用同一 power_of / solve_scale）：
  使「缩放后敌方总战力」= 建议战力 × difficulty。只缩放 hp/atk/def/mres，
  spd/crit 不参与强度缩放。

机制表达（沿用「描述性机制 + 现有 skill/traits/env」的取舍）：
  - 【深渊迷雾】命中降低、【诅咒/流血】、【噬魂祭司复活】、【虚空侵蚀扣血】、
    【暗影爆发沉默】、【灵魂吸噬】被动、【永夜降临】光暗克制 → 引擎暂无对应原语，
    写进 mechanic 文本描述，战斗用可执行技能近似（眩晕近似沉默、点杀近似集火提示等）；
  - 【光暗克制】本就是引擎原生的元素相克（light ⇄ dark），无需额外实现。
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

# --------------------------------------------------------------------------- 怪物表（13 只，MERGE 进 ch1/ch2）
MONSTERS = {
    "shadow_spiderling": {
        "name": "暗影幼蛛", "element": "dark", "role": "warrior",
        "desc": "深渊里孵化的小蛛，成群扑上来，被迷雾遮着时更难瞄得准。",
        "base": {"hp": 480, "atk": 96, "def": 70, "mres": 46, "crit": 0.08, "crit_dmg": 1.5, "spd": 112},
        "action": {"kind": "attack", "target": "nearest_front", "damage": "phys", "mult": 1.0},
    },
    "void_mage": {
        "name": "虚空法师", "element": "dark", "role": "mage",
        "desc": "操纵虚空能量的施法者，一挥手裂隙乱流就扫过中排。",
        "base": {"hp": 560, "atk": 150, "def": 72, "mres": 140, "crit": 0.06, "crit_dmg": 1.5, "spd": 98},
        "action": {"kind": "attack", "target": "middle_row", "damage": "magic", "mult": 0.9, "aoe": True},
    },
    "bone_shield": {
        "name": "骨盾勇士", "element": "dark", "role": "tank",
        "desc": "举着巨兽肩胛骨的重装亡兵，正面几乎推不动。",
        "base": {"hp": 1150, "atk": 82, "def": 240, "mres": 96, "crit": 0.03, "crit_dmg": 1.5, "spd": 64},
        "action": {"kind": "attack", "target": "nearest_front", "damage": "phys", "mult": 1.0},
        "traits": [
            {"id": "bone_wall", "name": "骸骨壁垒", "desc": "物理减伤 28%", "phys_reduction": 0.28},
        ],
    },
    "cursed_scarecrow": {
        "name": "诅咒草人", "element": "dark", "role": "support",
        "desc": "钉满骨钉的邪法人偶，每回合缠上一个倒霉蛋，让他持续流血。",
        "base": {"hp": 700, "atk": 100, "def": 80, "mres": 130, "crit": 0.05, "crit_dmg": 1.5, "spd": 92},
        "action": {"kind": "attack", "target": "nearest_front", "damage": "magic", "mult": 0.6},
        "skill": {"kind": "attack", "target": "lowest_hp_back", "damage": "magic", "mult": 0.8,
                  "interval": 1, "offset": 0, "stun_chance": 0.35, "stun_actions": 1,
                  "name": "荆棘诅咒", "desc": "每回合缠上己方随机一名英雄，使其陷入【流血】持续掉血（近似：概率定身 1 回合）"},
    },
    "night_archer": {
        "name": "暗夜弓手", "element": "dark", "role": "archer",
        "desc": "潜伏在暗处的狙击手，专挑阵型最后排最脆的那一个。",
        "base": {"hp": 500, "atk": 118, "def": 58, "mres": 50, "crit": 0.14, "crit_dmg": 1.6, "spd": 122},
        "action": {"kind": "attack", "target": "lowest_hp_back", "damage": "phys", "mult": 1.0},
    },
    "headless_knight": {
        "name": "无头骑士", "element": "dark", "role": "tank",
        "desc": "夹着头颅巡逻的亡魂骑士，越挨打越凶。",
        "base": {"hp": 1050, "atk": 104, "def": 200, "mres": 110, "crit": 0.06, "crit_dmg": 1.5, "spd": 86},
        "action": {"kind": "attack", "target": "nearest_front", "damage": "phys", "mult": 1.05},
        "traits": [
            {"id": "doom_aura", "name": "亡者威压", "desc": "物理减伤 15%（描述性光环）", "phys_reduction": 0.15},
        ],
    },
    "night_assassin": {
        "name": "暗夜刺客", "element": "dark", "role": "assassin",
        "desc": "藏在影子里的刀客，只为一击致命。",
        "base": {"hp": 640, "atk": 148, "def": 72, "mres": 60, "crit": 0.18, "crit_dmg": 1.7, "spd": 130},
        "action": {"kind": "attack", "target": "lowest_hp_back", "damage": "phys", "mult": 1.15},
    },
    "soul_priest": {
        "name": "噬魂祭司", "element": "dark", "role": "healer",
        "desc": "捧着魂灯的祭司，只要它站着，倒下的同伙就会被重新唤回战场。",
        "base": {"hp": 820, "atk": 86, "def": 90, "mres": 170, "crit": 0.04, "crit_dmg": 1.5, "spd": 106},
        "action": {"kind": "attack", "target": "nearest_front", "damage": "magic", "mult": 0.7},
        "skill": {"kind": "heal_lowest", "interval": 1, "mult": 1.9,
                  "name": "噬魂续命", "desc": "每次行动治疗己方血量最低单位（描述性：击杀己方单位时立即复活一名敌方前排），务必优先集火切后"},
    },
    "void_demon": {
        "name": "虚空恶魔", "element": "dark", "role": "mage",
        "desc": "从虚空裂缝里爬出的魔物，浑身腐蚀着周围的生命。",
        "base": {"hp": 880, "atk": 132, "def": 110, "mres": 120, "crit": 0.07, "crit_dmg": 1.5, "spd": 94},
        "action": {"kind": "attack", "target": "nearest_front", "damage": "magic", "mult": 1.0},
    },
    "shadow_blade": {
        "name": "暗影武者·刃", "element": "dark", "role": "assassin",
        "desc": "手握影刃的武者，刀光一闪便掠过整条战线。",
        "base": {"hp": 760, "atk": 172, "def": 110, "mres": 110, "crit": 0.20, "crit_dmg": 1.8, "spd": 128},
        "action": {"kind": "attack", "target": "lowest_hp_back", "damage": "phys", "mult": 1.2},
        "skill": {"kind": "attack", "target": "all_foes", "damage": "phys", "mult": 1.3, "aoe": True,
                  "interval": 3, "offset": 2, "name": "无影刃", "desc": "每 3 回合释放无影刃，横扫敌方全队"},
    },
    "cedric_guardian": {
        "name": "森林守护者·塞德里克", "element": "earth", "role": "tank",
        "desc": "被深渊腐化却仍守着最后绿意的守护者，硬得像一座活体堡垒。",
        "base": {"hp": 1600, "atk": 90, "def": 300, "mres": 150, "crit": 0.03, "crit_dmg": 1.5, "spd": 60},
        "action": {"kind": "attack", "target": "nearest_front", "damage": "phys", "mult": 1.0},
        "traits": [
            {"id": "bark_skin", "name": "古树之皮", "desc": "物理减伤 35%", "phys_reduction": 0.35},
        ],
        "skill": {"kind": "shield_all", "interval": 3, "offset": 2, "target": "all_allies", "mult": 1.0,
                  "name": "盘根护盾", "desc": "每 3 回合为己方全队附加护盾"},
    },
    "katherine_judge": {
        "name": "圣光审判者·凯瑟琳", "element": "light", "role": "mage",
        "desc": "手持圣焰的审判官，一击便能把整支队伍照得透亮。",
        "base": {"hp": 900, "atk": 196, "def": 96, "mres": 176, "crit": 0.10, "crit_dmg": 1.6, "spd": 104},
        "action": {"kind": "attack", "target": "nearest_front", "damage": "magic", "mult": 0.8},
        "skill": {"kind": "attack", "target": "all_foes", "damage": "magic", "mult": 1.5, "aoe": True,
                  "interval": 2, "offset": 1, "name": "圣光审判", "desc": "每 2 回合对敌方全队降下一轮高额圣光爆发"},
    },
    "shadow_lord": {
        "name": "影之魔王·萨尔加斯", "element": "dark", "role": "tank",
        "desc": "深渊暗界的主宰，永夜之王，吞噬一切亡魂为己用。",
        "boss": True,
        "base": {"hp": 5600, "atk": 268, "def": 360, "mres": 260, "crit": 0.06, "crit_dmg": 1.6, "spd": 72},
        "action": {"kind": "attack", "target": "nearest_front", "damage": "phys", "mult": 1.1},
        "traits": [
            {"id": "eternal_night", "name": "永夜降临",
             "desc": "光系伤害对其提升 50%，但非光系英雄物理/魔法防御降低 30%（描述性领域）",
             "phys_reduction": 0.20},
            {"id": "soul_devour", "name": "灵魂吸噬",
             "desc": "每当有场上单位（含敌我）死亡，Boss 恢复 15% 最大生命并提升 20% 攻击力（描述性被动）"},
        ],
        "skill": {"kind": "attack", "target": "all_foes", "damage": "magic", "mult": 3.0, "aoe": True,
                  "interval": 3, "offset": 2, "stun_chance": 1.0, "stun_actions": 1,
                  "name": "暗影爆发", "desc": "满能量时对己方全体造成 300% 极高魔法伤害，并附加 2 回合【沉默】（近似：眩晕 1 回合无法行动）"},
    },
}

# --------------------------------------------------------------------------- 关卡表
STAGES = [
    {
        "id": 3001, "name": "深渊暗界·迷雾边缘", "kind": "battle", "subtitle": "新环境机制引导关",
        "recommend_power": 22000, "stamina": 8, "pre_stage_id": 0, "is_boss": False,
        "difficulty": 0.85,
        "enemies": [{"slot": 1, "mob": "shadow_spiderling"}, {"slot": 3, "mob": "shadow_spiderling"},
                    {"slot": 8, "mob": "void_mage"}],
        "mechanic": "引导玩家了解新环境机制——【深渊迷雾】：前 2 回合敌方全员处于遮蔽状态，命中率降低 20%，需使用光系技能或辅助技能「照亮」战场。",
        "tactics": "迷雾未散时物理队命中率吃折扣，光系/带「照亮」的辅助能提前揭开遮蔽；两只暗影幼蛛扑上来得快，先手点掉后排的虚空法师更稳。",
        "rewards": [
            {"id": "gold", "name": "金币", "count": 5000, "icon": "res://assets/icons/icon_coin.svg"},
            {"id": "hero_exp", "name": "英雄经验", "count": 6000, "icon": "res://assets/icons/icon_star.svg"},
            {"id": "break_stone_3", "name": "3阶突破石", "count": 5, "icon": "res://assets/icons/icon_def.svg"},
        ],
    },
    {
        "id": 3002, "name": "诅咒走廊", "kind": "battle", "subtitle": "普通战斗",
        "recommend_power": 23500, "stamina": 8, "pre_stage_id": 3001, "is_boss": False,
        "difficulty": 0.85,
        "enemies": [{"slot": 1, "mob": "bone_shield"}, {"slot": 3, "mob": "bone_shield"},
                    {"slot": 5, "mob": "cursed_scarecrow"}, {"slot": 8, "mob": "night_archer"}],
        "mechanic": "【诅咒草人】每回合使己方随机 1 名英雄进入【流血】状态，持续掉血。",
        "tactics": "两只骨盾勇士顶前后，草人在中间放诅咒、暗夜弓手点你后排 —— 需配备带净化能力的辅助（如 UR 依莲）解除流血，否则血条一边打一边漏。",
        "rewards": [
            {"id": "gold", "name": "金币", "count": 5500, "icon": "res://assets/icons/icon_coin.svg"},
            {"id": "hero_exp", "name": "英雄经验", "count": 6500, "icon": "res://assets/icons/icon_star.svg"},
            {"id": "break_stone_3", "name": "3阶突破石", "count": 8, "icon": "res://assets/icons/icon_def.svg"},
        ],
    },
    {
        "id": 3003, "name": "影之祭坛", "kind": "elite", "subtitle": "精英挑战 · 小精英",
        "recommend_power": 25800, "stamina": 10, "pre_stage_id": 3002, "is_boss": False,
        "difficulty": 0.85,
        "enemies": [{"slot": 1, "mob": "headless_knight"}, {"slot": 5, "mob": "night_assassin"},
                    {"slot": 8, "mob": "soul_priest"}],
        "mechanic": "【噬魂祭司】击杀己方单位时会立即复活一名敌方前排。",
        "tactics": "祭司不删，前排杀了又活 —— 必须优先集火切后：绕过无头骑士，抢先把噬魂祭司和暗夜刺客带走，才能断掉复活链。",
        "rewards": [
            {"id": "bound_gem", "name": "绑钻", "count": 100, "icon": "res://assets/icons/icon_gem.svg"},
            {"id": "equip_shadow_boots", "name": "SSR级套装【暗影之靴】", "count": 1,
             "icon": "res://assets/icons/icon_dark.svg"},
            {"id": "hero_exp", "name": "英雄经验", "count": 8000, "icon": "res://assets/icons/icon_star.svg"},
        ],
    },
    {
        "id": 3004, "name": "虚空裂缝", "kind": "elite", "subtitle": "高危支线 · 极限生存",
        "recommend_power": 27000, "stamina": 10, "pre_stage_id": 3003, "is_boss": False,
        "difficulty": 0.85,
        "enemies": [{"slot": 4, "mob": "void_demon"}, {"slot": 6, "mob": "void_demon"},
                    {"slot": 8, "mob": "shadow_blade"}],
        "mechanic": "环境效果【虚空侵蚀】：全体非暗系英雄每回合损失 5% 最大生命值（描述性环境机制）。",
        "tactics": "裂缝里全是虚空腐蚀，非暗系英雄每回合都在掉血，拖得越久越亏：暗系队天然免疫这条 Debuff，配奶妈硬顶也要在血被榨干前把两只虚空恶魔清掉，别让暗影武者·刃开出无影刃。",
        "rewards": [
            {"id": "bound_gem", "name": "绑钻", "count": 200, "icon": "res://assets/icons/icon_gem.svg"},
            {"id": "ticket_advanced", "name": "高级召唤卷轴", "count": 2, "icon": "res://assets/icons/icon_gift.svg"},
            {"id": "scroll_dark", "name": "暗元素召唤卷轴", "count": 1, "icon": "res://assets/icons/icon_dark.svg"},
        ],
    },
    {
        "id": 3005, "name": "噬魂泉水", "kind": "event", "subtitle": "随机抉择 · 险境求生",
        "recommend_power": 0, "stamina": 0, "pre_stage_id": 3004, "is_boss": False,
        "enemies": [],
        "mechanic": "非战斗节点：在噬魂泉水前做出抉择，风险与收益全凭一瞬。",
        "options": [
            {"id": "drink", "name": "饮用泉水（高风险高回报）", "cost": {},
             "grant": {"buff": {"stat": "crit", "mult": 1.2, "scope": "team", "battles": 2,
                                "name": "深渊之力",
                                "desc": "饮用泉水：50% 概率全队恢复 100% 能量，50% 概率全队当前生命值减少 30%（近似以临时暴击增益呈现高风险高回报）"}}},
            {"id": "purify", "name": "净化泉水（消耗光系英雄能量）", "cost": {},
             "grant": {"buff": {"stat": "spd", "mult": 1.1, "scope": "team", "battles": 1,
                                "name": "净化光环", "desc": "获得【净化光环】：下一场战斗全队免疫首次控制"}}},
            {"id": "leave", "name": "绕道而行", "cost": {}, "grant": {}},
        ],
        "rewards": [],
    },
    {
        "id": 3006, "name": "暗影迷宫", "kind": "battle", "subtitle": "普通战斗",
        "recommend_power": 28500, "stamina": 8, "pre_stage_id": 3005, "is_boss": False,
        "difficulty": 0.85,
        "enemies": [{"slot": 1, "mob": "bone_shield"}, {"slot": 4, "mob": "night_assassin"},
                    {"slot": 6, "mob": "night_archer"}, {"slot": 8, "mob": "void_mage"}],
        "mechanic": "敌方双刺客/弓手阵容，专挑后排下手，生存压力极大。",
        "tactics": "暗夜刺客和暗夜弓手都盯着你最脆的后排，虚空法师还会扫中排 —— 需靠地系/前排嘲讽英雄把伤害吸走，否则后排站不住两回合。",
        "rewards": [
            {"id": "gold", "name": "金币", "count": 6500, "icon": "res://assets/icons/icon_coin.svg"},
            {"id": "hero_exp", "name": "英雄经验", "count": 7500, "icon": "res://assets/icons/icon_star.svg"},
        ],
    },
    {
        "id": 3007, "name": "封印之门", "kind": "rest", "subtitle": "宝箱 / 休息节点",
        "recommend_power": 0, "stamina": 0, "pre_stage_id": 3006, "is_boss": False,
        "enemies": [],
        "mechanic": "节点效果：恢复全队 80% 生命值，并获得【深渊魔盒】。",
        "restore": {"hp_pct": 0.8, "scope": "team"},
        "rewards": [
            {"id": "gem", "name": "彩虹钻石", "count": 150, "icon": "res://assets/icons/icon_gem.svg"},
            {"id": "shard_ssr", "name": "SSR英雄碎片", "count": 10, "icon": "res://assets/icons/icon_star.svg"},
        ],
    },
    {
        "id": 3008, "name": "暗夜密室", "kind": "elite", "subtitle": "隐藏挑战 · 精英限时战",
        "recommend_power": 31000, "stamina": 12, "pre_stage_id": 3007, "is_boss": False,
        "difficulty": 0.85,
        "enemies": [{"slot": 1, "mob": "cedric_guardian"}, {"slot": 8, "mob": "katherine_judge"}],
        "mechanic": "限时挑战：5 回合内击杀所有敌人即通关，超时判负。",
        "tactics": "塞德里克硬到令人发指（物理减伤 35% 还会给全队套盾），凯瑟琳每 2 回合降一轮高额圣光爆发 —— 拼的是极限单体点杀与破盾能力，奶盾都救不了超时，5 回合内必须把两只一起带走。",
        "rewards": [
            {"id": "shard_ur", "name": "UR英雄碎片", "count": 5, "icon": "res://assets/icons/icon_star.svg"},
            {"id": "equip_holy_robe", "name": "UR套装【圣光法袍】", "count": 1,
             "icon": "res://assets/icons/icon_light.svg"},
        ],
    },
    {
        "id": 3009, "name": "影魔前哨", "kind": "battle", "subtitle": "Boss 前哨战",
        "recommend_power": 32500, "stamina": 8, "pre_stage_id": 3008, "is_boss": False,
        "difficulty": 0.85,
        "enemies": [{"slot": 1, "mob": "headless_knight"}, {"slot": 3, "mob": "bone_shield"},
                    {"slot": 5, "mob": "cursed_scarecrow"}, {"slot": 8, "mob": "soul_priest"}],
        "mechanic": "Boss 战前的阵容综合检验，必须在 4 回合内打破敌方防线。",
        "tactics": "双前排扛伤、草人放诅咒、祭司续命复活，是 Boss 阵容的缩水版；能 4 回合内强拆防线又断得掉祭司，3010 才有得打。",
        "rewards": [
            {"id": "gold", "name": "金币", "count": 7500, "icon": "res://assets/icons/icon_coin.svg"},
            {"id": "break_stone_3", "name": "3阶突破石", "count": 20, "icon": "res://assets/icons/icon_def.svg"},
        ],
    },
    {
        "id": 3010, "name": "影之魔王·萨尔加斯", "kind": "boss", "subtitle": "章节最终 Boss 战",
        "recommend_power": 35000, "stamina": 12, "pre_stage_id": 3009, "is_boss": True,
        "difficulty": 0.85, "first_clear_only": True,
        "enemies": [{"slot": 1, "mob": "headless_knight"}, {"slot": 3, "mob": "headless_knight"},
                    {"slot": 4, "mob": "void_demon"}, {"slot": 5, "mob": "shadow_lord"},
                    {"slot": 6, "mob": "void_demon"}, {"slot": 8, "mob": "soul_priest"}],
        "mechanic": "Boss 特性：【永夜降临】光系伤害对其提升 50%，但非光系英雄物理/魔法防御降低 30%；"
                    "【暗影爆发】满能量时对己方全体造成 300% 极高魔法伤害并附加 2 回合【沉默】；"
                    "被动【灵魂吸噬】每当场上有单位（含敌我）死亡，Boss 恢复 15% 最大生命并提升 20% 攻击力。",
        "tactics": "光系队被永夜降临加成、能打出更高爆发，但非光系英雄防御被削 30% —— 编队要在「光系点杀」和「暗系扛线」间权衡；"
                   "灵魂吸噬让场上任何死亡都在给 Boss 回血加攻，切忌用自杀式换血流；"
                   "抢在暗影爆发满能量前，先切掉两侧虚空恶魔与噬魂祭司，再集火把萨尔加斯带走。",
        "rewards": [
            {"id": "gem", "name": "彩虹钻石", "count": 800, "icon": "res://assets/icons/icon_gem.svg"},
            {"id": "ticket_advanced", "name": "高级召唤卷轴", "count": 10, "icon": "res://assets/icons/icon_gift.svg"},
            {"id": "hero_shadow_blade", "name": "UR英雄【暗影武者·刃】", "count": 1,
             "icon": "res://assets/icons/icon_dark.svg", "first_clear": True},
        ],
    },
]

# --------------------------------------------------------------------------- 小节布局（3-3-4，沿用成熟坐标）
SECTION_DEFS = [
    {"id": "ch3_s1", "label": "第一节", "name": "迷雾诅咒",
     "chain": [(3001, (620, 700)), (3002, (950, 540)), (3003, (1280, 700))]},
    {"id": "ch3_s2", "label": "第二节", "name": "虚空裂隙",
     "chain": [(3004, (620, 700)), (3005, (950, 540)), (3006, (1280, 700))]},
    {"id": "ch3_s3", "label": "第三节", "name": "永夜王座",
     "chain": [(3007, (560, 680)), (3008, (820, 470)), (3009, (1080, 680)), (3010, (1340, 470))]},
]

# 每个节点的展示口径（图标按类型分派，与前两章同规范）
KIND_NODE = {
    "battle": {"icon": ISLE_PLAIN, "icon_size": 180, "radius": 90, "tag": ""},
    "elite":  {"icon": ISLE_CASTLE, "icon_size": 190, "radius": 100, "tag": "精"},
    "event":  {"icon": ISLE_PLAIN, "icon_size": 180, "radius": 90, "tag": "福"},
    "rest":   {"icon": ISLE_PLAIN, "icon_size": 180, "radius": 90, "tag": "休"},
    "boss":   {"icon": ISLE_CASTLE, "icon_size": 190, "radius": 100, "tag": "王"},
}
LABEL_DY = 110

# 战场环境配色（深渊暗界：紫黑、幽蓝、暗红、病绿）
THEMES = {
    3001: {"sky_top": "#3B2E52", "sky_bottom": "#6E5A8C", "sun": "#8C7BB0",
           "ground": "#332844", "rim": "#1C1430", "haze": "#4A3A66"},
    3002: {"sky_top": "#2A2140", "sky_bottom": "#544272", "sun": "#7A6AA0",
           "ground": "#28203C", "rim": "#150F26", "haze": "#3A2E56"},
    3003: {"sky_top": "#4A2650", "sky_bottom": "#7E4684", "sun": "#B06AC0",
           "ground": "#381E40", "rim": "#220F28", "haze": "#5A2E60"},
    3004: {"sky_top": "#1E2A48", "sky_bottom": "#3E5A82", "sun": "#6E8CC0",
           "ground": "#1A2338", "rim": "#0F1524", "haze": "#2E4266"},
    3005: {"sky_top": "#22483F", "sky_bottom": "#3F7A68", "sun": "#6FBFA0",
           "ground": "#1C3A32", "rim": "#102420", "haze": "#2E5A4C"},
    3006: {"sky_top": "#2E2340", "sky_bottom": "#5A4676", "sun": "#8874B0",
           "ground": "#2A2038", "rim": "#181024", "haze": "#40305C"},
    3007: {"sky_top": "#3A2A52", "sky_bottom": "#6E5290", "sun": "#A488D0",
           "ground": "#302448", "rim": "#1C1430", "haze": "#4E3A6C"},
    3008: {"sky_top": "#243A4A", "sky_bottom": "#4E6E82", "sun": "#8AC0A0",
           "ground": "#1E303C", "rim": "#122028", "haze": "#2E4C5C"},
    3009: {"sky_top": "#40203A", "sky_bottom": "#72405E", "sun": "#A86A8C",
           "ground": "#341A30", "rim": "#1E0F1C", "haze": "#56304E"},
    3010: {"sky_top": "#160F24", "sky_bottom": "#3A1E48", "sun": "#7A2E6E",
           "ground": "#120B1E", "rim": "#0A0612", "haze": "#2A1438"},
}
DEFAULT_THEME = {"sky_top": "#2E2340", "sky_bottom": "#5A4676", "sun": "#8874B0",
                 "ground": "#2A2038", "rim": "#181024", "haze": "#40305C"}


# --------------------------------------------------------------------------- 战力计算（与前两章同一把尺）
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
        "chapter_id": "ch3",
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

    # 1. 怪物表：MERGE（不清掉前两章），补齐 icon/portrait 字段
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

    # 3. extra_chapter_stages：追加/覆写 ch3 那份块（幂等：按 chapter_id 去重）
    extras = data["adventure"].setdefault("extra_chapter_stages", [])
    block = {
        "chapter_id": "ch3",
        "title": "深渊暗界 · 影之迷宫",
        "note": "第三章全 10 关。power_scale 反解口径与前两章一致，由 tools/_inspect/apply_chapter3.py 生成。",
        "slot_note": "enemies[].slot 取 combat.board.row_slots（1-3 前排 / 4-6 中排 / 7-9 后排）",
        "list": stages,
    }
    extras = [b for b in extras if str(b.get("chapter_id", "")) != "ch3"]
    extras.append(block)
    data["adventure"]["extra_chapter_stages"] = extras

    # 4. sections：把 ch3 的 3 节追加到 select_map.sections（幂等：按 id 去重，保持 ch1/ch2 在前）
    built = [_build_section(sec) for sec in SECTION_DEFS]
    _validate(built)
    sm = data["adventure"]["select_map"]
    ch3_ids = {s["id"] for s in built}
    existing = [s for s in sm.get("sections", []) if str(s.get("id", "")) not in ch3_ids]
    sm["sections"] = existing + built
    # legacy 镜像：拼平所有小节节点
    sm["nodes"] = [n for s in sm["sections"] for n in s["nodes"]]
    sm["nodes_note"] = (
        "各章按 3-3-4 拆成小节，每小节一张独立子地图；本 nodes 为各小节节点拼平的 legacy 镜像，"
        "渲染以 sections 为准（chapter_id 过滤当前章）。")

    # 5. chapter_tabs：ch3 改名《深渊暗界·影之迷宫》、有地图、通关二章 Boss(2010) 解锁
    for tab in sm.get("chapter_tabs", {}).get("items", []):
        if str(tab.get("id", "")) == "ch3":
            tab["name"] = "深渊暗界·影之迷宫"
            tab["locked"] = False
            tab["unlock_stage"] = 2010

    # 6. chapters 元信息对齐（把占位的星辉圣殿改成本章设计）
    for ch in data["adventure"].get("chapters", []):
        if ch.get("id") == "ch3":
            ch["name"] = "深渊暗界·影之迷宫"
            ch["stages"] = 10
            ch["recommend_power"] = 22000
            ch["boss"] = "影之魔王·萨尔加斯"
            ch["unlock_stage"] = 2010
            ch["chapter_stages"] = "res://data/game_data.json#adventure.extra_chapter_stages"

    # 7. stage_kinds 补全（ch3 用到 battle/elite/event/rest/boss，前两章已具备）
    kinds = data["adventure"].get("stage_kinds", [])
    have = {str(k.get("id")) for k in kinds}
    for kid, kn in [("boss", "章节 Boss 战"), ("rest", "休息 / 宝箱"), ("event", "随机事件"),
                    ("elite", "精英挑战")]:
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
