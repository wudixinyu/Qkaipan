#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
把「冒险关卡选择」参考图里的数据写进 data/game_data.json 的 adventure.select_map。

坐标：以 1920x1080 视口为基准的像素锚点（节点锚点 = 该关卡所在浮岛的中心）。
来源图：1024x559 的概念稿。

换算规则必须与 tools/prep_stage_select_bg.py 的 cover 规则一致：
  scale = max(1920/1024, 1080/559) = 1.93202，缩放后 1978x1080，左右各裁 29px。
  所以 screen = 稿坐标 * scale - 裁边量。

幂等：重复执行结果一致（select_map 整段覆盖）。
"""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CFG = ROOT / "data" / "game_data.json"

ICON_GIFT = "res://assets/icons/icon_gift.svg"
ISLE_PLAIN = "res://assets/icons/stage_isle_plain.svg"
ISLE_CASTLE = "res://assets/icons/stage_isle_castle.svg"
ISLE_STORM = "res://assets/icons/stage_isle_storm.svg"

# 概念稿 1024x559 -> 1920x1080（cover，保持比例）
SCALE = max(1920 / 1024, 1080 / 559)
OFF_X = round((1024 * SCALE - 1920) / 2)
OFF_Y = round((559 * SCALE - 1080) / 2)


def px(x: float, y: float) -> list:
    """概念稿坐标 -> 1920x1080 基准像素锚点。"""
    return [int(round(x * SCALE - OFF_X)), int(round(y * SCALE - OFF_Y))]


def dy(v: float) -> int:
    """概念稿纵向距离 -> 屏幕像素距离（横向同理，仅为可读性分两个名字）。"""
    return int(round(v * SCALE))


SELECT_MAP = {
    "title": "冒险关卡选择",
    "chapter_id": "ch1",
    "coord_note": "pos = 节点锚点（该关浮岛的中心），1920x1080 视口像素坐标（左上原点）；z 越大越靠前",
    "anchor_note": "锚点为概念稿实测值经 cover 映射换算；背景 bg_stage_select.png 即该概念稿底图，故锚点与背景浮岛一一对位",
    "label_dy": "标签首行中心相对锚点的纵向偏移（像素），各节点按概念稿实测，故三个值不同",
    "radius": "该关浮岛在背景里的视觉半径（像素）。引导线两端各按这个半径从节点中心收回，"
              "于是只在浮岛之间露出一小段 —— 概念稿里就是这样，不是贯穿全场的连线",
    "icon_note": "icon 为空 = 该关浮岛由背景自带，不再叠加图标（叠了会和背景重复）；"
                 "仅 1004 风暴元素的雷云在背景里不存在，需叠加 stage_isle_storm.svg",
    "enter_button": {"text": "进入关卡", "sub_text": "START LEVEL"},
    "team_panel": {
        "rows": 3,
        "cols": 3,
        "deployed": 3,
        "label": "3x3 3",
        "lineup": ["knight_rock", "pyro_girl", "elf_ranger"],
    },
    "promo_entry": {"id": "promo", "name": "活动", "icon": ICON_GIFT},
    # 关卡节点：stage_id 对应该章的关卡编号；pre_stage_id 即图中发光引导线
    "nodes": [
        {
            "stage_id": 1001,
            "__r": 110,
            # 关卡名以第一章策划表为准：1001 = 初始之地（早前从概念稿误读成「初云之地」）
            "name": "初始之地",
            "level": 1,
            "kind": "battle",
            "tag": "",
            "icon": "",
            "icon_size": 0,
            "label_order": "name_level",
            "pos": px(351, 304),
            "label_dy": dy(29),
            "radius": 95,
            "z": 1,
            "pre_stage_id": 0,
            "demo_stars": 0,
            "demo_selected": False,
        },
        {
            "stage_id": 1003,
            "__r": 122,
            "name": "云端城堡",
            "level": 1,
            "kind": "elite",
            "tag": "精",
            "icon": "",
            "icon_size": 0,
            "label_order": "name_level",
            "pos": px(500, 207),
            "label_dy": dy(51),
            "radius": 100,
            "z": 2,
            "pre_stage_id": 1001,
            "demo_stars": 0,
            "demo_selected": True,
        },
        {
            "stage_id": 1004,
            "__r": 90,
            "name": "风暴元素",
            "level": 1,
            "kind": "battle",
            "tag": "",
            "icon": ISLE_STORM,
            "icon_size": 208,
            "label_order": "level_name",
            "pos": px(640, 333),
            "label_dy": dy(57),
            "radius": 90,
            "z": 3,
            "pre_stage_id": 1003,
            "demo_stars": 0,
            "demo_selected": False,
        },
    ],
    # 非玩法的装饰浮岛：仅作选关页布景参照，不进战斗逻辑
    # 注意：选关页背景 bg_stage_select.png 自带完整浮岛美术，装饰岛暂不渲染，
    #       这批锚点保留作布局参照（换背景时可随时启用）。
    "decor_islands": [
        {"id": "island_castle_far", "pos": px(281, 128), "scale": 1.0, "icon": ISLE_CASTLE},
        {"id": "island_forest_left", "pos": px(105, 110), "scale": 0.9, "icon": ISLE_PLAIN},
        {"id": "island_tower_top", "pos": px(800, 92), "scale": 0.8, "icon": ISLE_CASTLE},
        {"id": "island_farm_right", "pos": px(893, 300), "scale": 0.9, "icon": ISLE_PLAIN},
        {"id": "island_cabin_bottom", "pos": px(868, 487), "scale": 1.0, "icon": ISLE_PLAIN},
        {"id": "island_ruins_left", "pos": px(272, 380), "scale": 0.8, "icon": ISLE_PLAIN},
    ],
}


def main() -> None:
    raw = CFG.read_text(encoding="utf-8")
    data = json.loads(raw)

    adv = data.setdefault("adventure", {})
    adv["select_map"] = SELECT_MAP

    out = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
    CFG.write_text(out, encoding="utf-8")

    nodes = SELECT_MAP["nodes"]
    print(f"[ok] adventure.select_map 已写入 {CFG.relative_to(ROOT)}")
    for n in nodes:
        print(f"     #{n['stage_id']} {n['name']:<6} lv{n['level']} stars={n['demo_stars']} "
              f"kind={n['kind']:<6} pos={n['pos']} pre={n['pre_stage_id']}")
    print(f"     节点 {len(nodes)} 个 / 装饰岛 {len(SELECT_MAP['decor_islands'])} 个 / "
          f"队伍 {SELECT_MAP['team_panel']['deployed']} 人")
    print(f"     文件 {len(raw.encode('utf-8'))} -> {len(out.encode('utf-8'))} 字节")


if __name__ == "__main__":
    main()
