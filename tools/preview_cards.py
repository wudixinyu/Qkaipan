"""卡片视觉预演：把立绘按内腔矩形贴进卡框，检查四档品质叠层是否成立。"""
import json
from pathlib import Path

from PIL import Image

ROOT = Path(r"D:/Godot_v4.7.2-stable_win64.exe/卡片游戏/卡牌大冒险")
OUT = ROOT / "tools" / "_inspect"

report = json.loads((OUT / "punch_report.json").read_text(encoding="utf-8"))

# 与 game_data.json 保持一致的对应关系
PAIRS = [("r", "knight"), ("sr", "ranger"), ("ssr", "pyromancer"), ("ur", "priest")]

CARD_W = 330
GAP = 40
cards = []

for rarity, char in PAIRS:
    fr = Image.open(ROOT / f"assets/art/frames/frame_{rarity}.png").convert("RGBA")
    ch = Image.open(ROOT / f"assets/art/characters/char_{char}.png").convert("RGBA")

    card_h = round(CARD_W / (fr.width / fr.height))
    frame = fr.resize((CARD_W, card_h), Image.LANCZOS)

    inner = report[f"frame_{rarity}"]["inner_rect"]
    ix0, iy0 = round(inner[0] * CARD_W), round(inner[1] * card_h)
    ix1, iy1 = round(inner[2] * CARD_W), round(inner[3] * card_h)
    iw, ih = ix1 - ix0, iy1 - iy0

    # 立绘按宽度贴合内腔，垂直居中（等比，不拉伸）
    scale = iw / ch.width
    ph = max(1, round(ch.height * scale))
    portrait = ch.resize((iw, ph), Image.LANCZOS)

    canvas = Image.new("RGBA", (CARD_W, card_h), (0, 0, 0, 0))
    # 内腔底衬：品质色微光，避免空洞
    tint = {"r": (60, 48, 40), "sr": (26, 62, 74),
            "ssr": (52, 32, 68), "ur": (62, 46, 22)}[rarity]
    bed = Image.new("RGBA", (iw, ih), tint + (255,))
    canvas.paste(bed, (ix0, iy0))
    oy = iy0 + (ih - ph) // 2
    canvas.alpha_composite(portrait, (ix0, max(iy0, oy)))
    # 卡框压在最上层
    canvas.alpha_composite(frame, (0, 0))

    cards.append(canvas)
    print(f"{rarity.upper():>3} card {CARD_W}x{card_h}  inner=({ix0},{iy0},{ix1},{iy1}) {iw}x{ih}")

total_w = CARD_W * len(cards) + GAP * (len(cards) - 1)
max_h = max(c.height for c in cards)
sheet = Image.new("RGBA", (total_w, max_h), (34, 40, 52, 255))
x = 0
for c in cards:
    sheet.alpha_composite(c, (x, (max_h - c.height) // 2))
    x += CARD_W + GAP
sheet.convert("RGB").save(OUT / "preview_cards.png")
print("\n-> tools/_inspect/preview_cards.png")
