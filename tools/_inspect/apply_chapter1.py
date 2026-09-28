#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""apply_chapter1.py —— 把第一章《云上浮岛·初始之痕》全关卡设计落进 game_data.json

用法：
    python tools/_inspect/apply_chapter1.py            # 写入并打印核对表

幂等：chapter_stages / monsters / combat.battle 三段整体覆写；
      select_map 的 3 个节点只补名称与体力（锚点/anchor_note 不动）。

设计取舍（都在配置的 *_note 字段里留了痕）：
  1. 敌方强度不手填每个怪的数值，而是「怪物基础面板 + 每关一个 power_scale」：
     基础面板描述这只怪**是什么**（软泥怪就是弱，巨石守卫就是强），
     关卡强度描述这一关**多难**。两个维度分开，改关卡难度不会把怪物设定改脏。
  2. power_scale 由「建议战力 × 难度系数、反解出使敌方总战力达标的比例」算出，
     所以配置里的数字和策划表的「建议战力」永远对得上，不靠手调。
  3. 怪物行为（打哪一排 / 治疗 / 加攻 / 护盾 / Boss 特性）全部数据化在 action /
     skill / traits 字段里，战斗内核只做解释器，不写 if 怪名。
"""

import io
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DATA = os.path.join(ROOT, "data", "game_data.json")
ICON_BASE = "res://assets/icons/monsters"

# --------------------------------------------------------------------------- 怪物表
# base 面板口径与 characters[].base 一致，便于 RealmDB 的战斗力估值函数直接复用。
# action：普通行动；skill：带 interval 的特殊行动（interval=1 表示每次都放）。
MONSTERS = {
    "slime": {
        "name": "软泥怪", "element": "water", "role": "warrior",
        "desc": "云海浅滩最常见的软体生物，只会一头撞上来。",
        "base": {"hp": 420, "atk": 42, "def": 60, "mres": 30, "crit": 0.03, "crit_dmg": 1.5, "spd": 80},
        "action": {"kind": "attack", "target": "nearest_front", "damage": "phys", "mult": 1.0},
    },
    "nut_soldier": {
        "name": "坚果小兵", "element": "earth", "role": "tank",
        "desc": "顶着坚果壳的浮岛守备兵，壳硬得很，负责挡在最前面。",
        "base": {"hp": 620, "atk": 50, "def": 130, "mres": 40, "crit": 0.02, "crit_dmg": 1.5, "spd": 70},
        "action": {"kind": "attack", "target": "nearest_front", "damage": "phys", "mult": 0.9},
    },
    "forest_archer": {
        "name": "森林弓箭手", "element": "wind", "role": "archer",
        "desc": "藏在浮空森林树冠里的射手，箭头永远朝着更脆的那一排。",
        "base": {"hp": 460, "atk": 96, "def": 55, "mres": 45, "crit": 0.12, "crit_dmg": 1.6, "spd": 118},
        "action": {"kind": "attack", "target": "lowest_hp_back", "damage": "phys", "mult": 1.0},
    },
    "castle_guard": {
        "name": "城堡重装卫兵", "element": "light", "role": "tank",
        "desc": "云端城堡的仪仗守卫，塔盾一立，正面几乎推不动。",
        "base": {"hp": 900, "atk": 62, "def": 210, "mres": 70, "crit": 0.02, "crit_dmg": 1.5, "spd": 64},
        "action": {"kind": "attack", "target": "nearest_front", "damage": "phys", "mult": 1.0},
    },
    "ballista": {
        "name": "弩箭车", "element": "earth", "role": "archer",
        "desc": "架在城垛上的重弩，一轮齐射能覆盖一整排。",
        "base": {"hp": 700, "atk": 128, "def": 110, "mres": 40, "crit": 0.08, "crit_dmg": 1.5, "spd": 58},
        "action": {"kind": "attack", "target": "middle_row", "damage": "phys", "mult": 0.85, "aoe": True},
    },
    "castle_bard": {
        "name": "城堡军乐手", "element": "light", "role": "support",
        "desc": "不当输出，只吹号角。号声一响，全队越打越猛，因此必须优先切后排。",
        "base": {"hp": 560, "atk": 40, "def": 70, "mres": 95, "crit": 0.03, "crit_dmg": 1.5, "spd": 96},
        "action": {"kind": "attack", "target": "nearest_front", "damage": "magic", "mult": 0.6},
        "skill": {"kind": "buff_atk", "interval": 1, "value": 0.08, "max_stacks": 3,
                  "name": "战地军乐", "desc": "每次行动为全队提升 8% 攻击力，最多叠 3 层"},
    },
    "storm_elemental": {
        "name": "风暴元素", "element": "wind", "role": "mage",
        "desc": "被浮岛风暴卷起来的气旋，无形无质，只对中排倾泻乱流。",
        "base": {"hp": 660, "atk": 124, "def": 66, "mres": 88, "crit": 0.10, "crit_dmg": 1.5, "spd": 126},
        "action": {"kind": "attack", "target": "middle_row", "damage": "magic", "mult": 0.9, "aoe": True},
    },
    "cloud_sprite": {
        "name": "雷云精灵", "element": "wind", "role": "mage",
        "desc": "小朵雷云，专挑队伍里血最薄的那个劈。",
        "base": {"hp": 520, "atk": 118, "def": 50, "mres": 105, "crit": 0.09, "crit_dmg": 1.5, "spd": 132},
        "action": {"kind": "attack", "target": "lowest_hp_back", "damage": "magic", "mult": 1.05},
    },
    "ruin_guard": {
        "name": "遗迹守卫", "element": "earth", "role": "tank",
        "desc": "遗迹里还在按旧命令巡逻的石像，慢，但很难凿开。",
        "base": {"hp": 1150, "atk": 78, "def": 240, "mres": 90, "crit": 0.02, "crit_dmg": 1.5, "spd": 62},
        "action": {"kind": "attack", "target": "nearest_front", "damage": "phys", "mult": 1.0},
    },
    "puppet_mage": {
        "name": "傀儡法师", "element": "dark", "role": "mage",
        "desc": "提线人偶，每隔两次行动就替全队糊上一层护盾，得靠单体爆发快速减员。",
        "base": {"hp": 700, "atk": 140, "def": 72, "mres": 130, "crit": 0.08, "crit_dmg": 1.5, "spd": 88},
        "action": {"kind": "attack", "target": "nearest_front", "damage": "magic", "mult": 0.95},
        "skill": {"kind": "shield_all", "interval": 3, "offset": 1, "mult": 1.2,
                  "name": "傀儡护盾", "desc": "为己方全队附加等同自身攻击力 120% 的护盾"},
    },
    "goblin_chief": {
        "name": "哥布林百夫长", "element": "fire", "role": "warrior",
        "desc": "部落里最能打的一个，红缨一甩就往前顶。",
        "base": {"hp": 1250, "atk": 118, "def": 165, "mres": 60, "crit": 0.06, "crit_dmg": 1.6, "spd": 86},
        "action": {"kind": "attack", "target": "nearest_front", "damage": "phys", "mult": 1.1},
    },
    "stone_slinger": {
        "name": "投石投掷手", "element": "earth", "role": "archer",
        "desc": "抡着皮兜往对面后排砸石头，砸得又散又疼。",
        "base": {"hp": 780, "atk": 132, "def": 90, "mres": 55, "crit": 0.07, "crit_dmg": 1.5, "spd": 92},
        "action": {"kind": "attack", "target": "back_row", "damage": "phys", "mult": 0.8, "aoe": True},
    },
    "goblin_shaman": {
        "name": "哥布林萨满", "element": "dark", "role": "healer",
        "desc": "跳着祭舞给族人续命，只要它站着，前排就磨不死。",
        "base": {"hp": 820, "atk": 76, "def": 85, "mres": 140, "crit": 0.04, "crit_dmg": 1.5, "spd": 104},
        "action": {"kind": "attack", "target": "nearest_front", "damage": "magic", "mult": 0.7},
        "skill": {"kind": "heal_lowest", "interval": 1, "mult": 1.8,
                  "name": "先祖图腾", "desc": "每次行动治疗己方血量百分比最低的单位，治疗量为攻击力 180%"},
    },
    "stone_warden": {
        "name": "巨石守卫", "element": "earth", "role": "tank",
        "desc": "枯髅门的守门人，一整块花岗岩凿出来的巨人，胸口符文是它唯一没被风蚀掉的东西。",
        "boss": True,
        "base": {"hp": 4200, "atk": 210, "def": 320, "mres": 180, "crit": 0.05, "crit_dmg": 1.5, "spd": 74},
        "action": {"kind": "attack", "target": "nearest_front", "damage": "phys", "mult": 1.0},
        "traits": [
            {"id": "granite_armor", "name": "花岗岩护甲",
             "desc": "物理减伤 30%，开局为自身附加等同 20% 最大生命值的护盾",
             "phys_reduction": 0.30, "shield_pct": 0.20, "shield_scope": "self"},
            {"id": "quake_slam", "name": "裂地震击",
             "desc": "满能量释放，对敌方前排全体造成 200% 物理伤害，50% 概率眩晕 1 回合",
             "mult": 2.0, "target": "front_row", "damage": "phys",
             "stun_chance": 0.5, "stun_actions": 1},
        ],
    },
}

# --------------------------------------------------------------------------- 关卡表
# enemies 的 slot 语义 = combat.board.row_slots（1-3 前排 / 4-6 中排 / 7-9 后排），
# 与 RealmDB.roster() 用的 player slot 是同一套编号，UI 不需要第二套坐标。
STAGES = [
    {
        "id": 1001, "name": "初始之地", "kind": "battle", "subtitle": "新手引导关",
        "recommend_power": 1000, "stamina": 0, "pre_stage_id": 0, "is_boss": False,
        "difficulty": 0.60,
        "enemies": [{"slot": 1, "mob": "slime"}, {"slot": 3, "mob": "slime"}],
        "mechanic": "引导玩家完成基础卡牌上阵与「进入冒险」点击操作。",
        "tactics": "两只会撞人的软泥怪，随便打。",
        "rewards": [
            {"id": "gold", "name": "金币", "count": 500, "icon": "res://assets/icons/icon_coin.svg"},
            {"id": "hero_exp", "name": "英雄经验", "count": 500, "icon": "res://assets/icons/icon_star.svg"},
            {"id": "ticket_basic", "name": "基础召唤券", "count": 1, "icon": "res://assets/icons/icon_gift.svg"},
        ],
    },
    {
        "id": 1002, "name": "浮空森林", "kind": "battle", "subtitle": "普通战斗",
        "recommend_power": 2500, "stamina": 6, "pre_stage_id": 1001, "is_boss": False,
        "difficulty": 0.85,
        "enemies": [{"slot": 1, "mob": "nut_soldier"}, {"slot": 3, "mob": "nut_soldier"},
                    {"slot": 8, "mob": "forest_archer"}],
        "mechanic": "介绍前排保护与后排输出的基本定位，引导玩家关注攻击顺序。",
        "tactics": "两只坚果小兵顶在前排，弓箭手在后排点名最脆的单位 —— 先拆后排，前排自然崩。",
        "rewards": [
            {"id": "gold", "name": "金币", "count": 1000, "icon": "res://assets/icons/icon_coin.svg"},
            {"id": "hero_exp", "name": "英雄经验", "count": 1200, "icon": "res://assets/icons/icon_star.svg"},
            {"id": "break_stone_1", "name": "1阶突破石", "count": 5, "icon": "res://assets/icons/icon_def.svg"},
        ],
    },
    {
        "id": 1003, "name": "云端城堡", "kind": "elite", "subtitle": "精英挑战 · 首个小精英",
        "recommend_power": 4800, "stamina": 8, "pre_stage_id": 1001, "is_boss": False,
        "difficulty": 0.85,
        "enemies": [{"slot": 1, "mob": "castle_guard"}, {"slot": 5, "mob": "ballista"},
                    {"slot": 8, "mob": "castle_bard"}],
        "mechanic": "后排军乐手会不断为全队增加攻击力，需优先使用切后排技能清理。",
        "tactics": "重装卫兵挡正面、弩箭车扫中排，号声一响对面越打越猛 —— 拖得越久越难，必须抢节奏切后排。",
        "rewards": [
            {"id": "bound_gem", "name": "绑钻", "count": 50, "icon": "res://assets/icons/icon_gem.svg"},
            {"id": "equip_wood_chest", "name": "R级套装装备【木质护胸】", "count": 1,
             "icon": "res://assets/icons/icon_def.svg"},
            {"id": "hero_exp", "name": "英雄经验", "count": 2000, "icon": "res://assets/icons/icon_star.svg"},
        ],
    },
    {
        "id": 1004, "name": "风暴元素", "kind": "battle", "subtitle": "支线 · 元素考验",
        "recommend_power": 6200, "stamina": 6, "pre_stage_id": 1003, "is_boss": False,
        "difficulty": 0.85,
        "enemies": [{"slot": 4, "mob": "storm_elemental"}, {"slot": 6, "mob": "storm_elemental"},
                    {"slot": 8, "mob": "cloud_sprite"}],
        "env": {
            "id": "storm_aura", "name": "风暴气场",
            "desc": "场上所有风属性单位攻击速度提升 20%",
            "element": "wind", "stat": "spd", "mult": 1.2,
        },
        "mechanic": "环境效果【风暴气场】：场上所有风属性单位攻击速度提升 20%。",
        "tactics": "三只风属性单位全部吃满气场加速，出手极快；用土系打风可以打出克制。",
        "rewards": [
            {"id": "bound_gem", "name": "绑钻", "count": 100, "icon": "res://assets/icons/icon_gem.svg"},
            {"id": "scroll_wind", "name": "风元素召唤卷轴", "count": 1, "icon": "res://assets/icons/icon_wind.svg"},
        ],
    },
    {
        "id": 1005, "name": "元素祭坛", "kind": "event", "subtitle": "随机事件 · 奇遇",
        "recommend_power": 0, "stamina": 0, "pre_stage_id": 1004, "is_boss": False,
        "enemies": [],
        "mechanic": "非战斗节点：在祭坛前做出选择，代价与收益都由选择决定。",
        "options": [
            {"id": "pray", "name": "祈祷", "cost": {"currency": "gold", "count": 100},
             "grant": {"buff": {"stat": "atk", "mult": 1.15, "scope": "team", "battles": 1,
                                "name": "祭坛祝福", "desc": "下一场战斗己方全队攻击力 +15%"}}},
            {"id": "sacrifice", "name": "献祭", "cost": {"stamina": 20},
             "grant": {"item": {"id": "shard_mystic_girl", "name": "SSR 秘法少女碎片", "count": 5,
                                "icon": "res://assets/icons/icon_light.svg"}}},
            {"id": "leave", "name": "离开", "cost": {}, "grant": {}},
        ],
        "rewards": [],
    },
    {
        "id": 1006, "name": "破碎遗迹", "kind": "battle", "subtitle": "普通战斗",
        "recommend_power": 7800, "stamina": 6, "pre_stage_id": 1004, "is_boss": False,
        "difficulty": 0.85,
        "enemies": [{"slot": 1, "mob": "ruin_guard"}, {"slot": 3, "mob": "ruin_guard"},
                    {"slot": 5, "mob": "puppet_mage"}],
        "mechanic": "傀儡法师具有群体护盾技能，需使用高单体爆发英雄快速减员。",
        "tactics": "石像守卫硬、傀儡法师每三次行动糊一层全队护盾；群攻在这儿是给护盾送效率，要单点爆破。",
        "rewards": [
            {"id": "gold", "name": "金币", "count": 1800, "icon": "res://assets/icons/icon_coin.svg"},
            {"id": "hero_exp", "name": "英雄经验", "count": 2500, "icon": "res://assets/icons/icon_star.svg"},
        ],
    },
    {
        "id": 1007, "name": "奇遇喷泉", "kind": "rest", "subtitle": "宝箱 / 休息节点",
        "recommend_power": 0, "stamina": 0, "pre_stage_id": 1006, "is_boss": False,
        "enemies": [],
        "mechanic": "节点效果：恢复全队英雄 100% 生命值，并获得【云端宝箱】。",
        "restore": {"hp_pct": 1.0, "scope": "team"},
        "rewards": [
            {"id": "bound_gem", "name": "绑钻", "count": 80, "icon": "res://assets/icons/icon_gem.svg"},
            {"id": "ticket_basic", "name": "普通抽卡券", "count": 1, "icon": "res://assets/icons/icon_gift.svg"},
        ],
    },
    {
        "id": 1008, "name": "精英部落", "kind": "elite", "subtitle": "高难支线 · 精英挑战",
        "recommend_power": 10500, "stamina": 10, "pre_stage_id": 1003, "is_boss": False,
        "difficulty": 0.85,
        "enemies": [{"slot": 1, "mob": "goblin_chief"}, {"slot": 4, "mob": "stone_slinger"},
                    {"slot": 6, "mob": "stone_slinger"}, {"slot": 8, "mob": "goblin_shaman"}],
        "mechanic": "后排萨满提供持续治疗，中排投石手对己方后排造成高额范围伤害。",
        "tactics": "考验阵容整体恢复与耐受力：不切掉萨满，前排就永远磨不掉；不管后排，投石手会把你的输出先砸没。",
        "rewards": [
            {"id": "equip_acrylic_glove", "name": "SR级装备【亮面亚克力护手】", "count": 1,
             "icon": "res://assets/icons/icon_atk.svg"},
            {"id": "shard_ssr", "name": "SSR英雄碎片", "count": 5, "icon": "res://assets/icons/icon_star.svg"},
        ],
    },
    {
        "id": 1009, "name": "枯髅门前哨", "kind": "battle", "subtitle": "Boss 前夜 · 常规战斗",
        "recommend_power": 11200, "stamina": 6, "pre_stage_id": 1008, "is_boss": False,
        "difficulty": 0.85,
        "enemies": [{"slot": 1, "mob": "nut_soldier"}, {"slot": 3, "mob": "nut_soldier"},
                    {"slot": 5, "mob": "storm_elemental"}, {"slot": 8, "mob": "goblin_shaman"}],
        "mechanic": "Boss 战前的阵容调配测试，确保队伍具备「破盾 + 切后 + 承伤」完整体系。",
        "tactics": "坚硬前排 + 中排元素 AOE + 后排治疗，是 Boss 阵容的缩水版；能稳过这里，1010 才有得打。",
        "rewards": [
            {"id": "gold", "name": "金币", "count": 2200, "icon": "res://assets/icons/icon_coin.svg"},
            {"id": "break_stone_1", "name": "1阶突破石", "count": 10, "icon": "res://assets/icons/icon_def.svg"},
        ],
    },
    {
        "id": 1010, "name": "枯髅门 · 巨石守卫", "kind": "boss", "subtitle": "章节最终 Boss 战",
        "recommend_power": 12500, "stamina": 8, "pre_stage_id": 1009, "is_boss": True,
        "difficulty": 0.85, "first_clear_only": True,
        "enemies": [{"slot": 1, "mob": "nut_soldier"}, {"slot": 3, "mob": "nut_soldier"},
                    {"slot": 4, "mob": "storm_elemental"}, {"slot": 5, "mob": "stone_warden"},
                    {"slot": 6, "mob": "storm_elemental"}, {"slot": 8, "mob": "goblin_shaman"}],
        "mechanic": "Boss 特性：【花岗岩护甲】物理减伤 30%，开局拥有 20% 最大生命值的护盾；"
                    "【裂地震击】满能量释放，对前排造成 200% 物理伤害并附带 50% 概率眩晕。",
        "tactics": "物理队会被护甲吃掉三成伤害，开局先破那层 20% 的盾；中排两只风暴元素持续压中排血量，"
                   "萨满还在后面续命 —— 破盾、切后、承伤，缺一环就打不过。",
        "rewards": [
            {"id": "gem", "name": "彩虹钻石", "count": 300, "icon": "res://assets/icons/icon_gem.svg"},
            {"id": "ticket_advanced", "name": "高级召唤卷轴", "count": 5, "icon": "res://assets/icons/icon_gift.svg"},
            {"id": "hero_mystic_girl", "name": "SSR英雄【秘法少女】", "count": 1,
             "icon": "res://assets/icons/icon_light.svg", "first_clear": True},
        ],
    },
]

# 与选关页现有 3 个节点对齐（名称以策划表为准，锚点/anchor_note 不动）
NODE_FIX = {
    1001: {"name": "初始之地", "stamina": 0, "recommend_power": 1000},
    1003: {"name": "云端城堡", "stamina": 8, "recommend_power": 4800},
    1004: {"name": "风暴元素", "stamina": 6, "recommend_power": 6200},
}

# 新增关卡类型（rest / boss 在选关页地图上暂时没有节点，但战斗侧要认识它们）
NEW_KINDS = [
    {"id": "rest", "name": "休息 / 宝箱"},
    {"id": "boss", "name": "章节 Boss 战"},
]

# 我方英雄的大招数值：策划表只写了技能名与目标语义，倍率由这里补齐。
# 放在 characters[].skill.effect 而不是内核里，是为了让「技能数值」和「技能描述」
# 躺在同一处 —— 以后做技能升级只需要改这个字段。
PLAYER_ULTS = {
    "knight_rock": {
        "name": "磐岩壁垒", "kind": "shield_all", "target": "self_and_adjacent_front", "from": "def",
        "mult": 2.2, "turns": 2,
        "note": "护盾量 = 自身防御 × 220%，与技能描述一致",
    },
    "pyro_girl": {
        "name": "紫焰风暴", "kind": "attack", "target": "enemy_middle_row", "damage": "magic",
        "mult": 1.35, "aoe": True,
    },
    "elf_ranger": {
        "name": "穿云箭", "kind": "attack", "target": "enemy_back_lowest_hp", "damage": "phys",
        "mult": 2.2,
    },
    "holy_priest": {
        "name": "圣光洗礼", "kind": "heal", "target": "all_allies", "heal_pct": 0.28,
        "note": "治疗量按目标最大生命值的 28% 计，避免牧师攻击力过低导致奶量失真",
    },
}

# 每关的战场环境配色：目前没有战斗背景美术，先由这组颜色在运行时铺出
# 「天光 + 云带 + 浮岛剪影 + 石台」的程序化战场。等有整张背景图后，
# 把图的路径写进 stage.bg，运行时就会直接用图、忽略 theme。
THEMES = {
    1001: {"sky_top": "#FFDCA8", "sky_bottom": "#FFF6E4", "sun": "#FFE7A8",
           "ground": "#9CCB74", "rim": "#5FA83C", "haze": "#5B7FA8"},
    1002: {"sky_top": "#A9D9B3", "sky_bottom": "#EDF8E6", "sun": "#D8F0B0",
           "ground": "#6E9B5A", "rim": "#3F6B34", "haze": "#3F7A6A"},
    1003: {"sky_top": "#FFC58C", "sky_bottom": "#FFF1DE", "sun": "#FFD9A0",
           "ground": "#B9A48C", "rim": "#7C664E", "haze": "#8A6E9E"},
    1004: {"sky_top": "#7E93C4", "sky_bottom": "#DFE9F8", "sun": "#C9D8F5",
           "ground": "#8C93A8", "rim": "#5A6178", "haze": "#3E4C6E"},
    1006: {"sky_top": "#CBB68F", "sky_bottom": "#F6EDDA", "sun": "#F0D9A8",
           "ground": "#9A8B72", "rim": "#665B47", "haze": "#6E5F4A"},
    1008: {"sky_top": "#E2A274", "sky_bottom": "#FCE8D2", "sun": "#FFC98A",
           "ground": "#8A6A4E", "rim": "#553D2A", "haze": "#6B4A34"},
    1009: {"sky_top": "#B2A2C2", "sky_bottom": "#EFE6F4", "sun": "#DCC8E8",
           "ground": "#8F8298", "rim": "#5C5266", "haze": "#584A6A"},
    1010: {"sky_top": "#6E5A7A", "sky_bottom": "#CBBAD2", "sun": "#B79BC4",
           "ground": "#7A6A80", "rim": "#463A4E", "haze": "#3A2E46"},
}
DEFAULT_THEME = {"sky_top": "#8FB4D8", "sky_bottom": "#F2F7FB", "sun": "#FFF0C0",
                 "ground": "#9AA3AE", "rim": "#5E6670", "haze": "#5A6C86"}

BATTLE_CFG = {
    "layout_note": "战场坐标同样按 1920x1080 视口像素。格子位置 = origin + col_step*(col-1) + 该侧的 depth_step*相对排数，"
                   "相对排数：两侧都以前排为 0、中排 1、后排 2。敌方 depth_step 朝左上、我方朝左下，"
                   "于是两块棋盘各自往后收窄，合起来是一片菱形场地，两侧前排在中线附近正对。",
    "col_step": [220, 0],
    "row_step": [-80, -132],
    "player_row_step": [-80, 132],
    "step_note": "row_step 与 player_row_step 的 x 相同、y 相反：后排一律往左收，纵深方向各自朝远离中线的方向走。",
    "enemy_origin": [880, 552],
    "player_origin": [880, 724],
    "origin_note": "origin = 该侧前排中间格（slot 2 / slot 8）的地面锚点。"
                   "竖向占用实测：敌方后排脚下 276、我方后排脚下 984，"
                   "可视范围 116..984（立绘 112~132 高、名牌挂在头顶上方 42px），"
                   "刚好让开顶部信息条（0-108）和底部行动顺序条（996+）。",
    "anchor_note": "格子锚点 = 单位脚下的地面点，立绘以该点向上生长；名牌与血条挂在锚点下方",
    "token": {"w": 156, "px_h": 140, "monster_h": 120, "block_h": 42, "block_w": 116},
    "block_layer_note": "名牌/血条不挂在立绘下方而是挂在**头顶上方**，并单独放 %PlateLayer 盖在所有立绘之上："
                        "一是 2.5D 棋盘上后排单位的血条必然会被前一排立绘压住，掐到独立图层才永远读得到；"
                        "二是挂在脚下会正好落进前一排的脑袋上（排间距 132 < 立绘 112 + 名牌 42），挂头顶就落在空处。",
    "shield_hint": "护盾条绘制在血条之上，用浅蓝描边区分",
    "max_actions": 400,
    "overtime_note": "超过 max_actions 仍未分胜负，按双方剩余血量百分比裁定（高者胜）",
    "screen_rect": [400, 110, 1344, 992],
    "screen_rect_note": "战场可视区，左右两侧留给队伍面板与战报面板，冒烟测试按它断言单位不出框",
}


# --------------------------------------------------------------------------- 计算
def power_of(stats):
    """与 RealmDB.battle_power 同一公式，用来反解 power_scale"""
    return (float(stats["hp"]) * 0.12 + float(stats["atk"]) * 2.4 + float(stats["def"]) * 1.6
            + float(stats["mres"]) * 1.1 + float(stats["spd"]) * 2.0 + float(stats.get("crit", 0.0)) * 600.0)


def solve_scale(enemies, target):
    """反解 power_scale，使得「缩放后敌方总战力」= target

    只缩放 hp/atk/def/mres（战斗成长轴），spd/crit 属于节奏与运气轴，不参与强度缩放 ——
    否则一关光靠堆速度就能把战力撑起来，实际打起来却很怪。
    """
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


def player_team_power(data):
    """按 RealmDB 公式估算演示队伍战力，用来核对关卡难度是否合理"""
    growth = data["growth"]["star_up"]["per_star_attr_bonus"]
    total = 0
    for raw in data["menu"]["demo_team_slots"]:
        cfg = next((c for c in data["characters"] if c["id"] == raw), None)
        if cfg is None:
            continue
        lv = int(cfg.get("demo_level", 1))
        star = int(cfg.get("demo_star", 1))
        mult = 1.0 + float(growth[min(star - 1, len(growth) - 1)])
        st = {}
        for k in ("hp", "atk", "def", "mres"):
            st[k] = (float(cfg["base"][k]) + float(cfg["growth"].get(k, 0)) * (lv - 1)) * mult
        st["spd"] = int(round((float(cfg["base"]["spd"]) + float(cfg["growth"].get("spd", 0)) * (lv - 1)) * mult))
        st["crit"] = float(cfg["base"].get("crit", 0.0))
        total += int(round(power_of(st)))
    return total


# --------------------------------------------------------------------------- 主流程
def main():
    with io.open(DATA, encoding="utf-8") as f:
        data = json.load(f)

    # 1. 怪物表
    data["monsters"] = {
        "note": "第一章敌方单位。base 面板口径与 characters[].base 一致；"
                "action/skill 描述行为，traits 描述 Boss 特性，战斗内核只做解释器。",
        "icon_note": "icon 由 tools/make_monsters.py 生成，改造型重跑该脚本即可，配置不用动。",
        "order": list(MONSTERS.keys()),
        "table": {
            k: dict(v, id=k, icon="%s/mob_%s.svg" % (ICON_BASE, k),
                    portrait="", portrait_note="暂无立绘，战场用 icon 占位；有立绘后填 portrait 即可切过去")
            for k, v in MONSTERS.items()
        },
    }

    # 2. 关卡表（含算出的 power_scale）
    stages = []
    for idx, s in enumerate(STAGES):
        st = dict(s)
        st["no"] = idx + 1          # 章节内序号，界面上显示「第 N 关」用
        st["power_scale"] = round(solve_scale(s["enemies"], s["recommend_power"] * s["difficulty"]), 4) \
            if s["enemies"] else 0.0
        st["theme"] = dict(THEMES.get(s["id"], DEFAULT_THEME))
        st["theme_note"] = "战场环境配色。填了 bg（整张背景图路径）时 theme 失效，直接换成美术图。"
        st["bg"] = ""
        stages.append(st)
    data["adventure"]["chapter_stages"] = {
        "chapter_id": "ch1",
        "title": "云上浮岛 · 初始之痕",
        "note": "第一章全 10 关。power_scale = 使敌方总战力达到「建议战力 × difficulty」的缩放比，"
                "由 tools/_inspect/apply_chapter1.py 反解，改建议战力后重跑即可。",
        "slot_note": "enemies[].slot 取 combat.board.row_slots（1-3 前排 / 4-6 中排 / 7-9 后排）",
        "list": stages,
    }

    # 3. 战斗布局与规则
    data["combat"]["battle"] = BATTLE_CFG

    # 3b. 我方英雄大招数值（写到 skill.effect，与技能描述同处）
    for ch in data["characters"]:
        eff = PLAYER_ULTS.get(str(ch.get("id", "")))
        if eff is not None and isinstance(ch.get("skill"), dict):
            ch["skill"]["effect"] = dict(eff)

    # 4. 章节元信息对齐策划表
    for ch in data["adventure"]["chapters"]:
        if ch.get("id") == "ch1":
            ch["name"] = "云上浮岛·初始之痕"
            ch["stages"] = 10
            ch["recommend_power"] = 1000
            ch["boss"] = "巨石守卫"
            ch["chapter_stages"] = "res://data/game_data.json#adventure.chapter_stages"

    # 5. 关卡类型补全
    kinds = data["adventure"].get("stage_kinds", [])
    have = {str(k.get("id")) for k in kinds}
    for nk in NEW_KINDS:
        if nk["id"] not in have:
            kinds.append(nk)
    data["adventure"]["stage_kinds"] = kinds

    # 6. 选关页节点：只改名称与体力，锚点不动
    for node in data["adventure"]["select_map"]["nodes"]:
        sid = int(node.get("stage_id", 0))
        if sid in NODE_FIX:
            node.update(NODE_FIX[sid])
    data["adventure"]["select_map"]["stamina_note"] = \
        "每关体力以关卡自身的 stamina 为准（1001 引导关免费、1003 精英 8 点、1008 高难支线 10 点）；" \
        "adventure.stamina_per_stage 只作为缺省值。"

    with io.open(DATA, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")

    # ------------------------------------------------------------------ 核对表
    tp = player_team_power(data)
    print("已写入 %s" % os.path.relpath(DATA, ROOT))
    print("演示队伍（%s）战力 ≈ %d\n" % (",".join(data["menu"]["demo_team_slots"]), tp))
    print("%-6s %-14s %-6s %8s %5s %9s %8s  %s" %
          ("编号", "名称", "类型", "建议战力", "体力", "敌方战力", "power_s", "阵容"))
    for s in stages:
        if not s["enemies"]:
            print("%-6d %-14s %-6s %8d %5d %9s %8s  %s" %
                  (s["id"], s["name"], s["kind"], s["recommend_power"], s["stamina"], "-", "-",
                   "非战斗节点"))
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
        print("%-6d %-14s %-6s %8d %5d %9d %8.3f  %s" %
              (s["id"], s["name"], s["kind"], s["recommend_power"], s["stamina"],
               int(round(total)), s["power_scale"], " ".join(lineup)))
    print("\n怪物 %d 只，关卡 %d 关" % (len(MONSTERS), len(STAGES)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
