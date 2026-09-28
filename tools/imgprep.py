"""素材预处理：裁掉背景图水印、放大参考图卡牌区、生成卡框拼版。"""
import sys
from pathlib import Path
from PIL import Image

ROOT = Path(r"D:/Godot_v4.7.2-stable_win64.exe/卡片游戏/卡牌大冒险")
REF = Path(r"C:/Users/63446/.workbuddy/clipboard-images/clipboard-2026-09-27T07-03-19-112Z-e0d21a33.jpg")
OUT = ROOT / "tools" / "_inspect"

cmd = sys.argv[1] if len(sys.argv) > 1 else "all"
OUT.mkdir(parents=True, exist_ok=True)

if cmd in ("all", "cropbg"):
    src = ROOT / "assets/art/bg/bg_islands.png"
    im = Image.open(src)
    w, h = im.size
    print(f"bg original: {w}x{h}")
    # 水印位于右下角，裁掉底部约 9% 高度
    cut = int(h * 0.092)
    im2 = im.crop((0, 0, w, h - cut))
    im2.save(src)
    print(f"bg cropped -> {im2.size}  (removed bottom {cut}px)")

if cmd in ("all", "ref"):
    im = Image.open(REF)
    w, h = im.size
    print(f"reference: {w}x{h}")
    # 卡牌区
    box = (int(w * 0.27), int(h * 0.36), int(w * 0.72), int(h * 0.76))
    im.crop(box).resize(((box[2] - box[0]) * 3, (box[3] - box[1]) * 3), Image.LANCZOS) \
      .save(OUT / "ref_cards_zoom.png")
    # 顶部资源条
    im.crop((0, 0, int(w * 0.30), int(h * 0.14))).resize((int(w * 0.30) * 4, int(h * 0.14) * 4), Image.LANCZOS) \
      .save(OUT / "ref_topleft_zoom.png")
    # 底部按钮 + 队伍预览
    im.crop((int(w * 0.36), int(h * 0.70), int(w * 0.66), int(h * 0.98))) \
      .resize((int(w * 0.30) * 4, int(h * 0.28) * 4), Image.LANCZOS) \
      .save(OUT / "ref_bottom_zoom.png")
    print("ref crops written")

if cmd in ("all", "sheet"):
    files = [("R", "frame_r.png"), ("SR", "frame_sr.png"),
             ("SSR", "frame_ssr.png"), ("UR", "frame_ur.png")]
    cell = (300, 450)
    sheet = Image.new("RGBA", (cell[0] * 4, cell[1]), (40, 46, 58, 255))
    for i, (_, fn) in enumerate(files):
        im = Image.open(ROOT / "assets/art/frames" / fn).convert("RGBA")
        im.thumbnail(cell, Image.LANCZOS)
        sheet.paste(im, (i * cell[0] + (cell[0] - im.width) // 2,
                         (cell[1] - im.height) // 2), im)
    sheet.convert("RGB").save(OUT / "sheet_frames.png")
    print("frame sheet written")

    chars = ["char_knight.png", "char_pyromancer.png", "char_ranger.png", "char_priest.png"]
    c2 = (260, 260)
    sh2 = Image.new("RGBA", (c2[0] * 4, c2[1]), (40, 46, 58, 255))
    for i, fn in enumerate(chars):
        im = Image.open(ROOT / "assets/art/characters" / fn).convert("RGBA")
        im.thumbnail(c2, Image.LANCZOS)
        sh2.paste(im, (i * c2[0] + (c2[0] - im.width) // 2,
                       (c2[1] - im.height) // 2), im)
    sh2.convert("RGB").save(OUT / "sheet_chars.png")
    print("char sheet written")
