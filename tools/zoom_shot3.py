import os
from PIL import Image
im = Image.open("shots/main_menu.png").convert("RGB")
out = "tools/_inspect"; os.makedirs(out, exist_ok=True)
# 按 diag_fan 报出的各卡三围条全局矩形取景，统一 4 倍 NEAREST 放大
regions = {
    "n_r_stats":  (330, 735, 620, 800),
    "n_ssr_stats":(660, 650, 950, 715),
    "n_sr_stats": (990, 695, 1280, 760),
    "n_ur_stats": (1340, 690, 1580, 755),
}
for name, box in regions.items():
    c = im.crop(box)
    c = c.resize((c.width*4, c.height*4), Image.NEAREST)
    p = os.path.join(out, name+".png"); c.save(p); print("saved", p, c.size)
