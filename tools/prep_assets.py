"""把 AI 生成的占位图处理成可直接用的资源。

- 卡框：洪泛填充挖空内腔 -> 透明；裁到内容边界；输出内腔归一化矩形
- 立绘：洪泛填充抠掉连通白底 -> 透明；裁到内容边界
结果写回原文件，内腔矩形打印出来供 game_data.json 使用。
"""
import json
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(r"D:/Godot_v4.7.2-stable_win64.exe/卡片游戏/卡牌大冒险")
SENTINEL = (255, 0, 255)


def flood_mask(img: Image.Image, seeds, thresh: int) -> Image.Image:
    """从若干种子点洪泛，返回被填充区域的单通道掩膜。"""
    work = img.convert("RGB").copy()
    for s in seeds:
        ImageDraw.floodfill(work, s, SENTINEL, thresh=thresh)
    diff = ImageChops.difference(work, Image.new("RGB", img.size, SENTINEL))
    return diff.convert("L").point(lambda v: 255 if v < 24 else 0)


def punch(img: Image.Image, seeds, thresh: int, feather: float) -> Image.Image:
    """按掩膜把指定区域挖成透明，并做羽化抗锯齿。"""
    mask = flood_mask(img, seeds, thresh)
    if feather > 0:
        mask = mask.filter(ImageFilter.GaussianBlur(feather))
    img = img.convert("RGBA")
    alpha = img.getchannel("A")
    alpha = ImageChops.subtract(alpha, mask)
    img.putalpha(alpha)
    return img


def crop_to_content(img: Image.Image):
    bbox = img.getchannel("A").getbbox()
    if bbox is None:
        return img, (0, 0, img.width, img.height)
    return img.crop(bbox), bbox


def grid_seeds(w: int, h: int):
    """内腔种子：中心 + 中央 30%~70% 的网格，规避装饰把内腔切碎的情况。"""
    pts = []
    for fx in (0.4, 0.5, 0.6):
        for fy in (0.3, 0.45, 0.6, 0.72):
            pts.append((int(w * fx), int(h * fy)))
    return pts


def edge_seeds(w: int, h: int):
    return [(1, 1), (w - 2, 1), (1, h - 2), (w - 2, h - 2),
            (w // 2, 1), (w // 2, h - 2), (1, h // 2), (w - 2, h // 2)]


report = {}

# ---------- 卡框 ----------
for key in ("r", "sr", "ssr", "ur"):
    p = ROOT / "assets/art/frames" / f"frame_{key}.png"
    im = Image.open(p).convert("RGBA")
    seeds = grid_seeds(*im.size)
    cut = punch(im, seeds, thresh=34, feather=1.1)

    # 用挖空前后的 alpha 差集定位内腔
    hole = ImageChops.subtract(im.getchannel("A"), cut.getchannel("A"))
    hb = hole.getbbox()
    cut, box = crop_to_content(cut)
    if hb:
        inner = ((hb[0] - box[0]) / cut.width, (hb[1] - box[1]) / cut.height,
                 (hb[2] - box[0]) / cut.width, (hb[3] - box[1]) / cut.height)
    else:
        inner = (0.1, 0.1, 0.9, 0.9)
    cut.save(p)
    report[f"frame_{key}"] = {
        "size": list(cut.size),
        "inner_rect": [round(v, 4) for v in inner],
        "transparent_px": int(sum(cut.getchannel("A").point(lambda v: 1 if v < 128 else 0)
                                  .get_flattened_data())),
    }
    print(f"frame_{key}: {cut.size}  inner={[round(v,3) for v in inner]}")

# ---------- 立绘 ----------
for key in ("knight", "pyromancer", "ranger", "priest"):
    p = ROOT / "assets/art/characters" / f"char_{key}.png"
    im = Image.open(p).convert("RGBA")
    cut = punch(im, edge_seeds(*im.size), thresh=26, feather=1.4)
    cut, box = crop_to_content(cut)
    cut.save(p)
    report[f"char_{key}"] = {"size": list(cut.size)}
    print(f"char_{key}: {cut.size}")

(ROOT / "tools" / "_inspect" / "punch_report.json").write_text(
    json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
print("\nreport -> tools/_inspect/punch_report.json")
