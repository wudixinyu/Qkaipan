"""clean_char_alpha.py —— 立绘 PNG 的 alpha 清理流水线

背景
----
立绘是 AI 直接生成的"贴纸风"立绘，画面里除了角色本体还画了一条**虚线裁切线**
（die-cut dashed outline），并且原始背景是实色的，所以用亮度/色度掩码 + 边界洪泛
抠图后，会残留两类东西：

  1. 那条虚线 —— 它与角色之间有缝隙，是一堆互不连通的小碎块；
  2. 角色轮廓外侧 1~3px 的抗锯齿浅灰过渡像素 —— 贴到深色卡底上是一圈白雾。

处理
----
  A. **测地重建（geodesic reconstruction）**：以掩码质心为种子，在掩码内部反复膨胀
     到收敛，得到"包含种子的那个连通分量"。虚线碎块因为不连通会被整体丢弃。
     没有 scipy/cv2 也能做——纯 numpy 的 8 邻域位移运算，几百次迭代即可收敛。
  B. **描边清理**：对距离全透明区 RING 步以内、且又亮又灰的像素做颜色渗色 +
     alpha 衰减。角色内部的浅色（骑士盔甲、牧师白袍）离透明区远，不会误伤。

备份放在 assets/art/characters/_orig/，脚本可反复运行。
"""

import os
import sys
import numpy as np
from PIL import Image

CHARS = ["knight", "pyromancer", "ranger", "priest"]
SRC_DIR = "assets/art/characters"
BACKUP_DIR = "assets/art/characters/_orig"

RING = 3            # 描边清理的传呼半径
LUMA_MIN = 175      # 亮于该值
CHROMA_MAX = 45     # 且色度低于该值，才算浅灰描边
MAX_ITER = 4000     # 测地重建迭代上限（收敛即提前退出）


# ------------------------------------------------------------------ 基础算子

def _dilate(mask: np.ndarray) -> np.ndarray:
    """8 邻域膨胀，用切片实现以避免 np.roll 的环绕。"""
    out = mask.copy()
    out[1:, :] |= mask[:-1, :]
    out[:-1, :] |= mask[1:, :]
    out[:, 1:] |= mask[:, :-1]
    out[:, :-1] |= mask[:, 1:]
    out[1:, 1:] |= mask[:-1, :-1]
    out[:-1, :-1] |= mask[1:, 1:]
    out[1:, :-1] |= mask[:-1, 1:]
    out[:-1, 1:] |= mask[1:, :-1]
    return out


def geodesic_reconstruct(mask: np.ndarray, seed: np.ndarray) -> np.ndarray:
    """在 mask 内部从 seed 出发膨胀到收敛，返回 seed 所在的连通分量。"""
    cur = seed & mask
    for i in range(MAX_ITER):
        nxt = _dilate(cur) & mask
        if np.array_equal(nxt, cur):
            return cur
        cur = nxt
    return cur


def largest_component(mask: np.ndarray) -> np.ndarray:
    """取 mask 中最大的连通分量（种子用掩码质心最近的非零像素，最稳）。"""
    ys, xs = np.nonzero(mask)
    if ys.size == 0:
        return mask
    cy, cx = int(ys.mean()), int(xs.mean())
    if not mask[cy, cx]:
        # 质心落在空洞里时，退到"离质心最近的掩码像素"
        d = (ys - cy) ** 2 + (xs - cx) ** 2
        k = int(np.argmin(d))
        cy, cx = int(ys[k]), int(xs[k])
    seed = np.zeros_like(mask)
    seed[cy, cx] = True
    return geodesic_reconstruct(mask, seed)


def luma_chroma(rgb: np.ndarray):
    luma = (rgb[..., 0] * 299 + rgb[..., 1] * 587 + rgb[..., 2] * 114) // 1000
    chroma = (np.abs(rgb[..., 0] - rgb[..., 1])
              + np.abs(rgb[..., 1] - rgb[..., 2])
              + np.abs(rgb[..., 0] - rgb[..., 2]))
    return luma, chroma


def pick_bleed(rgb: np.ndarray, alpha: np.ndarray) -> np.ndarray:
    """3x3 邻域里 alpha 最大的像素的 RGB，用作渗色源。"""
    h, w = alpha.shape
    pa = np.pad(alpha, 1, constant_values=-1)
    prgb = np.pad(rgb, ((1, 1), (1, 1), (0, 0)), constant_values=0)
    best_a = np.full((h, w), -1, dtype=np.int32)
    best_rgb = rgb.copy()
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if dy == 0 and dx == 0:
                continue
            na = pa[1 + dy:1 + dy + h, 1 + dx:1 + dx + w]
            nrgb = prgb[1 + dy:1 + dy + h, 1 + dx:1 + dx + w]
            take = na > best_a
            best_a = np.where(take, na, best_a)
            best_rgb = np.where(take[..., None], nrgb, best_rgb)
    return best_rgb


# ------------------------------------------------------------------ 主流程

def clean(name: str) -> None:
    src = os.path.join(SRC_DIR, f"char_{name}.png")
    bak = os.path.join(BACKUP_DIR, f"char_{name}.png")

    # 首次运行先留备份；之后每次都从备份重跑，保证可重复
    if os.path.exists(bak):
        base = bak
    else:
        os.makedirs(BACKUP_DIR, exist_ok=True)
        Image.open(src).convert("RGBA").save(bak)
        base = src

    img = Image.open(base).convert("RGBA")
    arr = np.asarray(img).astype(np.int32)
    rgb, alpha = arr[..., :3], arr[..., 3]

    # --- A. 只保留角色本体，丢掉虚线裁切线 ---
    mask = alpha >= 8
    body = largest_component(mask)
    dropped = int(mask.sum() - body.sum())
    new_alpha = np.where(body, alpha, 0).astype(np.int32)

    # --- B. 清理轮廓外侧的浅灰抗锯齿描边 ---
    luma, chroma = luma_chroma(rgb)
    reach = _dilate(new_alpha == 0)
    ring = np.zeros_like(reach)
    cur = new_alpha == 0
    for _ in range(RING):
        cur = _dilate(cur)
        ring |= cur
    ring &= new_alpha > 0
    halo = ring & (luma >= LUMA_MIN) & (chroma <= CHROMA_MAX)

    new_rgb = rgb.copy()
    if halo.any():
        bleed = pick_bleed(rgb, new_alpha)
        new_rgb[halo] = bleed[halo]
        new_alpha = new_alpha.astype(np.float32)
        new_alpha[halo] *= 0.55
        new_alpha = np.clip(new_alpha, 0, 255).astype(np.int32)

    out = np.dstack([new_rgb, new_alpha]).astype(np.uint8)
    Image.fromarray(out, "RGBA").save(src)
    print(f"{name:11s} 丢弃虚线碎块 {dropped:>6d}px   清理描边 {int(halo.sum()):>6d}px   "
          f"剩余不透明 {int((new_alpha > 0).sum()):>7d}px")


def main() -> None:
    names = sys.argv[1:] or CHARS
    for nm in names:
        clean(nm)


if __name__ == "__main__":
    main()
