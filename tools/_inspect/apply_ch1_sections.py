#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""apply_ch1_sections.py —— 把第一章 10 关拆成 3-3-4 三个小节，每小节一张独立子地图。

用法：
    python tools/_inspect/apply_ch1_sections.py

小节划分（按关卡号连续切段）：
    第一节 ch1_s1 = 1001 / 1002 / 1003   守关关 gate = 1003
    第二节 ch1_s2 = 1004 / 1005 / 1006   守关关 gate = 1006
    第三节 ch1_s3 = 1007 / 1008 / 1009 / 1010   守关关 gate = 1010（章 Boss，其后无小节）

解锁口径：通关上一小节的 gate 关（progress.stage_clears 有记录）即解锁下一小节。
本节点内 pre_stage_id 重排为干净的线性链，跨小节连线一律丢弃。

幂等：整体覆写 adventure.select_map.sections；并把各小节节点拼平成 select_map.nodes
（仅作 legacy 镜像，运行时以 sections 为唯一渲染源），chapter_tabs 不动。

每小节布局约束（与 tools/suites/stage_select_suite.gd 的断言一致）：
  - 锚点落在 x∈(400,1500)、y∈(250,900)；
  - 同节内任意两节点欧氏距离 ≥ 200（浮岛不重叠）；
  - 引导线（pre→cur）两端各按 radius 收回后可见段 ∈ [24,260)。
