# -*- coding: utf-8 -*-
"""apply_team_unlock.py —— 把「上阵数量随玩家等级解锁」的规则写回 data/game_data.json

规则（用户设定）：1 级只能上阵 1 人，每 10 级 +1，最大 9 人，玩家等级最大 100。
公式：cap = clamp(base + level // interval, base, max_members)

幂等：只改 formation.team.unlock / formation.team.max_members /
formation.toast.slot_locked 三处，其余段落原样保留。

    python tools/_inspect/apply_team_unlock.py
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
DATA_PATH = os.path.join(ROOT, "data", "game_data.json")

# 解锁规则：base 人起步，每 interval 级 +1，封顶 max（= 棋盘槽位数），玩家等级封顶 level_cap
UNLOCK = {
    "note": "上阵数量按玩家等级解锁：base 起步，每 interval 级 +1，封顶 max",
    "base": 1,            # 1 级只能上阵 1 人
    "interval": 10,       # 每 10 级 +1
    "max": 9,             # 最大 9 人（正好铺满 3×3 棋盘）
    "level_cap": 100,     # 玩家等级上限
}

with open(DATA_PATH, "r", encoding="utf-8") as f:
    data = json.load(f)

team = data["formation"]["team"]
team["unlock"] = UNLOCK
# max_members 现在是「绝对上限」= 棋盘格数 = 解锁封顶（9）；
# 运行时按等级算出的动态上限走 SaveDB.team_max()（= GameDB.team_max_for_level）。
team["max_members"] = UNLOCK["max"]
data["formation"].setdefault("toast", {})["slot_locked"] = \
    "该槽位尚未解锁 · Lv.%d 可上阵 %d 人"

with open(DATA_PATH, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")

print("[apply_team_unlock] unlock=%s" % json.dumps(UNLOCK, ensure_ascii=False))
print("[apply_team_unlock] toast.slot_locked=%s"
      % data["formation"]["toast"]["slot_locked"])
