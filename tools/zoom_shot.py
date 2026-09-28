import os
from PIL import Image

im = Image.open("shots/main_menu.png").convert("RGB")
out = "tools/_inspect"
os.makedirs(out, exist_ok=True)

# 真实像素坐标（原图 1920x1080）
regions = {
    "zoom_statband": (320, 700, 1680, 850),   # 四张卡的名牌+三围条横带
    "zoom_r_card":   (330, 340, 815, 920),    # R 卡整张（最左，被 SSR 压住）
    "zoom_ur_card":  (1320, 350, 1640, 895),  # UR 卡整张（最右）
    "zoom_ssr_card": (670, 200, 1075, 910),   # SSR 卡整张（最高，未被压）
}
for name, box in regions.items():
    crop = im.crop(box)
    s = 2 if crop.width > 400 else 3
    crop = crop.resize((crop.width * s, crop.height * s), Image.LANCZOS)
    p = os.path.join(out, name + ".png")
    crop.save(p)
    print("saved", p, crop.size)
