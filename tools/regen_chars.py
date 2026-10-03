"""regen_chars.py —— 卡片人物立绘全量重绘的入库流水线（生成 → 抠底 → 覆盖 assets）。

输入：tools/_inspect/gen_new/char_<key>.png   （ImageGen 出的原图，纯白底 RGB）
输出：assets/art/characters/char_<key>.png   （透明底，裁到内容框）
备份：assets/art/characters/_orig_v1/        （首次覆盖前把旧图挪一份，可反复重跑）

四步，沿用项目里已验证的两套算法，并针对本批图补了两处修正：
  1. 洪泛抠底（prep_chars.py）：亮度高 + 彩度低 = 背景色，只吃与四周边界连通的部分，
     角色内部的白袍/白银甲被描边隔断，不会被误伤。
  2. 碎块过滤：只丢极小的噪点分量。**不能只留最大连通分量**——浮石、光环、星芒
     这类特效本来就是与本体断开的小分量，按最大分量裁会把它们整批吃掉（实测大地守卫
     被吃掉 8.4 万 px）。
  3. 封闭白底清除：洪泛只能从边界进入，被弓臂/弓弦这类描线围死的白色空洞逃得掉。
     判据用「分量尺寸 + 边界暗墨占比」：漏抠的背景是被粗墨线包住的，边界暗墨占比高；
     白袍、银甲、肤色高光贴在彩色本体上，该占比很低。两者实测能拉开（0.24 vs ≤0.13）。
     每删一块都打印，避免误伤合法白色设计。
  4. 描边清理（clean_char_alpha.py）+ 按 alpha 裁到内容框，写回 assets。

元数据单独写 regen_report.json，不碰 punch_report.json（那里存的是卡框 inner_rect，
preview_cards.py 还要读）。
"""
import json
import shutil
import sys
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(r"D:/Godot_v4.7.2-stable_win64.exe/卡片游戏/卡牌大冒险")
GEN = ROOT / "tools" / "_inspect" / "gen_new"
OUT = ROOT / "tools" / "_inspect"
DST = ROOT / "assets" / "art" / "characters"
BAK = DST / "_orig_v1"

KEYS = ["arcane_girl", "earth_guardian", "flame_knight", "knight",
        "priest", "pyromancer", "ranger", "shadow_assassin"]

LUMA_MIN = 196      # 背景亮度下限
CHROMA_MAX = 46     # 背景彩度上限
RING = 3            # 描边清理半径
LUMA_DEFOCUS_MIN = 175
CHROMA_DEFOCUS_MAX = 45

MIN_COMP_PCT = 0.05   # 小于该占比的不透明分量当噪点丢掉（保留浮石/光环等特效碎块）
WHITE_LUMA = 225      # 近白判据：亮度下限
WHITE_CHROMA = 22     # 近白判据：彩度上限
DARK_LUMA = 120       # 暗墨判据：边界上算作描边的亮度上限
TRAP_MIN_PCT = 0.30   # 封闭白底：分量尺寸下限（占全图百分比）
TRAP_DARK = 1.01      # 封闭白底：边界暗墨占比下限；>1 即关闭该规则（见下方说明）

# 为什么默认关掉「封闭白底清除」：试跑数据表明它无法区分漏抠背景与合法白色设计。
# 白布/白盾面本身也用粗墨线勾边，边界暗墨占比同样高达 0.22~0.32，会被连带误删
# （秘法少女 3.8 万 px 白袍、暗夜刺客 1.7 万 px）。正确做法是在出图阶段就不画
# 白色细线（弓弦类），已对 char_ranger 重生成解决；确实残留时用 --trap 单张复核。


# ------------------------------------------------------------- 基础算子

def _dilate(mask):
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


def components(mask):
    """4 邻域连通分量标号，返回 (label 数组, 分量个数)。纯 numpy + deque，不引 scipy。"""
    lab = np.zeros(mask.shape, np.int32)
    n = 0
    h, w = mask.shape
    ys, xs = np.nonzero(mask)
    for y0, x0 in zip(ys, xs):
        if lab[y0, x0]:
            continue
        n += 1
        lab[y0, x0] = n
        q = deque([(y0, x0)])
        while q:
            y, x = q.popleft()
            for ny, nx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
                if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not lab[ny, nx]:
                    lab[ny, nx] = n
                    q.append((ny, nx))
    return lab, n


def pick_bleed(rgb, alpha):
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


# ------------------------------------------------------------- 单张处理

def flood_bg(rgb):
    """从四周边界洪泛「又亮又灰」的像素，返回与边界连通的背景掩膜。"""
    luma = (rgb[..., 0] * 299 + rgb[..., 1] * 587 + rgb[..., 2] * 114) // 1000
    chroma = (np.abs(rgb[..., 0] - rgb[..., 1])
              + np.abs(rgb[..., 1] - rgb[..., 2])
              + np.abs(rgb[..., 0] - rgb[..., 2])) // 2
    fillable = (luma >= LUMA_MIN) & (chroma <= CHROMA_MAX)

    h, w = fillable.shape
    visited = np.zeros_like(fillable)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if fillable[y, x] and not visited[y, x]:
                visited[y, x] = True
                q.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if fillable[y, x] and not visited[y, x]:
                visited[y, x] = True
                q.append((x, y))
    while q:
        x, y = q.popleft()
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < w and 0 <= ny < h and fillable[ny, nx] and not visited[ny, nx]:
                visited[ny, nx] = True
                q.append((nx, ny))
    return visited


