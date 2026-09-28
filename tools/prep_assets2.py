"""第二轮素材预处理（修正版）。

发现：
- 立绘本身就是带 alpha 的透明底，问题只是最外圈 1px 不透明描边撑满了裁剪框
- 卡框内腔已挖通，但外部白底仍不透明，需要一并挖掉再裁到边框

处理：
- 卡框：内腔(中心网格种子) + 外部(边缘种子) 一起挖 -> 裁到边框内容
- 立绘：清掉最外 3px -> 按 alpha>32 裁到内容
输出每张卡框的内腔归一化矩形，供卡牌控件放置立绘。
"""
import json
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(r"D:/Godot_v4.7.2-stable_win64.exe/卡片游戏/卡牌大冒险")
OUT = ROOT / "tools" / "_inspect"
SENTINEL = (255, 0, 255)


def make_mask(img, seeds, thresh):
    work = img.convert("RGB").copy()
    for s in seeds:
        ImageDraw.floodfill(work, s, SENTINEL, thresh=thresh)
    diff = ImageChops.difference(work, Image.new("RGB", img.size, SENTINEL))
    return diff.convert("L").point(lambda v: 255 if v < 24 else 0)


def punch(img, seeds, thresh, feather):
    mask = make_mask(img, seeds, thresh)
    if feather > 0:
        mask = mask.filter(ImageFilter.GaussianBlur(feather))
    out = img.convert("RGBA")
    out.putalpha(ImageChops.subtract(out.getchannel("A"), mask))
    return out, mask


def bbox_above(img, cutoff=32):
    """按 alpha 阈值求内容框，忽略极淡的辉光。"""
    a = img.getchannel("A").point(lambda v: 255 if v > cutoff else 0)
    return a.getbbox()


report = {}

for key in ("r", "sr", "ssr", "ur"):
    p = ROOT / "assets/art/frames" / f"frame_{key}.png"
    im = Image.open(p).convert("RGBA")
    w, h = im.size
    inner_seeds = [(int(w * fx), int(h * fy))
                   for fx in (0.4, 0.5, 0.6) for fy in (0.28, 0.45, 0.62, 0.75)]
    outer_seeds = [(1, 1), (w - 2, 1), (1, h - 2), (w - 2, h - 2),
                   (w // 2, 1), (w // 2, h - 2), (1, h // 2), (w - 2, h // 2)]

    # 内腔和外部分别取掩膜，内腔矩形要在裁切前算出来
    inner_mask = make_mask(im, inner_seeds, 34)
    outer_mask = make_mask(im, outer_seeds, 34)
    combined = ImageChops.lighter(inner_mask, outer_mask)

    out = im.copy()
    soft = combined.filter(ImageFilter.GaussianBlur(1.1))
    out.putalpha(ImageChops.subtract(out.getchannel("A"), soft))

    hb = inner_mask.filter(ImageFilter.GaussianBlur(1)).point(lambda v: 255 if v > 128 else 0).getbbox()
    box = bbox_above(out, 32) or (0, 0, w, h)
    out = out.crop(box)
    if hb:
        # 内腔是否需要下移（UR 顶部有皇冠装饰，开口不在正中）
        inner = [(hb[0] - box[0]) / out.width, (hb[1] - box[1]) / out.height,
                 (hb[2] - box[0]) / out.width, (hb[3] - box[1]) / out.height]
    else:
        inner = [0.12, 0.12, 0.88, 0.88]
    out.save(p)
    report[f"frame_{key}"] = {"size": list(out.size),
                              "inner_rect": [round(v, 4) for v in inner]}
    print(f"frame_{key}: {out.size} ratio={out.width/out.height:.3f} "
          f"inner={[round(v, 3) for v in inner]}")

for key in ("knight", "pyromancer", "ranger", "priest"):
    p = ROOT / "assets/art/characters" / f"char_{key}.png"
    im = Image.open(p).convert("RGBA")
    w, h = im.size
    # 清掉最外圈不透明描边
    ed = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(ed)
    d.rectangle([0, 0, w - 1, 2], fill=255)
    d.rectangle([0, h - 3, w - 1, h - 1], fill=255)
    d.rectangle([0, 0, 2, h - 1], fill=255)
    d.rectangle([w - 3, 0, w - 1, h - 1], fill=255)
    im.putalpha(ImageChops.subtract(im.getchannel("A"), ed))
    box = bbox_above(im, 32) or (0, 0, w, h)
    im = im.crop(box)
    im.save(p)
    report[f"char_{key}"] = {"size": list(im.size)}
    print(f"char_{key}: {im.size} ratio={im.width/im.height:.3f}")

(OUT / "punch_report.json").write_text(
    json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
print("\n-> tools/_inspect/punch_report.json")
