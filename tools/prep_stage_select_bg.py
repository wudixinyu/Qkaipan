#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
把「冒险关卡选择」的原始底图（概念稿 1024x559）预处理成 1920x1080 的运行时背景。

为什么离线放大而不是丢给 Godot 运行时缩放：
  1. 运行时是双线性过滤，1024 -> 1978 的放大会明显发糊；
     LANCZOS + 轻度 USM 的观感明显更好。
  2. 预处理成 1920x1080 后运行时 1:1 贴图，没有缩放开销，
     配置里的锚点也就能和屏幕像素直接对齐，不用在心算里绕缩放系数。

裁剪规则（cover）：保持 1024x559 的原始比例铺满 1920x1080，
  取 scale = max(1920/1024, 1080/559) = 1.93202，
  缩放后 1978x1080，左右各裁 29px 到 1920x1080。
  这条规则必须与 tools/_inspect/apply_adventure_map.py 里的映射保持一致。

用法：
    python tools/prep_stage_select_bg.py [源图路径]

不带参数时使用下方 DEFAULT_SRC。
"""

import sys
from pathlib import Path

from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "art" / "bg" / "bg_stage_select.png"

DEFAULT_SRC = Path.home() / ".workbuddy" / "clipboard-images" \
    / "clipboard-2026-09-27T08-56-09-481Z-3bcbba2f.png"

BASE = (1920, 1080)          # 项目目标视口
SRC_SIZE = (1024, 559)       # 概念稿原始尺寸，用于校验源图没被换错
SHARPEN_RADIUS = 2.0         # USM 半径：2px 足以找回放大后流失的边缘
SHARPEN_PERCENT = 62         # USM 强度：再高会在云层渐变上起噪点
SHARPEN_THRESHOLD = 3        # 只锐化明显边缘，避免把 JPEG 噪点也放大


def cover_plan(src_w: int, src_h: int, dst_w: int, dst_h: int) -> dict:
    """算出 cover 铺满所需的缩放与裁剪量。"""
    scale = max(dst_w / src_w, dst_h / src_h)
    scaled = (round(src_w * scale), round(src_h * scale))
    return {
        "scale": scale,
        "scaled": scaled,
        "left": (scaled[0] - dst_w) // 2,
        "top": (scaled[1] - dst_h) // 2,
        "crop": (dst_w, dst_h),
    }


def main() -> int:
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_SRC
    if not src.exists():
        print(f"[err] 找不到源图：{src}")
        return 1

    im = Image.open(src).convert("RGB")
    print(f"[src] {src.name}  {im.size[0]}x{im.size[1]}")
    if im.size != SRC_SIZE:
        print(f"[warn] 源图尺寸 {im.size} 与预期 {SRC_SIZE} 不符 —— "
              f"锚点映射仍按 {SRC_SIZE} 概念稿坐标系推算，请确认换图是有意为之。")

    plan = cover_plan(im.size[0], im.size[1], *BASE)
    print(f"[map] scale={plan['scale']:.5f}  缩放后={plan['scaled']}  "
          f"裁掉 left={plan['left']} top={plan['top']}")

    big = im.resize(plan["scaled"], Image.LANCZOS)
    out = big.crop((plan["left"], plan["top"],
                    plan["left"] + BASE[0], plan["top"] + BASE[1]))
    out = out.filter(ImageFilter.UnsharpMask(
        radius=SHARPEN_RADIUS, percent=SHARPEN_PERCENT, threshold=SHARPEN_THRESHOLD))

    OUT.parent.mkdir(parents=True, exist_ok=True)
    out.save(OUT, "PNG", optimize=True)
    print(f"[ok ] {OUT.relative_to(ROOT)}  {out.size[0]}x{out.size[1]}  "
          f"{OUT.stat().st_size / 1024:.0f} KB")

    # 打印锚点换算表，方便和 apply_adventure_map.py 的结果对拍
    def to_screen(x: float, y: float) -> tuple:
        return (round(x * plan["scale"] - plan["left"]),
                round(y * plan["scale"] - plan["top"]))

    print("[锚点] 概念稿坐标 -> 屏幕像素")
    for name, pt in [("1001 初始之地", (351, 304)),
                     ("1003 云端城堡", (500, 207)),
                     ("1004 风暴元素", (640, 333)),
                     ("队伍面板中心", (513, 437)),
                     ("进入按钮中心", (513, 510))]:
        print(f"       {name:<12} {pt} -> {to_screen(*pt)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