所有节点统一叠加浮岛图标（plain/castle/storm），不再依赖底图自带浮岛。
"""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CFG = ROOT / "data" / "game_data.json"

ISLE_PLAIN = "res://assets/icons/stage_isle_plain.svg"
ISLE_CASTLE = "res://assets/icons/stage_isle_castle.svg"
ISLE_STORM = "res://assets/icons/stage_isle_storm.svg"

# 关卡静态口径（与原 chapter_stages / 旧 select_map.nodes 对齐）
STAGE_META = {
    1001: {"name": "初始之地", "kind": "battle", "tag": "", "icon": ISLE_PLAIN,
           "icon_size": 180, "radius": 90, "label_order": "name_level",
           "stamina": 0, "recommend_power": 1000},
    1002: {"name": "浮空森林", "kind": "battle", "tag": "", "icon": ISLE_PLAIN,
           "icon_size": 180, "radius": 90, "label_order": "name_level",
           "stamina": 6, "recommend_power": 2500},
    1003: {"name": "云端城堡", "kind": "elite", "tag": "精", "icon": ISLE_CASTLE,
           "icon_size": 190, "radius": 100, "label_order": "name_level",
           "stamina": 8, "recommend_power": 4800},
    1004: {"name": "风暴元素", "kind": "battle", "tag": "", "icon": ISLE_STORM,
           "icon_size": 208, "radius": 100, "label_order": "level_name",
           "stamina": 6, "recommend_power": 6200},
    1005: {"name": "元素祭坛", "kind": "event", "tag": "福", "icon": ISLE_PLAIN,
           "icon_size": 180, "radius": 90, "label_order": "name_level",
           "stamina": 0, "recommend_power": 0},
    1006: {"name": "破碎遗迹", "kind": "battle", "tag": "", "icon": ISLE_PLAIN,
           "icon_size": 180, "radius": 90, "label_order": "name_level",
           "stamina": 6, "recommend_power": 7800},
    1007: {"name": "奇遇喷泉", "kind": "rest", "tag": "休", "icon": ISLE_PLAIN,
           "icon_size": 180, "radius": 90, "label_order": "name_level",
           "stamina": 0, "recommend_power": 0},
    1008: {"name": "精英部落", "kind": "elite", "tag": "精", "icon": ISLE_CASTLE,
           "icon_size": 190, "radius": 100, "label_order": "name_level",
           "stamina": 10, "recommend_power": 10500},
    1009: {"name": "枯髅门前哨", "kind": "battle", "tag": "", "icon": ISLE_PLAIN,
           "icon_size": 180, "radius": 90, "label_order": "name_level",
           "stamina": 6, "recommend_power": 11200},
    1010: {"name": "枯髅门 · 巨石守卫", "kind": "boss", "tag": "王", "icon": ISLE_CASTLE,
           "icon_size": 190, "radius": 100, "label_order": "name_level",
           "stamina": 8, "recommend_power": 12500},
}

# 每小节的链路顺序（pre_stage_id 线性化）与锚点布局
SECTIONS = [
    {
        "id": "ch1_s1", "label": "第一节", "name": "初临浮岛",
        "chain": [
            (1001, (620, 700)),
            (1002, (950, 540)),
            (1003, (1280, 700)),
        ],
    },
    {
        "id": "ch1_s2", "label": "第二节", "name": "风暴试炼",
        "chain": [
            (1004, (620, 700)),
            (1005, (950, 540)),
            (1006, (1280, 700)),
        ],
    },
    {
        "id": "ch1_s3", "label": "第三节", "name": "枯髅之门",
        "chain": [
            (1007, (560, 680)),
            (1008, (820, 470)),
            (1009, (1080, 680)),
            (1010, (1340, 470)),
        ],
    },
]

LABEL_DY = 110  # 叠加浮岛图标后，标签首行中心落在锚点下方 110px


def _build_section(sec: dict) -> dict:
    """把 chain 展开成带完整字段的节点列表，gate 取链尾关。"""
    nodes: list[dict] = []
    prev_id = 0
    for z, (sid, pos) in enumerate(sec["chain"], start=1):
        meta = STAGE_META[sid]
        nodes.append({
            "stage_id": sid,
            "name": meta["name"],
            "level": 1,
            "kind": meta["kind"],
            "tag": meta["tag"],
            "icon": meta["icon"],
            "icon_size": meta["icon_size"],
            "label_order": meta["label_order"],
            "pos": list(pos),
            "label_dy": LABEL_DY,
            "radius": meta["radius"],
            "z": z,
            "pre_stage_id": prev_id,
            "demo_stars": 0,
            "demo_selected": False,
            "stamina": meta["stamina"],
            "recommend_power": meta["recommend_power"],
        })
        prev_id = sid
    gate = sec["chain"][-1][0]
    return {
        "id": sec["id"],
        "label": sec["label"],
        "name": sec["name"],
        "chapter_id": "ch1",
        "stage_ids": [sid for sid, _ in sec["chain"]],
        "gate_stage_id": gate,
        "nodes": nodes,
    }


# ---------------------------------------------------------------- 布局校验

def _validate(built: list[dict]) -> None:
    errors: list[str] = []
    for s in built:
        nodes = s["nodes"]
        # 边界
        for n in nodes:
            x, y = n["pos"]
            if not (400 < x < 1500 and 250 < y < 900):
                errors.append(f"{s['id']} 节点 {n['stage_id']} 越界 pos={n['pos']}")
        # 两两不重叠
        for i in range(len(nodes)):
            for j in range(i + 1, len(nodes)):
                a, b = nodes[i], nodes[j]
                d = _dist(a["pos"], b["pos"])
                if d < 200.0:
                    errors.append(
                        f"{s['id']} 节点 {a['stage_id']}/{b['stage_id']} 重叠 d={d:.0f}")
        # 引导线可见段
        by_id = {n["stage_id"]: n for n in nodes}
        for n in nodes:
            pre = n["pre_stage_id"]
            if pre <= 0 or pre not in by_id:
                continue
            a, b = by_id[pre], n
            d = _dist(a["pos"], b["pos"])
            visible = d - (a["radius"] + b["radius"])
            if not (24.0 <= visible < 260.0):
                errors.append(
                    f"{s['id']} 引导线 {pre}->{b['stage_id']} 可见段 {visible:.0f} 越界")
    if errors:
        raise SystemExit("[FAIL] 布局校验未通过：\n  " + "\n  ".join(errors))


def _dist(p: list[int], q: list[int]) -> float:
    return ((p[0] - q[0]) ** 2 + (p[1] - q[1]) ** 2) ** 0.5


def main() -> None:
    raw = CFG.read_text(encoding="utf-8")
    data = json.loads(raw)

    built = [_build_section(sec) for sec in SECTIONS]
    _validate(built)

    sm = data.setdefault("adventure", {}).setdefault("select_map", {})
    sm["sections"] = built
    # legacy 镜像：拼平所有小节节点（运行时以 sections 为唯一渲染源）
    sm["nodes"] = [n for s in built for n in s["nodes"]]
    sm["nodes_note"] = (
        "第一章按 3-3-4 拆成 3 个小节，每小节一张独立子地图；"
        "本 nodes 为各小节节点拼平的 legacy 镜像，渲染以 sections 为准。")
    sm["sections_note"] = (
        "小节唯一数据源。gate_stage_id = 该节守关关，通关它即解锁下一小节；"
        "节内 pre_stage_id 为线性链，跨节连线已丢弃。")

    out = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
    CFG.write_text(out, encoding="utf-8")

    total = sum(len(s["nodes"]) for s in built)
    print(f"[ok] sections -> {len(built)} 节 / 共 {total} 关")
    for s in built:
        print(f"     {s['id']} {s['label']}《{s['name']}》 "
              f"stages={s['stage_ids']} gate={s['gate_stage_id']}")
    print(f"     文件 {len(raw.encode('utf-8'))} -> {len(out.encode('utf-8'))} 字节")


if __name__ == "__main__":
    main()
