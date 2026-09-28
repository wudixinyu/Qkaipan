import os
from PIL import Image

im = Image.open("shots/main_menu.png").convert("RGB")
out = "tools/_inspect"
os.makedirs(out, exist_ok=True)

regions = {
    "z_r_stats":    (350, 755, 680, 815, 5),   # R 卡三围条（高倍）
    "z_ssr_stats":  (740, 715, 1080, 775, 5),  # SSR 卡三围条（高倍）
    "z_ur_stats":   (1350, 745, 1660, 805, 5), # UR 卡三围条（高倍）
    "z_r_name":     (355, 700, 660, 790, 5),   # R 卡名牌+三围
}
for name, (x0, y0, x1, y1, s) in regions.items():
    crop = im.crop((x0, y0, x1, y1))
    crop = crop.resize((crop.width * s, crop.height * s), Image.NEAREST)
    p = os.path.join(out, name + ".png")
    crop.save(p)
    print("saved", p, crop.size)
