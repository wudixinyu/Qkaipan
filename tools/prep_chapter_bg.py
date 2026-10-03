#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把三章大地图 AI 底图预处理成 1920x1080 运行时背景。

沿用 prep_stage_select_bg.py 的 cover 规则：保持源图比例铺满 1920x1080，
居中裁掉多余边，再做轻度 USM 找回放大流失的边缘。源图为 ImageGen 产出的
1792x1024（16:9），scale≈1.071、只需上下各裁约 8px。

用法：
    python tools/prep_chapter_bg.py
"""

from pathlib import Path

from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "assets" / "art" / "bg"

BASE = (1920, 1080)
SHARPEN_RADIUS = 2.0
SHARPEN_PERCENT = 55
SHARPEN_THRESHOLD = 3

# chapter_id -> 源图（绝对路径）。用户提供的新三章概念图（.jpg）。
# 文件名前缀即章号：1=云上浮岛 ch1、2=机械迷城 ch2、3=深渊暗界 ch3。
SOURCES = {
    "bg_ch1": Path(r"C:\Users\63446\AppData\Roaming\Qoder\SharedClientCache\cache\images\a8eaff7b\1-482a6916.jpg"),
    "bg_ch2": Path(r"C:\Users\63446\AppData\Roaming\Qoder\SharedClientCache\cache\images\a8eaff7b\2-c2944c36.jpg"),
    "bg_ch3": Path(r"C:\Users\63446\AppData\Roaming\Qoder\SharedClientCache\cache\images\a8eaff7b\3-33ea1e2a.jpg"),
}


def cover_resize(im: Image.Image) -> Image.Image:
    src_w, src_h = im.size
    scale = max(BASE[0] / src_w, BASE[1] / src_h)
    scaled = (round(src_w * scale), round(src_h * scale))
    big = im.resize(scaled, Image.LANCZOS)
    left = (scaled[0] - BASE[0]) // 2
    top = (scaled[1] - BASE[1]) // 2
    out = big.crop((left, top, left + BASE[0], top + BASE[1]))
    return out.filter(ImageFilter.UnsharpMask(
        radius=SHARPEN_RADIUS, percent=SHARPEN_PERCENT, threshold=SHARPEN_THRESHOLD))


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    rc = 0
    for name, src in SOURCES.items():
        if not src.exists():
            print(f"[err] 找不到源图：{src}")
            rc = 1
            continue
        im = Image.open(src).convert("RGB")
        out = cover_resize(im)
        dst = OUT_DIR / f"{name}.png"
        out.save(dst, "PNG", optimize=True)
        print(f"[ok ] {dst.relative_to(ROOT)}  {out.size[0]}x{out.size[1]}  "
              f"{dst.stat().st_size / 1024:.0f} KB  (源 {im.size[0]}x{im.size[1]})")
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
