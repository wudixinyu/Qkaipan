#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""幂等注入：给 select_map.chapter_tabs.items 每一章加 bg 字段（章节大地图底图路径）。

约定与项目其余 apply_*.py 一致：ensure_ascii=False, indent=2，末尾补一个换行。
bg 指向 tools/prep_chapter_bg.py 预处理出的 1920x1080 运行时底图。
"""

import json
import io
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "data" / "game_data.json"

# chapter_id -> 底图（res:// 路径，供 stage_select.gd 运行时 load）
CHAPTER_BG = {
    "ch1": "res://assets/art/bg/bg_ch1.png",
    "ch2": "res://assets/art/bg/bg_ch2.png",
    "ch3": "res://assets/art/bg/bg_ch3.png",
}


def main() -> int:
    with io.open(DATA, encoding="utf-8") as f:
        data = json.load(f)

    items = data["adventure"]["select_map"]["chapter_tabs"]["items"]
    changed = 0
    for it in items:
        cid = it.get("id", "")
        want = CHAPTER_BG.get(cid)
        if want and it.get("bg") != want:
            it["bg"] = want
            changed += 1
            print(f"[apply_chapter_bg] {cid}.bg = {want}")

    if changed == 0:
        print("[apply_chapter_bg] 无变化（bg 已就位），跳过写盘")
        return 0

    with io.open(DATA, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"[apply_chapter_bg] 已注入 {changed} 章 bg 字段 -> {DATA.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
