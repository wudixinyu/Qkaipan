"""card_fit_check.py —— 按 card_view.gd 的真实布局公式校验新立绘套框效果。

preview_cards.py 是"按宽贴合"，而游戏里 _layout_portrait() 走的是：
    fit    = min(holder.w / tex.w, holder.h / tex.h) * PORTRAIT_ZOOM
    x      = (holder.w - s.x) / 2                        # 水平居中
    y      = holder.h - s.y + holder.h * PORTRAIT_BOTTOM_BIAS
    clip_contents = true                                 # 超出内腔的部分裁掉

立绘换图后宽高比会变（本批从 ~0.91 变成 ~0.79），必须确认：
  1. 等比缩放，不拉伸变形；
  2. 头部不被顶出内腔、脚不被裁掉太多；
  3. 四档卡框都成立。
所以这里复刻上面四步 + 裁切，输出对照图，而不是用另一套近似逻辑。
"""
import json
from pathlib import Path

from PIL import Image

ROOT = Path(r"D:/Godot_v4.7.2-stable_win64.exe/卡片游戏/卡牌大冒险")
OUT = ROOT / "tools" / "_inspect"

PORTRAIT_ZOOM = 1.10
PORTRAIT_BOTTOM_BIAS = 0.03

CARD_W = 330
GAP = 26

report = json.loads((OUT / "punch_report.json").read_text(encoding="utf-8"))
game = json.loads((ROOT / "data" / "game_data.json").read_text(encoding="utf-8"))

# 每张立绘取一个真实使用者，卡框按该角色的品质走
by_portrait = {}
for c in game["characters"]:
    key = c["portrait"].split("/")[-1]
    by_portrait.setdefault(key, c)

keys = sorted(by_portrait)
cards = []
metrics = []

for key in keys:
    owner = by_portrait[key]
    rarity = owner["rarity"].lower()
    fr = Image.open(ROOT / f"assets/art/frames/frame_{rarity}.png").convert("RGBA")
    ch = Image.open(ROOT / f"assets/art/characters/{key}").convert("RGBA")

    card_h = round(CARD_W / (fr.width / fr.height))
    frame = fr.resize((CARD_W, card_h), Image.LANCZOS)

    inner = report[f"frame_{rarity}"]["inner_rect"]
    ix0, iy0 = round(inner[0] * CARD_W), round(inner[1] * card_h)
    ix1, iy1 = round(inner[2] * CARD_W), round(inner[3] * card_h)
    hw, hh = ix1 - ix0, iy1 - iy0

    # --- card_view.gd: _layout_portrait ---
    tw, th = ch.size
    fit = min(hw / tw, hh / th) * PORTRAIT_ZOOM
    sw, sh = max(1, round(tw * fit)), max(1, round(th * fit))
    px = (hw - sw) // 2
    py = hh - sh + hh * PORTRAIT_BOTTOM_BIAS

    portrait = ch.resize((sw, sh), Image.LANCZOS)

    canvas = Image.new("RGBA", (CARD_W, card_h), (0, 0, 0, 0))
    tint = {"r": (60, 48, 40), "sr": (26, 62, 74),
            "ssr": (52, 32, 68), "ur": (62, 46, 22)}[rarity]
    canvas.paste(Image.new("RGBA", (hw, hh), tint + (255,)), (ix0, iy0))

    # clip_contents：把立绘裁到内腔矩形内再贴
    clip = Image.new("RGBA", (hw, hh), (0, 0, 0, 0))
    clip.paste(portrait, (px, int(round(py))))
    canvas.alpha_composite(clip, (ix0, iy0))
    canvas.alpha_composite(frame, (0, 0))
    cards.append(canvas)

    metrics.append({
        "portrait": key, "who": owner["name"], "rarity": rarity,
        "aspect": round(tw / th, 3),
        "fit": round(fit, 4),
        "overflow_x": max(0, -px), "overflow_x_r": round(max(0, -px) / hw, 3),
        "head_gap": round(int(round(py)) / hh, 3),       # 顶部留白，负数=顶出内腔
        "foot_cut": round(max(0, int(round(py)) + sh - hh) / hh, 3),
    })

max_h = max(c.height for c in cards)
cols = 4
rows = (len(cards) + cols - 1) // cols
pad = GAP
sheet = Image.new("RGBA", (cols * (CARD_W + pad) + pad, rows * (max_h + pad) + pad),
                  (34, 40, 52, 255))
for i, c in enumerate(cards):
    x = pad + (i % cols) * (CARD_W + pad)
    y = pad + (i // cols) * (max_h + pad)
    sheet.alpha_composite(c, (x, y))
sheet.save(OUT / "card_fit_check.png")

print(f"{'portrait':28s} {'who':8s} rar  aspect   top%  footCut%  overflowX%")
for m in metrics:
    print(f"{m['portrait']:28s} {m['who']:8s} {m['rarity']:3s} "
          f"{m['aspect']:6.3f}  {m['head_gap']:6.3f}  {m['foot_cut']:6.3f}  {m['overflow_x_r']:6.3f}")
print("\n-> tools/_inspect/card_fit_check.png")
