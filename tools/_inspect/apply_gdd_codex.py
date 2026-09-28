# -*- coding: utf-8 -*-
"""apply_gdd_codex.py —— 把 GDD 扩展（卡牌全图鉴与英雄信息表）写回 data/game_data.json

    python tools/_inspect/apply_gdd_codex.py

幂等：按 id 定位 characters 条目（存在则补字段，不存在则追加），其余段落原样保留。

本次落地的三块内容：
  1. `characters` 新增 4 名英雄（秘法少女 / 暗夜刺客 / 大地守卫 / 炎赫骑士），
     已有 4 名英雄补 `codex` 图鉴信息（英雄名 / 战斗定位 / 普攻 / 绝技 / 被动）。
  2. `formation.synergies` 追加 4 条 GDD 羁绊（云端先锋队 / 自然之护 / 光暗交织 / 全元素共鸣），
     schema 扩展见 docs：cond.type 新增 `char_ids`，effect 升级为 `effects` 多效果数组。
  3. 新增顶层 `codex` 段（职业定位矩阵）与 `roles.*.class`（四大职业归类）。

数值口径
--------
GDD 给的是「Lv.30 基础面板」（未计星级系数）。项目公式为
    最终值 = (base + growth × (等级-1)) × 星级系数
因此这里把 GDD 面板按**同稀有度参照卡**的 base 占比拆成 base / growth，
保证成长曲线形状与既有卡一致，且 Lv.30 未计星时的总量 = GDD 面板。
参照卡见 REF_RATIO，改 GDD 数值后重跑本脚本即可。
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
DATA_PATH = os.path.join(ROOT, "data", "game_data.json")

ART = "res://assets/art/characters"

# ---------------------------------------------------------------------------
# 1. 新英雄。base / growth 由 REF_RATIO × GDD Lv.30 面板反解（见文件头说明）
# ---------------------------------------------------------------------------

NEW_HEROES = [
    {
        "id": "arcane_girl",
        "name": "秘法少女",
        "hero_name": "许知夏",
        "title": "燎原的星火",
        "rarity": "SSR",
        "element": "fire",
        "role": "mage",
        "portrait": f"{ART}/char_arcane_girl.png",
        "prefer_slot": 5,
        "demo_level": 30,
        "demo_star": 3,
        "base": {"hp": 626, "atk": 238, "def": 44, "mres": 76,
                 "crit": 0.12, "crit_dmg": 1.65, "hit": 0.08, "spd": 100},
        "growth": {"hp": 35.3, "atk": 9.7, "def": 2.6, "mres": 3.9, "spd": 0.35},
        "codex": {
            "class": "dps",
            "battle_role": "中排群体魔法 / 范围破盾 / 持续灼烧",
            "gdd_panel_lv30": {"hp": 1650, "atk": 520, "def": 120, "mres": 190, "spd": 110},
            "attack": {"name": "火球术", "desc": "对敌方单体造成 120% 魔法伤害。"},
            "ult": {"name": "陨星风暴",
                    "desc": "呼唤流星砸向敌方全体，造成 210% 魔法伤害，对带有护盾的目标额外造成 50% 破盾伤害，并附加 2 回合【灼烧】。"},
            "passive": {"name": "元素共鸣", "desc": "同阵营存在前排英雄时，自身基础魔法攻击力提升 15%。"},
        },
        "skill": {
            "name": "陨星风暴",
            "type": "ult",
            "cost": 100,
            "target": "enemy_all_foes",
            "desc": "呼唤流星砸向敌方全体，造成 210% 魔法伤害，并附加 2 回合【灼烧】。",
            "shards": [
                {"star": 3, "desc": "对带护盾目标额外造成 50% 破盾伤害"},
                {"star": 5, "desc": "灼烧可叠加 2 层"},
            ],
            "effect": {
                "name": "陨星风暴",
                "kind": "attack",
                "target": "enemy_all_foes",
                "damage": "magic",
                "mult": 1.30,
                "aoe": True,
                "note": "GDD 描述为 210% 全体 + 破盾 + 灼烧；战斗内核当前按 130% 全体魔法结算，破盾与灼烧为待接入项",
            },
        },
    },
    {
        "id": "shadow_assassin",
        "name": "暗夜刺客",
        "hero_name": "影刃",
        "title": "无声的刃",
        "rarity": "SSR",
        "element": "dark",
        "role": "assassin",
        "portrait": f"{ART}/char_shadow_assassin.png",
        "prefer_slot": 7,
        "demo_level": 30,
        "demo_star": 3,
        "base": {"hp": 535, "atk": 268, "def": 39, "mres": 43,
                 "crit": 0.24, "crit_dmg": 1.78, "hit": 0.10, "spd": 120},
        "growth": {"hp": 29.8, "atk": 10.8, "def": 2.1, "mres": 2.3, "spd": 0.52},
        "codex": {
            "class": "agile",
            "battle_role": "后排斩杀 / 隐身避伤 / 高暴击",
            "gdd_panel_lv30": {"hp": 1400, "atk": 580, "def": 100, "mres": 110, "spd": 135},
            "attack": {"name": "暗影刺击", "desc": "跳跃至敌方后排，对血量最低的单位造成 150% 物理伤害。"},
            "ult": {"name": "瞬狱影杀阵",
                    "desc": "对敌方后排目标进行 5 次连续穿刺，总计造成 450% 物理伤害，若击杀目标则立即恢复 50% 能量。"},
            "passive": {"name": "夜色掩护", "desc": "开局前 2 回合进入隐身状态，无法被单体技能选中。"},
        },
        "skill": {
            "name": "瞬狱影杀阵",
            "type": "ult",
            "cost": 100,
            "target": "enemy_back_lowest_hp",
            "desc": "对敌方后排血量最低单位连续穿刺，造成 320% 物理伤害，击杀目标则恢复 50% 能量。",
            "shards": [
                {"star": 3, "desc": "击杀后立即再行动一次"},
                {"star": 5, "desc": "穿刺段数提升至 7 段"},
            ],
            "effect": {
                "name": "瞬狱影杀阵",
                "kind": "attack",
                "target": "enemy_back_lowest_hp",
                "damage": "phys",
                "mult": 2.6,
                "note": "GDD 描述为 5 段共 450%；战斗内核按单次 260% 结算，多段拆分与击杀回能为待接入项",
            },
        },
    },
    {
        "id": "earth_guardian",
        "name": "大地守卫",
        "hero_name": "托尔",
        "title": "移动的山峦",
        "rarity": "SR",
        "element": "earth",
        "role": "tank",
        "portrait": f"{ART}/char_earth_guardian.png",
        "prefer_slot": 2,
        "demo_level": 30,
        "demo_star": 2,
        "base": {"hp": 1441, "atk": 119, "def": 152, "mres": 113,
                 "crit": 0.05, "crit_dmg": 1.50, "hit": 0.0, "spd": 85},
        "growth": {"hp": 46.9, "atk": 3.1, "def": 5.4, "mres": 3.7, "spd": 0.17},
        "codex": {
            "class": "front",
            "battle_role": "前排承伤 / 嘲讽 / 减伤",
            "gdd_panel_lv30": {"hp": 2800, "atk": 210, "def": 310, "mres": 220, "spd": 90},
            "attack": {"name": "重锤打击", "desc": "造成 80% 基于防御力的物理伤害。"},
            "ult": {"name": "大地咆哮",
                    "desc": "嘲讽敌方前排与中排所有单位，强制其攻击自己，同时自身获得 30% 伤害减免，持续 2 回合。"},
            "passive": {"name": "岩石体魄", "desc": "生命值每降低 10%，自身物理防御力提升 5%。"},
        },
        "skill": {
            "name": "大地咆哮",
            "type": "ult",
            "cost": 100,
            "target": "all_allies",
            "desc": "为全队附加等同于自身 30% 最大生命的护盾，持续 2 回合（等价于 30% 伤害减免）。",
            "shards": [
                {"star": 3, "desc": "护盾量提升至 45% 最大生命，并免疫击退"},
            ],
            "effect": {
                "name": "大地咆哮",
                "kind": "shield_all",
                "target": "all_allies",
                "from": "max_hp",
                "mult": 0.30,
                "turns": 2,
                "note": "GDD 的【嘲讽】尚未接入战斗内核，当前用「全队 30% 最大生命护盾」承载同一条绝技的减伤语义",
            },
        },
    },
    {
        "id": "flame_knight",
        "name": "炎赫骑士",
        "hero_name": "亚瑟",
        "title": "烈焰的誓约",
        "rarity": "R",
        "element": "fire",
        "role": "warrior",
        "portrait": f"{ART}/char_flame_knight.png",
        "prefer_slot": 1,
        "demo_level": 20,
        "demo_star": 1,
        "base": {"hp": 927, "atk": 102, "def": 93, "mres": 67,
                 "crit": 0.08, "crit_dmg": 1.60, "hit": 0.04, "spd": 92},
        "growth": {"hp": 45.9, "atk": 4.1, "def": 5.1, "mres": 3.3, "spd": 0.16},
        "codex": {
            "class": "front",
            "battle_role": "前排基础承伤 / 反击",
            "gdd_panel_lv20": {"hp": 1800, "atk": 180, "def": 190, "mres": 130, "spd": 95},
            "attack": {"name": "挥剑斩击", "desc": "造成 100% 物理伤害。"},
            "ult": {"name": "烈焰斩",
                    "desc": "对敌方前排单体造成 180% 物理伤害，并恢复自身 10% 最大生命值。"},
            "passive": {"name": "热血", "desc": "受击时有 15% 概率触发反击，造成 80% 伤害。"},
        },
        "skill": {
            "name": "烈焰斩",
            "type": "ult",
            "cost": 100,
            "target": "enemy_front_row",
            "desc": "对敌方前排单体造成 180% 物理伤害，并恢复自身 10% 最大生命值。",
            "shards": [
                {"star": 3, "desc": "自愈提升至 20% 最大生命"},
            ],
            "effect": {
                "name": "烈焰斩",
                "kind": "attack",
                "target": "enemy_front_row",
                "damage": "phys",
                "mult": 1.80,
                "note": "自愈与反击被动为待接入项，当前只结算 180% 物理伤害",
            },
        },
    },
]

# ---------------------------------------------------------------------------
# 2. 已有英雄的图鉴信息补全（只补信息字段，不动已平衡的战斗数值）
# ---------------------------------------------------------------------------

EXISTING_CODEX = {
    "knight_rock": {
        "class": "front",
        "battle_role": "前排承伤 / 群体护盾",
        "attack": {"name": "岩盾冲撞", "desc": "对敌方前排单体造成 100% 物理伤害。"},
        "ult": {"name": "磐岩壁垒", "desc": "为自身与相邻前排单位附加等同于自身 DEF 220% 的护盾，持续 2 回合。"},
        "passive": {"name": "磐石意志", "desc": "自身受到的物理伤害降低，护盾存在期间额外减伤。"},
        "source": "项目既有英雄，战斗数值保持不变，图鉴文案据现有配置归纳",
    },
    "pyro_girl": {
        "class": "dps",
        "battle_role": "中排群体魔法 / 持续灼烧",
        "attack": {"name": "魔焰弹", "desc": "对敌方中排单体造成 100% 魔法伤害。"},
        "ult": {"name": "紫焰风暴", "desc": "对敌方中排全体造成 185% 火属性伤害，并附加 3 回合灼烧。"},
        "passive": {"name": "焰心", "desc": "灼烧目标受到的伤害提高。"},
        "source": "项目既有英雄，战斗数值保持不变，图鉴文案据现有配置归纳",
    },
    "elf_ranger": {
        "hero_name": "莱恩",
        "class": "agile",
        "battle_role": "后排单体点杀 / 减速控场",
        "gdd_panel_lv30": {"hp": 1500, "atk": 410, "def": 130, "mres": 140, "spd": 125},
        "attack": {"name": "疾风射击", "desc": "射出快速风箭，造成 110% 物理伤害。"},
        "ult": {"name": "风行连矢", "desc": "连续射出 3 支风箭，每支造成 100% 物理伤害，并降低目标 20% 攻击速度，持续 2 回合。"},
        "passive": {"name": "专注", "desc": "对距离自身越远的敌方目标，造成的伤害越高（最高提升 20%）。"},
    },
    "holy_priest": {
        "hero_name": "依莲",
        "class": "support",
        "battle_role": "后排群体治疗 / 无敌护盾 / 净化负面效果",
        "gdd_panel_lv30": {"hp": 2200, "atk": 320, "def": 180, "mres": 250, "spd": 105},
        "attack": {"name": "圣光弹", "desc": "对敌方前排单体造成 100% 魔法伤害。"},
        "ult": {"name": "神圣降临", "desc": "为己方全队恢复相当于自身攻击力 280% 的生命值，并赋予最虚弱的队友 1 回合【免疫伤害】效果。"},
        "passive": {"name": "光辉庇佑", "desc": "场上每存在一名光系队友，全队受到的魔法伤害降低 8%。"},
    },
}

# ---------------------------------------------------------------------------
# 3. 四条 GDD 羁绊。effect 单条写法仍兼容；这里统一用 effects 多效果数组
# ---------------------------------------------------------------------------

NEW_SYNERGIES = [
    {
        "id": "cloud_vanguard",
        "name": "云端先锋队",
        "cond": {"type": "char_ids", "ids": ["flame_knight", "arcane_girl"], "min": 2},
        "effects": [
            {"stat": "atk", "pct": 0.08, "target": "all"},
            {"stat": "elem_dmg", "pct": 0.10, "target": "all", "element": "fire"},
        ],
        "text": "同时上阵【炎赫骑士】+【秘法少女】：全队攻击 +8%，火元素伤害 +10%",
    },
    {
        "id": "nature_guard",
        "name": "自然之护",
        "cond": {"type": "char_ids", "ids": ["elf_ranger", "earth_guardian"], "min": 2},
        "effects": [
            {"stat": "hp", "pct": 0.12, "target": "row:front"},
            {"stat": "def", "pct": 0.10, "target": "row:front"},
        ],
        "text": "同时上阵【精灵游侠】+【大地守卫】：己方前排生命上限 +12%，防御 +10%",
    },
    {
        "id": "light_dark_weave",
        "name": "光暗交织",
        "cond": {"type": "char_ids", "ids": ["holy_priest", "shadow_assassin"], "min": 2},
        "effects": [
            {"stat": "crit", "value": 0.05, "target": "all"},
            {"stat": "open_energy", "value": 15.0, "target": "all"},
        ],
        "text": "同时上阵【神圣牧师】+【暗夜刺客】：全队暴击率 +5%，开局获得 15 点能量",
    },
    {
        "id": "all_element_resonance",
        "name": "全元素共鸣",
        "cond": {"type": "distinct_elements", "min": 4},
        "effects": [
            {"stat": "open_shield", "value": 0.15, "target": "all"},
        ],
        "text": "上阵 4 种不同元素属性的卡牌：战斗开始时为全员施加相当于自身生命值 15% 的护盾",
    },
]

# ---------------------------------------------------------------------------
# 4. 顶层 codex 段：职业定位矩阵
# ---------------------------------------------------------------------------

CODEX = {
    "title": "英雄图鉴",
    "subtitle": "4 大职业定位 × 6 大元素属性 的战术搭配体系",
    "class_matrix": [
        {"id": "front", "name": "前排", "en_name": "Warrior / Tank", "roles": ["tank", "warrior"],
         "desc": "高血高防，具备护盾、嘲讽或控场能力。"},
        {"id": "dps", "name": "输出", "en_name": "Mage / DPS", "roles": ["mage"],
         "desc": "核心伤害制造者，分为单体爆破与群体魔法伤害。"},
        {"id": "agile", "name": "游侠 / 刺客", "en_name": "Ranger / Assassin", "roles": ["archer", "assassin"],
         "desc": "高攻速、高暴击，优先锁定敌方后排或残血目标。"},
        {"id": "support", "name": "辅助", "en_name": "Support / Healer", "roles": ["healer", "support"],
         "desc": "提供群体治疗、能量恢复或战术增益（Buff）。"},
    ],
    "codex_fields": ["hero_name", "battle_role", "attack", "ult", "passive"],
    "note": "每条英雄的图鉴信息挂在 characters[].codex 下；战斗只读 base / growth / skill，图鉴信息纯展示。",
}

ROLE_CLASS = {
    "tank": "front", "warrior": "front",
    "mage": "dps",
    "archer": "agile", "assassin": "agile",
    "healer": "support", "support": "support",
}


def main() -> None:
    with open(DATA_PATH, encoding="utf-8") as f:
        data = json.load(f)

    chars = data["characters"]
    by_id = {str(c.get("id", "")): c for c in chars}

    added, patched = [], []
    for hero in NEW_HEROES:
        if hero["id"] in by_id:
            by_id[hero["id"]].update(hero)
            patched.append(hero["id"])
        else:
            chars.append(hero)
            added.append(hero["id"])

    for cid, info in EXISTING_CODEX.items():
        if cid not in by_id:
            print(f"[warn] 已有英雄 {cid} 不在 characters 里，跳过补全")
            continue
        card = by_id[cid]
        if "hero_name" in info:
            card["hero_name"] = info["hero_name"]
        card["codex"] = {k: v for k, v in info.items() if k != "hero_name"}
        patched.append(cid)

    # 羁绊：按 id 覆盖，保留既有 6 条
    syn = data["formation"]["synergies"]
    existing_ids = {str(s.get("id", "")) for s in syn}
    syn.extend([s for s in NEW_SYNERGIES if s["id"] not in existing_ids])

    # 职业归类
    for rid, cls in ROLE_CLASS.items():
        if rid in data["roles"]:
            data["roles"][rid]["class"] = cls

    data["codex"] = CODEX

    with open(DATA_PATH, "w", encoding="utf-8", newline="\r\n") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")

    print(f"[ok] 新增英雄 {len(added)}：{added}")
    print(f"[ok] 更新条目 {len(set(patched))} 条：{sorted(set(patched))}")
    print(f"[ok] 羁绊总数 {len(syn)}（新增 {len(NEW_SYNERGIES)}）")
    print(f"[ok] 角色总数 {len(chars)}")


if __name__ == "__main__":
    main()
