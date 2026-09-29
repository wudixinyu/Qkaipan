# -*- coding: utf-8 -*-
"""apply_gdd_codex2.py —— 把 GDD 扩展第二批（10 张新卡全图鉴）写回 data/game_data.json

    python tools/_inspect/apply_gdd_codex2.py

幂等：按 id 定位 characters 条目（存在则整体覆盖，不存在则追加）；
卡池接入按 (pool_id, rarity, hero_id) 去重，重复运行不会叠加。

本批落地内容
------------
  1. characters 新增 10 名英雄（UR×2 / SSR×3 / SR×3 / R×2），含
     base / growth（战斗用）、codex（图鉴展示）、skill（战斗绝技近似）。
  2. gacha.pools 中「常驻召唤 standard」按稀有度接入这 10 名英雄
     （限时池 limited、友情池 friend 不动，保持既有抽卡冒烟断言口径）。

数值口径（与 apply_gdd_codex.py 一致）
------------------------------------
GDD 给的是「Lv.30（R 卡 Lv.20）基础面板」（未计星级系数）。项目公式为
    最终值 = (base + growth × (等级-1)) × 星级系数
按**同稀有度参照卡**的 base 占比把面板拆成 base / growth，
使 Lv.30/Lv.20 未计星总量 = GDD 面板（±1）。参照卡：
    UR→holy_priest  SSR→(mage:arcane_girl / tank:earth_guardian / archer:elf_ranger)
    SR→(mage:arcane_girl / tank:earth_guardian / archer:elf_ranger)  R→flame_knight
立绘为「复用现有相近 PNG 占位」（后续再逐张替换专属立绘）。
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
DATA_PATH = os.path.join(ROOT, "data", "game_data.json")
ART = "res://assets/art/characters"

ROLE_CLASS = {
    "tank": "front", "warrior": "front", "mage": "dps",
    "archer": "agile", "assassin": "agile", "healer": "support", "support": "support",
}


def hero(cid, name, hero_name, title, rarity, element, role, slot, portrait,
         base, growth, panel_key, panel, battle_role, atk, ult, passive, skill):
    return {
        "id": cid, "name": name, "hero_name": hero_name, "title": title,
        "rarity": rarity, "element": element, "role": role,
        "portrait": f"{ART}/{portrait}", "prefer_slot": slot,
        "demo_level": 1, "demo_star": 1,
        "base": base, "growth": growth,
        "codex": {
            "class": ROLE_CLASS[role], "battle_role": battle_role,
            panel_key: panel,
            "attack": {"name": atk[0], "desc": atk[1]},
            "ult": {"name": ult[0], "desc": ult[1]},
            "passive": {"name": passive[0], "desc": passive[1]},
        },
        "skill": skill,
    }


def B(hp, atk, dfn, mres, spd, crit, cd, hit):
    return {"hp": hp, "atk": atk, "def": dfn, "mres": mres,
            "crit": crit, "crit_dmg": cd, "hit": hit, "spd": spd}


def G(hp, atk, dfn, mres, spd):
    return {"hp": hp, "atk": atk, "def": dfn, "mres": mres, "spd": spd}


NEW_HEROES = [
    hero(
        "tide_siren", "潮汐领主", "塞壬", "覆海的歌姬", "UR", "water", "support", 8,
        "char_priest.png",
        B(729, 156, 70, 109, 97, 0.06, 1.5, 0.10), G(42.1, 6.7, 4.1, 5.2, 0.38),
        "gdd_panel_lv30", {"hp": 1950, "atk": 350, "def": 190, "mres": 260, "spd": 108},
        "后排群体增益 / 减速控场 / 能量加速",
        ("水枪术", "对敌方单体造成 110% 魔法伤害。"),
        ("潮汐怒吼", "呼唤巨大的海浪席卷敌方全体，造成 190% 魔法伤害，并使其攻击速度和移动速度降低 30%，持续 2 回合。"),
        ("潮汐庇佑", "全队水系队友的基础攻击力提升 10%。"),
        {"name": "潮汐怒吼", "type": "ult", "cost": 100, "target": "enemy_all_foes",
         "desc": "呼唤巨大的海浪席卷敌方全体，造成 190% 魔法伤害，并使其攻击速度和移动速度降低 30%，持续 2 回合。",
         "shards": [{"star": 3, "desc": "减速提升至 40%，并额外降低目标 15% 防御"}],
         "effect": {"name": "潮汐怒吼", "kind": "attack", "target": "enemy_all_foes",
                    "damage": "magic", "mult": 1.30, "aoe": True,
                    "note": "GDD 描述为 190% 全体 + 攻速/移速 -30%；战斗内核当前按 130% 全体魔法结算，减速为待接入项"}},
    ),
    hero(
        "shadow_blade", "暗影武者", "刃", "无相的斩", "UR", "dark", "assassin", 7,
        "char_shadow_assassin.png",
        B(561, 272, 41, 50, 124, 0.24, 1.78, 0.10), G(32.4, 11.7, 2.4, 2.4, 0.48),
        "gdd_panel_lv30", {"hp": 1500, "atk": 610, "def": 110, "mres": 120, "spd": 138},
        "后排爆发 / 连击 / 暴击爆伤",
        ("暗影连击", "快速对敌方单体进行 2 次攻击，总计造成 140% 物理伤害。"),
        ("瞬狱斩", "瞬间移动到敌方最后排血量最低的目标身后，对其造成 480% 物理伤害，并有 50% 概率造成【流血】效果。"),
        ("暗影强化", "自身暴击率提升 10%，暴击伤害提升 20%。"),
        {"name": "瞬狱斩", "type": "ult", "cost": 100, "target": "enemy_back_lowest_hp",
         "desc": "瞬间移动到敌方后排血量最低的目标身后，对其造成 480% 物理伤害，并有 50% 概率造成【流血】效果。",
         "shards": [{"star": 5, "desc": "暴击时【流血】概率提升至 100%"}],
         "effect": {"name": "瞬狱斩", "kind": "attack", "target": "enemy_back_lowest_hp",
                    "damage": "phys", "mult": 3.0,
                    "note": "GDD 描述为单次 480% + 流血；战斗内核按单次 300% 物理结算，流血 DoT 为待接入项"}},
    ),
    hero(
        "light_catherine", "圣光审判者", "凯瑟琳", "黎明裁决", "SSR", "light", "mage", 5,
        "char_pyromancer.png",
        B(645, 247, 48, 80, 102, 0.12, 1.65, 0.08), G(36.4, 10.1, 2.8, 4.1, 0.34),
        "gdd_panel_lv30", {"hp": 1700, "atk": 540, "def": 130, "mres": 200, "spd": 112},
        "后排范围伤害 / 降防 / 魔法爆发",
        ("光束击", "对敌方单体造成 125% 魔法伤害。"),
        ("圣光审判", "天降圣光审判敌方全体，造成 230% 魔法伤害，并使其魔法防御力降低 20%，持续 2 回合。"),
        ("光之共鸣", "同阵营存在光系队友时，自身绝技伤害提升 15%。"),
        {"name": "圣光审判", "type": "ult", "cost": 100, "target": "enemy_all_foes",
         "desc": "天降圣光审判敌方全体，造成 230% 魔法伤害，并使其魔法防御力降低 20%，持续 2 回合。",
         "shards": [{"star": 3, "desc": "降魔防提升至 30%"}],
         "effect": {"name": "圣光审判", "kind": "attack", "target": "enemy_all_foes",
                    "damage": "magic", "mult": 1.35, "aoe": True,
                    "note": "GDD 描述为 230% 全体 + 降魔防 20%；战斗内核当前按 135% 全体魔法结算，降防为待接入项"}},
    ),
    hero(
        "forest_sedric", "森林守护者", "塞德里克", "苍郁的壁垒", "SSR", "earth", "tank", 2,
        "char_earth_guardian.png",
        B(1492, 131, 163, 118, 87, 0.05, 1.5, 0.0), G(48.6, 3.4, 5.8, 3.9, 0.17),
        "gdd_panel_lv30", {"hp": 2900, "atk": 230, "def": 330, "mres": 230, "spd": 92},
        "前排高血高防 / 嘲讽 / 群体减伤",
        ("大地撞击", "造成 90% 基于防御力的物理伤害。"),
        ("橡木护盾", "为自身和周围的队友施加一个相当于自身防御力 180% 的护盾，持续 2 回合。"),
        ("森林强化", "同阵营存在地系队友时，自身生命值上限提升 15%。"),
        {"name": "橡木护盾", "type": "ult", "cost": 100, "target": "self_and_adjacent_front",
         "desc": "为自身和周围的队友施加一个相当于自身防御力 180% 的护盾，持续 2 回合。",
         "shards": [{"star": 3, "desc": "护盾量提升至 DEF 240%"}],
         "effect": {"name": "橡木护盾", "kind": "shield_all", "target": "self_and_adjacent_front",
                    "from": "def", "mult": 1.8, "turns": 2,
                    "note": "护盾量 = 自身防御 × 180%，作用于自身与同排，与技能描述一致"}},
    ),
    hero(
        "wind_yahi", "疾风剑客", "雅希", "追风的剑", "SSR", "wind", "archer", 6,
        "char_ranger.png",
        B(611, 245, 48, 53, 116, 0.18, 1.6, 0.12), G(34.1, 9.8, 2.7, 2.8, 0.48),
        "gdd_panel_lv30", {"hp": 1600, "atk": 530, "def": 125, "mres": 135, "spd": 130},
        "后排快速攻击 / 破防 / 单体物理输出",
        ("疾风刺", "快速对敌方单体进行攻击，造成 130% 物理伤害。"),
        ("狂风连击", "连续对敌方单体进行 5 次攻击，总计造成 420% 物理伤害，并有 40% 概率降低其物理防御力 20%，持续 2 回合。"),
        ("疾风强化", "自身攻击速度提升 15%。"),
        {"name": "狂风连击", "type": "ult", "cost": 100, "target": "enemy_back_lowest_hp",
         "desc": "连续对敌方后排血量最低单位攻击，总计造成 420% 物理伤害，并有 40% 概率降低其物理防御力 20%，持续 2 回合。",
         "shards": [{"star": 5, "desc": "连击段数提升至 6 段"}],
         "effect": {"name": "狂风连击", "kind": "attack", "target": "enemy_back_lowest_hp",
                    "damage": "phys", "mult": 3.0,
                    "note": "GDD 描述为 5 段共 420% + 破防；战斗内核按单次 300% 物理结算，多段拆分与破防为待接入项"}},
    ),
    hero(
        "ice_eli", "冰雪女巫", "艾莉", "霜雪的咒", "SR", "water", "mage", 5,
        "char_arcane_girl.png",
        B(600, 220, 46, 74, 96, 0.12, 1.65, 0.08), G(33.8, 9.0, 2.7, 3.8, 0.34),
        "gdd_panel_lv30", {"hp": 1580, "atk": 480, "def": 125, "mres": 185, "spd": 106},
        "中排单体伤害 / 冰冻控场",
        ("冰弹术", "对敌方单体造成 115% 魔法伤害。"),
        ("冰封术", "对敌方单体造成 290% 魔法伤害，并有 60% 概率使其冻结 1 回合。"),
        ("冰霜强化", "自身魔法攻击力提升 10%。"),
        {"name": "冰封术", "type": "ult", "cost": 100, "target": "enemy_middle_row",
         "desc": "对敌方中排单体造成 290% 魔法伤害，并有 60% 概率使其冻结 1 回合。",
         "shards": [{"star": 3, "desc": "冻结概率提升至 80%"}],
         "effect": {"name": "冰封术", "kind": "attack", "target": "enemy_middle_row",
                    "damage": "magic", "mult": 2.4, "stun_chance": 0.6, "stun_actions": 1,
                    "note": "GDD 的【冻结 1 回合】用眩晕近似承载（60% 概率），伤害按 240% 结算"}},
    ),
    hero(
        "rock_baroque", "岩石守卫", "巴洛克", "不坏的岩壁", "SR", "earth", "tank", 2,
        "char_knight.png",
        B(1415, 125, 158, 110, 86, 0.05, 1.5, 0.0), G(46.0, 3.3, 5.6, 3.6, 0.17),
        "gdd_panel_lv30", {"hp": 2750, "atk": 220, "def": 320, "mres": 215, "spd": 91},
        "前排护盾 / 反击 / 物理防御",
        ("岩石击", "造成 85% 基于防御力的物理伤害。"),
        ("岩石护盾", "为自身施加一个相当于自身防御力 210% 的护盾，并使其受到物理伤害降低 25%，持续 2 回合。"),
        ("岩石强化", "受到物理攻击时，有 20% 概率对攻击者进行反击，造成 80% 基于防御力的物理伤害。"),
        {"name": "岩石护盾", "type": "ult", "cost": 100, "target": "self_and_adjacent_front",
         "desc": "为自身施加一个相当于自身防御力 210% 的护盾，持续 2 回合。",
         "shards": [{"star": 3, "desc": "受物伤降低提升至 35%"}],
         "effect": {"name": "岩石护盾", "kind": "shield_all", "target": "self_and_adjacent_front",
                    "from": "def", "mult": 2.1, "turns": 2,
                    "note": "护盾 = DEF×210%，作用于自身与同排；受物伤 -25% 与反击被动为待接入项"}},
    ),
    hero(
        "dark_leila", "暗夜弓手", "蕾拉", "夜雨的弦", "SR", "dark", "archer", 6,
        "char_shadow_assassin.png",
        B(565, 218, 45, 49, 114, 0.18, 1.6, 0.12), G(31.6, 8.7, 2.4, 2.6, 0.48),
        "gdd_panel_lv30", {"hp": 1480, "atk": 470, "def": 115, "mres": 125, "spd": 128},
        "后排群体伤害 / 流血效果",
        ("暗影箭", "对敌方单体造成 120% 物理伤害。"),
        ("暗影多重箭", "对敌方全体发射暗影之箭，总计造成 180% 物理伤害，并使其有 40% 概率受到【流血】效果。"),
        ("暗夜强化", "自身对带有【流血】效果的目标造成的伤害提升 15%。"),
        {"name": "暗影多重箭", "type": "ult", "cost": 100, "target": "enemy_all_foes",
         "desc": "对敌方全体发射暗影之箭，总计造成 180% 物理伤害，并使其有 40% 概率受到【流血】效果。",
         "shards": [{"star": 3, "desc": "【流血】触发概率提升至 60%"}],
         "effect": {"name": "暗影多重箭", "kind": "attack", "target": "enemy_all_foes",
                    "damage": "phys", "mult": 1.3, "aoe": True,
                    "note": "GDD 描述为 180% 全体 + 流血；战斗内核当前按 130% 全体物理结算，流血 DoT 为待接入项"}},
    ),
    hero(
        "lily_mage", "见习法师", "莉莉", "初燃的火种", "R", "fire", "mage", 5,
        "char_pyromancer.png",
        B(824, 159, 54, 83, 99, 0.10, 1.6, 0.06), G(40.8, 6.4, 2.9, 4.1, 0.16),
        "gdd_panel_lv20", {"hp": 1600, "atk": 280, "def": 110, "mres": 160, "spd": 102},
        "后排单体魔法伤害",
        ("火球击", "对敌方单体造成 110% 魔法伤害。"),
        ("火焰暴击", "对敌方单体造成 240% 魔法伤害，并使其有 30% 概率受到【灼烧】效果。"),
        ("火焰强化", "自身魔法攻击力提升 8%。"),
        {"name": "火焰暴击", "type": "ult", "cost": 100, "target": "enemy_front_row",
         "desc": "对敌方单体造成 240% 魔法伤害，并使其有 30% 概率受到【灼烧】效果。",
         "shards": [{"star": 3, "desc": "【灼烧】触发概率提升至 50%"}],
         "effect": {"name": "火焰暴击", "kind": "attack", "target": "enemy_front_row",
                    "damage": "magic", "mult": 2.0,
                    "note": "GDD 描述为 240% 单体 + 灼烧；战斗内核按 200% 单体魔法结算，灼烧为待接入项"}},
    ),
    hero(
        "tom_ranger", "见习游侠", "汤姆", "领风的箭", "R", "wind", "archer", 6,
        "char_ranger.png",
        B(747, 153, 51, 59, 118, 0.15, 1.6, 0.10), G(37.0, 6.2, 2.8, 2.9, 0.21),
        "gdd_panel_lv20", {"hp": 1450, "atk": 270, "def": 105, "mres": 115, "spd": 122},
        "后排单体物理伤害",
        ("疾风射击", "对敌方单体造成 115% 物理伤害。"),
        ("强力射击", "对敌方单体造成 230% 物理伤害，并有 20% 概率使其流血 2 回合。"),
        ("疾风强化", "自身攻击速度提升 8%。"),
        {"name": "强力射击", "type": "ult", "cost": 100, "target": "enemy_front_row",
         "desc": "对敌方单体造成 230% 物理伤害，并有 20% 概率使其流血 2 回合。",
         "shards": [{"star": 3, "desc": "【流血】持续回合 +1"}],
         "effect": {"name": "强力射击", "kind": "attack", "target": "enemy_front_row",
                    "damage": "phys", "mult": 2.0,
                    "note": "GDD 描述为 230% 单体 + 流血；战斗内核按 200% 单体物理结算，流血 DoT 为待接入项"}},
    ),
]

# 常驻池接入：稀有度 → [(hero_id, weight)]
STANDARD_ADD = {
    "UR": [("tide_siren", 1), ("shadow_blade", 1)],
    "SSR": [("light_catherine", 1), ("forest_sedric", 1), ("wind_yahi", 1)],
    "SR": [("ice_eli", 1), ("rock_baroque", 1), ("dark_leila", 1)],
    "R": [("lily_mage", 3), ("tom_ranger", 3)],
}


def main() -> None:
    with open(DATA_PATH, encoding="utf-8") as f:
        data = json.load(f)

    chars = data["characters"]
    by_id = {str(c.get("id", "")): c for c in chars}

    added, replaced = [], []
    for h in NEW_HEROES:
        if h["id"] in by_id:
            by_id[h["id"]].clear()
            by_id[h["id"]].update(h)
            replaced.append(h["id"])
        else:
            chars.append(h)
            added.append(h["id"])

    # 常驻池接入
    standard = next((p for p in data["gacha"]["pools"] if str(p.get("id", "")) == "standard"), None)
    if standard is None:
        raise SystemExit("[err] 找不到 standard 卡池")
    pool = standard["pool"]
    n_pool = 0
    for rar, items in STANDARD_ADD.items():
        tier = pool.setdefault(rar, [])
        have = {str(e.get("id", "")) for e in tier if str(e.get("type", "")) == "hero"}
        for hid, w in items:
            if hid in have:
                continue
            tier.append({"type": "hero", "id": hid, "weight": w})
            n_pool += 1

    with open(DATA_PATH, "w", encoding="utf-8", newline="\r\n") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")

    print(f"[ok] 新增英雄 {len(added)}：{added}")
    print(f"[ok] 覆盖英雄 {len(replaced)}：{replaced}")
    print(f"[ok] 常驻池新接入 {n_pool} 名英雄；角色总数 {len(chars)}")


if __name__ == "__main__":
    main()
