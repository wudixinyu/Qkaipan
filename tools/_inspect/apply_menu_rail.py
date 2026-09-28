# -*- coding: utf-8 -*-
"""apply_menu_rail.py —— 把主界面右侧竖栏的「系统入口」写回 data/game_data.json

幂等：只覆写 `menu.system_entries` 一个键，其余内容原样保留。

    python tools/_inspect/apply_menu_rail.py

为什么单开一个键而不是塞进 `modes`：
  `modes` 是**玩法模式**（无限之塔 / 迷宫 / 竞技场 / 巅峰对决），四个都是占位按钮，
  点了只弹「模块待接入」；而「卡牌」是**已经做好的系统入口**，要真的切场景。
  两者在竖栏里共用一套外观，但语义、点击行为都不同，混在一起以后没法各自演进。
  竖栏会把 modes 排在前面、system_entries 排在后面，中间加一条分隔线。
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
DATA_PATH = os.path.join(ROOT, "data", "game_data.json")


SYSTEM_ENTRIES = [
    # 与 apply_gacha.py 的 SYSTEM_ENTRIES 保持一致 —— 两个脚本都能单独重跑而不互相打脸
    {
        "id": "gacha",
        "name": "召集",
        "tag": "抽卡 / 水晶商店",
        "icon": "res://assets/icons/icon_gacha.svg",
        "color": "#C08BFF",
        "route": "res://scenes/gacha.tscn",
        "hint": "群星召唤：常驻 / 限时 UP 卡池与心愿水晶商店",
    },
    {
        "id": "cards",
        "name": "卡牌",
        "tag": "编队 / 收藏",
        "icon": "res://assets/icons/icon_cards.svg",
        "color": "#7BE0FF",
        # 有 route 的入口直接切场景；留空才回落到「模块待接入」提示
        "route": "res://scenes/formation.tscn",
        "hint": "查看全部英雄、调整上阵阵容与羁绊",
    },
]


def main():
    with open(DATA_PATH, "r", encoding="utf-8") as f:
        data = json.load(f)

    data.setdefault("menu", {})["system_entries"] = SYSTEM_ENTRIES

    with open(DATA_PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")

    print("[apply_menu_rail] 已写入 menu.system_entries：%d 个系统入口（%s）"
          % (len(SYSTEM_ENTRIES), "、".join(e["name"] for e in SYSTEM_ENTRIES)))


if __name__ == "__main__":
    main()
