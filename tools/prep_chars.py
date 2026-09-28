"""立绘抠底（第三轮，正确做法）。

问题：AI 出图自带 alpha，但只在最外圈，主体背后还有一块不透明的浅灰贴纸底，
导致贴进卡框后内腔是一片白色。

做法：构造「可填充」条件掩膜（亮度足够高 + 彩度足够低 = 背景色），
在掩膜上从四周边界洪泛，只吃掉与边界连通的背景区域；
角色自身的白色部位被描边隔断，不会被误伤。之后按 alpha 重新裁到内容框。
"""
import json
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(r"D:/Godot_v4.7.2-stable_win64.exe/卡片游戏/卡牌大冒险")
OUT = ROOT / "tools" / "_inspect"

LUMA_MIN = 196     # 背景亮度下限
CHROMA_MAX = 46    # 背景彩度上限
names = ["knight", "pyromancer", "ranger", "priest"]
report = json.loads((OUT / "punch_report.json").read_text(encoding="utf-8"))

for key in names:
    p = ROOT / "assets/art/characters" / f"char_{key}.png"
    im = Image.open(p).convert("RGBA")
    arr = np.asarray(im).astype(np.int32)
    r, g, b, a = arr[..., 0], arr[..., 1], arr[..., 2], arr[..., 3]

    luma = (r * 299 + g * 587 + b * 114) // 1000
    chroma = np.maximum(np.maximum(r, g), b) - np.minimum(np.minimum(r, g), b)
    fillable = (luma >= LUMA_MIN) & (chroma <= CHROMA_MAX)

    h, w = fillable.shape
    visited = np.zeros_like(fillable)
    q = deque()
    # 四周边界上所有可填充像素作为种子
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

    eaten = int(visited.sum())
    # 掩膜轻微羽化，避免硬锯齿
    m = Image.fromarray((visited * 255).astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(1.2))
    new_a = np.clip(a.astype(np.int16) - np.asarray(m).astype(np.int16), 0, 255).astype(np.uint8)

    out = im.copy()
    out.putalpha(Image.fromarray(new_a, "L"))

    # 按 alpha>32 重新裁到内容
    box = out.getchannel("A").point(lambda v: 255 if v > 32 else 0).getbbox() or (0, 0, w, h)
    out = out.crop(box)
    out.save(p)

    report[f"char_{key}"] = {"size": list(out.size), "bg_removed_px": eaten,
                             "removed_pct": round(eaten / (w * h) * 100, 1)}
    print(f"char_{key}: {w}x{h} -> {out.size}  抠掉背景 {eaten} px ({eaten/(w*h)*100:.1f}%)")

(OUT / "punch_report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
print("done")
