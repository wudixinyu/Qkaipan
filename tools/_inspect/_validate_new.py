# -*- coding: utf-8 -*-
"""校验 game_data.json 新批 10 卡落地后的完整性。"""
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
data = json.load(open(os.path.join(ROOT, "data", "game_data.json"), encoding="utf-8"))

ART = os.path.join(ROOT, "assets", "art", "characters")
chars = data["characters"]
ids = [c["id"] for c in chars]
print("角色总数:", len(chars), "| 唯一:", len(set(ids)) == len(ids))

ROLE_CLASS = {"tank": "front", "warrior": "front", "mage": "dps",
              "archer": "agile", "assassin": "agile", "healer": "support", "support": "support"}
elements = set(data["elements"]["table"].keys())
roles = set(data["roles"].keys())
rarity_order = data["rarities"]["order"]

errs = []
for c in chars:
    cid = c["id"]
    if c["element"] not in elements: errs.append(f"{cid} 元素非法 {c['element']}")
    if c["role"] not in roles: errs.append(f"{cid} 职业非法 {c['role']}")
    if c["rarity"] not in rarity_order: errs.append(f"{cid} 品质非法 {c['rarity']}")
    for k in ("hp", "atk", "def", "mres", "spd", "crit", "crit_dmg", "hit"):
        if k not in c["base"]: errs.append(f"{cid} base 缺 {k}")
    for k in ("hp", "atk", "def", "mres", "spd"):
        if k not in c["growth"]: errs.append(f"{cid} growth 缺 {k}")
    cod = c.get("codex", {})
    for k in ("class", "battle_role", "attack", "ult", "passive"):
        if not cod.get(k): errs.append(f"{cid} codex 缺 {k}")
    if cod.get("class") != ROLE_CLASS[c["role"]]:
        errs.append(f"{cid} class 与 role 不匹配")
    if not c.get("hero_name"): errs.append(f"{cid} 缺 hero_name")
    # portrait 文件存在（res:// 映射到项目根）
    rel = c["portrait"].replace("res://", "")
    if not os.path.exists(os.path.join(ROOT, rel)): errs.append(f"{cid} 立绘缺失 {rel}")
    # skill effect 合法 kind
    kind = c.get("skill", {}).get("effect", {}).get("kind", "")
    if kind not in ("attack", "heal", "shield_all", "buff_atk"):
        errs.append(f"{cid} skill.kind 非法 {kind}")

# 卡池 hero id 必须能查到角色
for p in data["gacha"]["pools"]:
    for rar, tier in p.get("pool", {}).items():
        for e in tier:
            if str(e.get("type", "")) == "hero" and e.get("id") not in ids:
                errs.append(f"池 {p['id']}/{rar} 引用不存在英雄 {e.get('id')}")

std = next(p for p in data["gacha"]["pools"] if p["id"] == "standard")
print("standard 池各档人数:",
      {r: sum(1 for e in t if e.get('type') == 'hero') for r, t in std['pool'].items()})
new_ids = ['tide_siren','shadow_blade','light_catherine','forest_sedric','wind_yahi',
           'ice_eli','rock_baroque','dark_leila','lily_mage','tom_ranger']
print("10 新卡全部在 standard:", all(any(e.get('id')==n for t in std['pool'].values() for e in t) for n in new_ids))

print("错误数:", len(errs))
for e in errs:
    print("  -", e)
print("OK" if not errs else "HAS_ERRORS")
