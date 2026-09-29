#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""apply_ch1_full_map.py —— 把第一章全 10 关铺进 adventure.select_map，并加章节切换栏配置。

用法：
    python tools/_inspect/apply_ch1_full_map.py

幂等：select_map.nodes 与 select_map.chapter_tabs 整体覆写，其余字段不动。

锚点布局约束（与 tools/suites/stage_select_suite.gd 的断言一致）：
  - 每个锚点落在 x∈(400,1500)、y∈(250,900) 的浮岛区；
  - 任意两节点欧氏距离 ≥ 200（浮岛不重叠）；
  - 引导线（parent→child）两端各按 radius 收回后可见段 ∈ [24,260)。
icon 为空 = 该关浮岛由背景自带（1001 石台、1003 中央城堡），不叠加图标；
其余关卡背景里没有对应浮岛，用 stage_isle_plain / castle / storm 补位。
"""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CFG = ROOT / "data" / "game_data.json"

ISLE_PLAIN = "res://assets/icons/stage_isle_plain.svg"
ISLE_CASTLE = "res://assets/icons/stage_isle_castle.svg"
ISLE_STORM = "res://assets/icons/stage_isle_storm.svg"

# stage_id -> 地图节点（锚点/半径/图标/角标等），关卡数值口径与 chapter_stages 对齐
NODES = [
    {"stage_id": 1001, "name": "初始之地", "level": 1, "kind": "battle", "tag": "",
     "icon": "", "icon_size": 0, "label_order": "name_level",
     "pos": [649, 587], "label_dy": 56, "radius": 95, "z": 1,
     "pre_stage_id": 0, "demo_stars": 0, "demo_selected": False,
     "stamina": 0, "recommend_power": 1000},
    {"stage_id": 1002, "name": "浮空森林", "level": 1, "kind": "battle", "tag": "",
     "icon": ISLE_PLAIN, "icon_size": 180, "label_order": "name_level",
     "pos": [455, 780], "label_dy": 110, "radius": 90, "z": 2,
     "pre_stage_id": 1001, "demo_stars": 0, "demo_selected": False,
     "stamina": 6, "recommend_power": 2500},
    {"stage_id": 1003, "name": "云端城堡", "level": 1, "kind": "elite", "tag": "精",
     "icon": "", "icon_size": 0, "label_order": "name_level",
     "pos": [937, 400], "label_dy": 99, "radius": 100, "z": 3,
     "pre_stage_id": 1001, "demo_stars": 0, "demo_selected": True,
     "stamina": 8, "recommend_power": 4800},
    {"stage_id": 1004, "name": "风暴元素", "level": 1, "kind": "battle", "tag": "",
     "icon": ISLE_STORM, "icon_size": 208, "label_order": "level_name",
     "pos": [1207, 643], "label_dy": 110, "radius": 90, "z": 4,
     "pre_stage_id": 1003, "demo_stars": 0, "demo_selected": False,
     "stamina": 6, "recommend_power": 6200},
    {"stage_id": 1005, "name": "元素祭坛", "level": 1, "kind": "event", "tag": "福",
     "icon": ISLE_PLAIN, "icon_size": 180, "label_order": "name_level",
     "pos": [1440, 470], "label_dy": 110, "radius": 90, "z": 5,
     "pre_stage_id": 1004, "demo_stars": 0, "demo_selected": False,
     "stamina": 0, "recommend_power": 0},
    {"stage_id": 1006, "name": "破碎遗迹", "level": 1, "kind": "battle", "tag": "",
     "icon": ISLE_PLAIN, "icon_size": 180, "label_order": "name_level",
     "pos": [1000, 790], "label_dy": 110, "radius": 90, "z": 6,
     "pre_stage_id": 1004, "demo_stars": 0, "demo_selected": False,
     "stamina": 6, "recommend_power": 7800},
    {"stage_id": 1007, "name": "奇遇喷泉", "level": 1, "kind": "rest", "tag": "休",
     "icon": ISLE_PLAIN, "icon_size": 180, "label_order": "name_level",
     "pos": [700, 860], "label_dy": 110, "radius": 90, "z": 7,
     "pre_stage_id": 1006, "demo_stars": 0, "demo_selected": False,
     "stamina": 0, "recommend_power": 0},
    {"stage_id": 1008, "name": "精英部落", "level": 1, "kind": "elite", "tag": "精",
     "icon": ISLE_CASTLE, "icon_size": 180, "label_order": "name_level",
     "pos": [640, 300], "label_dy": 110, "radius": 90, "z": 8,
     "pre_stage_id": 1003, "demo_stars": 0, "demo_selected": False,
     "stamina": 10, "recommend_power": 10500},
    {"stage_id": 1009, "name": "枯髅门前哨", "level": 1, "kind": "battle", "tag": "",
     "icon": ISLE_PLAIN, "icon_size": 180, "label_order": "name_level",
     "pos": [430, 300], "label_dy": 110, "radius": 90, "z": 9,
     "pre_stage_id": 1008, "demo_stars": 0, "demo_selected": False,
     "stamina": 6, "recommend_power": 11200},
    {"stage_id": 1010, "name": "枯髅门 · 巨石守卫", "level": 1, "kind": "boss", "tag": "王",
     "icon": ISLE_CASTLE, "icon_size": 190, "label_order": "name_level",
     "pos": [420, 560], "label_dy": 110, "radius": 90, "z": 10,
     "pre_stage_id": 1009, "demo_stars": 0, "demo_selected": False,
     "stamina": 8, "recommend_power": 12500},
]

CHAPTER_TABS = {
    "note": "顶部章节切换栏。仅 chapter_id 对应章节有地图数据，其余为锁定占位；"
            "locked 由 chapter_id 是否为当前章推导，也可在此显式覆盖。",
    "items": [
        {"id": "ch1", "label": "第一章", "name": "云上浮岛·初始之痕", "locked": False},
        {"id": "ch2", "label": "第二章", "name": "熔金回廊", "locked": True},
        {"id": "ch3", "label": "第三章", "name": "星辉圣殿", "locked": True},
    ],
}


def main() -> None:
    raw = CFG.read_text(encoding="utf-8")
    data = json.loads(raw)

    sm = data.setdefault("adventure", {}).setdefault("select_map", {})
    sm["nodes"] = NODES
    sm["chapter_tabs"] = CHAPTER_TABS
    sm["nodes_note"] = "第一章全 10 关铺满地图；锚点满足不重叠(≥200px)与引导线可见段(24~260px)约束。"

    out = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
    CFG.write_text(out, encoding="utf-8")

    print(f"[ok] select_map.nodes -> {len(NODES)} 关；chapter_tabs -> {len(CHAPTER_TABS['items'])} 章")
    for n in NODES:
        print(f"     #{n['stage_id']} {n['name']:<12} {n['kind']:<6} "
              f"pre={n['pre_stage_id']:<4} pos={n['pos']} icon={'bg' if n['icon']=='' else 'overlay'}")
    print(f"     文件 {len(raw.encode('utf-8'))} -> {len(out.encode('utf-8'))} 字节")


if __name__ == "__main__":
    main()