def regen(key):
    src = GEN / f"char_{key}.png"
    dst = DST / f"char_{key}.png"

    # 覆盖前留一份旧图备份（只做一次，之后重跑始终从生成图出发）
    if dst.exists():
        BAK.mkdir(parents=True, exist_ok=True)
        if not (BAK / dst.name).exists():
            shutil.copyfile(dst, BAK / dst.name)

    im = Image.open(src).convert("RGB")
    rgb = np.asarray(im).astype(np.int32)
    h, w = rgb.shape[:2]

    # 1. 洪泛抠底（掩膜轻微羽化，避免硬锯齿）
    bg = flood_bg(rgb)
    m = Image.fromarray((bg * 255).astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(1.2))
    alpha = np.clip(255 - np.asarray(m).astype(np.int32), 0, 255)

    luma = (rgb[..., 0] * 299 + rgb[..., 1] * 587 + rgb[..., 2] * 114) // 1000
    chroma = np.maximum(np.maximum(rgb[..., 0], rgb[..., 1]), rgb[..., 2]) \
        - np.minimum(np.minimum(rgb[..., 0], rgb[..., 1]), rgb[..., 2])

    # 2. 碎块过滤：只丢极小噪点，保留浮石/光环等断开的特效分量
    lab, n = components(alpha >= 8)
    sizes = np.bincount(lab.ravel())
    keep = sizes >= alpha.shape[0] * alpha.shape[1] * MIN_COMP_PCT / 100.0
    keep[0] = True
    noise = int(((~keep)[lab]).sum())
    alpha = np.where(keep[lab], alpha, 0)

    # 3. 封闭白底清除：洪泛进不来的、被粗墨线围住的近白空洞
    body = alpha > 32
    near_white = body & (luma >= WHITE_LUMA) & (chroma <= WHITE_CHROMA)
    dark = body & (luma < DARK_LUMA)
    wlab, wn = components(near_white)
    wsizes = np.bincount(wlab.ravel())
    trapped = np.zeros((h, w), bool)
    hits = []
    for i in range(1, wn + 1):
        sz = int(wsizes[i])
        if sz < h * w * TRAP_MIN_PCT / 100.0:
            continue
        comp = wlab == i
        edge = _dilate(comp) & ~comp
        e = int(edge.sum())
        ratio = int((edge & dark).sum()) / max(1, e)
        if ratio >= TRAP_DARK:
            trapped |= comp
            hits.append((sz, round(ratio, 2)))
    if trapped.any():
        alpha = np.where(trapped, 0, alpha)

    # 4. 清理轮廓外侧的浅灰抗锯齿描边
    ring = np.zeros((h, w), dtype=bool)
    cur = alpha == 0
    for _ in range(RING):
        cur = _dilate(cur)
        ring |= cur
    halo = ring & (alpha > 0) & (luma >= LUMA_DEFOCUS_MIN) & (chroma <= CHROMA_DEFOCUS_MAX)
    out_rgb = rgb.copy()
    if halo.any():
        bleed = pick_bleed(rgb, alpha)
        out_rgb[halo] = bleed[halo]
        alpha = alpha.astype(np.float32)
        alpha[halo] *= 0.55
        alpha = np.clip(alpha, 0, 255).astype(np.int32)

    # 5. 裁到内容框后写回
    out = Image.fromarray(np.dstack([out_rgb, alpha]).astype(np.uint8), "RGBA")
    box = out.getchannel("A").point(lambda v: 255 if v > 32 else 0).getbbox() or (0, 0, w, h)
    out = out.crop(box)
    out.save(dst)

    eaten = int(bg.sum())
    trap_px = sum(s for s, _ in hits)
    print(f"char_{key:16s} {w}x{h} -> {out.size[0]}x{out.size[1]}  "
          f"背景 {eaten / (w * h) * 100:4.1f}%  丢噪点 {noise:>6d}px  "
          f"清封闭白底 {trap_px:>6d}px{'' if not hits else ' ' + str(hits)}  "
          f"描边 {int(halo.sum()):>6d}px")
    return {"size": list(out.size), "source": [w, h], "bg_pct": round(eaten / (w * h) * 100, 1),
            "noise_px": noise, "trapped_white": [{"size": s, "dark_ratio": r} for s, r in hits],
            "defocus_px": int(halo.sum())}


def main():
    # --trap 开启封闭白底清除（阈值放回 0.20），用于单张复核，默认关闭
    global TRAP_DARK
    if "--trap" in sys.argv[1:]:
        TRAP_DARK = 0.20
        print("[trap] 封闭白底清除已开启，结果需逐张目视复核")
    keys = [a for a in sys.argv[1:] if not a.startswith("--")] or KEYS
    report = {}
    for key in keys:
        report[f"char_{key}"] = regen(key)
    prev = {}
    rp = OUT / "regen_report.json"
    if rp.exists():
        prev = json.loads(rp.read_text(encoding="utf-8"))
    prev.update(report)
    rp.write_text(json.dumps(prev, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"done -> assets/art/characters/  ({len(keys)} 张)  report: tools/_inspect/regen_report.json")


if __name__ == "__main__":
    main()
