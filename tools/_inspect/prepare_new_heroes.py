# -*- coding: utf-8 -*-
"""prepare_new_heroes.py —— 新英雄立绘抠图 + 接入

把 ImageGen 生成的四张 RGB 立绘处理成项目口径的透明底贴纸立绘：

  1. 背景抠除：AI 出图是实色/浅色背景（无 alpha），用「亮度 + 彩度」掩膜
     从四周边界洪泛，只吃掉与边界连通的背景；角色本体被轮廓隔断不误伤。
  2. 抗锯齿描边清理：亮且灰的过渡像素做 alpha 衰减（沿项目 clean_char_alpha 思路）。
  3. 裁切到内容框 + 等比缩放到 ~900 高（与现有立绘同口径），居中留边。

用法：
    <venv python> tools/_inspect/prepare_new_heroes.py

映射：
    Q版...少女法师...  -> char_arcane_girl.png      (秘法少女·许知夏)
    Q版...暗夜刺客...  -> char_shadow_assassin.png  (暗夜刺客·影刃)
    Q版...大地守卫...  -> char_earth_guardian.png   (大地守卫·托尔)
    Q版...炎赫骑士...  -> char_flame_knight.png     (炎赫骑士·亚瑟)
"""
import os
from collections import deque

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC_DIR = os.path.join(ROOT, "tools", "_inspect", "gen")
OUT_DIR = os.path.join(ROOT, "assets", "art", "characters")

TARGET_HEIGHT = 900  # 与现有立绘高度同口径
LUMA_MIN = 216       # 背景亮度下限（实测背景 ~250，描边残影 180~200 必须拒之门外）
CHROMA_MAX = 18      # 背景彩度上限（实色背景几乎无色，角色水墨/火焰彩度高，宽安全边）

# (生成文件关键字, 目标文件名)
MAPPING = [
    ("少女法师", "char_arcane_girl.png"),
    ("暗夜刺客", "char_shadow_assassin.png"),
    ("大地守卫", "char_earth_guardian.png"),
    ("炎赫骑士", "char_flame_knight.png"),
]


def flood_from_border(mask: np.ndarray) -> np.ndarray:
    """从四周边界洪泛，返回「与边界连通的区域」（即背景）。"""
    h, w = mask.shape
    visited = np.zeros_like(mask, dtype=bool)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if mask[y, x] and not visited[y, x]:
                visited[y, x] = True
                q.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if mask[y, x] and not visited[y, x]:
                visited[y, x] = True
                q.append((x, y))
    while q:
        x, y = q.popleft()
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dx == 0 and dy == 0:
                    continue
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and mask[ny, nx] and not visited[ny, nx]:
                    visited[ny, nx] = True
                    q.append((nx, ny))
    return visited


def clean(name: str, out_name: str) -> None:
    src = None
    for f in os.listdir(SRC_DIR):
        if f.endswith(".png") and name in f:
            src = os.path.join(SRC_DIR, f)
            break
    if src is None:
        print(f"[skip] 找不到 {name} 的源图")
        return

    im = Image.open(src).convert("RGB")
    arr = np.asarray(im).astype(np.int32)
    r, g, b = arr[..., 0], arr[..., 1], arr[..., 2]
    luma = (r * 299 + g * 587 + b * 114) // 1000
    chroma = np.maximum(np.maximum(r, g), b) - np.minimum(np.minimum(r, g), b)
    fillable = (luma >= LUMA_MIN) & (chroma <= CHROMA_MAX)

    background = flood_from_border(fillable)
    alpha = np.where(background, 0, 255).astype(np.uint8)

    # 抗锯齿：前景边缘 1 环做轻微羽化，避免深色卡底上的白雾
    alpha_img = Image.fromarray(alpha, mode="L")
    alpha_img = alpha_img.filter(ImageFilter.GaussianBlur(0.6))
    alpha = np.asarray(alpha_img)

    rgba = np.dstack([arr[..., 0], arr[..., 1], arr[..., 2], alpha]).astype(np.uint8)
    out = Image.fromarray(rgba, mode="RGBA")

    # 裁到内容框
    ys, xs = np.nonzero(alpha > 20)
    if ys.size == 0:
        print(f"[warn] {name} 抠图后为空，跳过")
        return
    x0, x1, y0, y1 = int(xs.min()), int(xs.max()), int(ys.min()), int(ys.max())
    out = out.crop((x0, y0, x1 + 1, y1 + 1))

    # 等比缩放到目标高度
    h_scale = TARGET_HEIGHT / float(out.height)
    nw = int(round(out.width * h_scale))
    out = out.resize((nw, TARGET_HEIGHT), Image.LANCZOS)

    dest = os.path.join(OUT_DIR, out_name)
    out.save(dest)
    print(f"[ok] {out_name}  <-  {os.path.basename(src)}  ({out.size[0]}x{out.size[1]})")


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    for keyword, out_name in MAPPING:
        clean(keyword, out_name)


if __name__ == "__main__":
    main()
