#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""make_monsters.py —— 生成第一章 14 只怪物的矢量图标

用法：
    python tools/make_monsters.py            # 写出 assets/icons/monsters/*.svg
    python tools/make_monsters.py --check    # 只校验文件是否齐全

为什么是手写 SVG 而不是 AI 出图：
  1. 数量少（14 只）+ 造型简单（Q 版扁平剪影），脚本参数化生成比重绘快得多；
  2. 同一套轮廓/描边/投影规范，14 只放在同一战场里不会互相打架；
  3. 纯几何形状，没有抠图残留问题，改颜色/改大小只需改一个参数重跑；
  4. 与项目既有的 stage_isle_*.svg 手写图标同一路数。

导入约定：project.godot 里 importer_defaults.svg.scale = 3.0，
  所以 200x200 的 viewBox 会导入成 600x600 纹理，战场里按 150px 显示正好清晰。

ThorVG 限制（踩过的坑）：
  - 不支持 fill-rule="evenodd" —— 全是实心形状，不需要；
  - 不用 filter / mask / clipPath —— 投影用椭圆代替；
  - 不用 <use> / <defs> —— 每只怪独立成型，便于单文件替换。
"""

import os
import sys

STROKE = "#2A1F17"
SW = 6.0
RY = 12.0  # 阴影椭圆统一压扁度

# --------------------------------------------------------------------------- 调色板
# 与 game_data.json 的 elements.table 同源：主色偏亮，暗色用于内阴影/细节，点缀色用于高光
ELEM_COLOR = {
    "water": "#4FC3F7",
    "fire": "#FF7043",
    "wind": "#66BB6A",
    "earth": "#A1887F",
    "light": "#FFD54F",
    "dark": "#7E57C2",
}


def shadow(cx=100.0, cy=174.0, rx=60.0, alpha=0.22):
    return '<ellipse cx="%.1f" cy="%.1f" rx="%.1f" ry="%.1f" fill="#000000" fill-opacity="%.2f"/>' % (
        cx, cy, rx, RY, alpha)


def eyes(lx=80.0, rx=120.0, y=112.0, r=10.0, glint=True, color="#2A1F17"):
    s = '<circle cx="%.1f" cy="%.1f" r="%.1f" fill="%s"/>' % (lx, y, r, color)
    s += '<circle cx="%.1f" cy="%.1f" r="%.1f" fill="%s"/>' % (rx, y, r, color)
    if glint:
        s += '<circle cx="%.1f" cy="%.1f" r="%.1f" fill="#FFFFFF"/>' % (lx - 3.5, y - 3.5, r * 0.34)
        s += '<circle cx="%.1f" cy="%.1f" r="%.1f" fill="#FFFFFF"/>' % (rx - 3.5, y - 3.5, r * 0.34)
    return s


def stroke_eyes(cx=100.0, y=112.0, dx=20.0, w=14.0, h=9.0, color="#2A1F17"):
    """两条横条眼（头盔/面罩用）"""
    s = '<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="%.1f" fill="%s"/>' % (
        cx - dx - w / 2, y - h / 2, w, h, h / 2, color)
    s += '<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="%.1f" fill="%s"/>' % (
        cx + dx - w / 2, y - h / 2, w, h, h / 2, color)
    return s


def layered_arcs(cx, cy, radii, color, width, sweep=250, start=-125):
    """同心圆弧：做旋涡 / 风环 / 音波，避免用 stroke-dasharray 之外的复杂特性"""
    out = []
    for r in radii:
        x0 = cx + r * 0.985
        y0 = cy
        import math
        a0 = math.radians(start)
        a1 = math.radians(start + sweep)
        x1 = cx + r * math.cos(a0)
        y1 = cy + r * math.sin(a0)
        x2 = cx + r * math.cos(a1)
        y2 = cy + r * math.sin(a1)
        large = 1 if sweep > 180 else 0
        out.append('<path d="M %.1f %.1f A %.1f %.1f 0 %d 1 %.1f %.1f" fill="none" '
                   'stroke="%s" stroke-width="%.1f" stroke-linecap="round"/>'
                   % (x1, y1, r, r, large, x2, y2, color, width))
    return "".join(out)


# --------------------------------------------------------------------------- 各原型
def arch_slime(m, d, a):
    """软泥怪：一坨果冻，重心低、边缘抖"""
    s = shadow(rx=60)
    s += ('<path d="M36 170 C26 122 50 66 100 66 C150 66 174 122 164 170 Z" '
          'fill="%s" stroke="%s" stroke-width="%.1f" stroke-linejoin="round"/>' % (m, STROKE, SW))
    s += ('<path d="M52 168 C46 132 62 92 92 88" fill="none" stroke="%s" '
          'stroke-width="9" stroke-linecap="round" stroke-opacity="0.75"/>' % a)
    s += eyes(80, 120, 112, 10)
    s += ('<path d="M90 140 Q100 149 110 140" fill="none" stroke="%s" stroke-width="5" '
          'stroke-linecap="round"/>' % STROKE)
    return s


def arch_nut_soldier(m, d, a):
    """坚果小兵：圆滚滚的坚果壳 + 头盔 + 小盾"""
    s = shadow(rx=54)
    s += ('<rect x="54" y="88" width="92" height="80" rx="30" fill="%s" stroke="%s" '
          'stroke-width="%.1f"/>' % (m, STROKE, SW))
    # 坚果壳纹路
    s += ('<path d="M62 106 Q100 128 138 106" fill="none" stroke="%s" stroke-width="5" '
          'stroke-opacity="0.55" stroke-linecap="round"/>' % d)
    # 头盔
    s += ('<path d="M60 92 A42 42 0 0 1 140 92 Z" fill="%s" stroke="%s" stroke-width="%.1f" '
          'stroke-linejoin="round"/>' % (d, STROKE, SW))
    s += '<rect x="52" y="86" width="96" height="12" rx="6" fill="%s" stroke="%s" stroke-width="4"/>' % (a, STROKE)
    s += stroke_eyes(100, 126, 22, 15, 9)
    # 小盾
    s += ('<rect x="128" y="108" width="42" height="52" rx="12" fill="%s" stroke="%s" '
          'stroke-width="%.1f"/>' % (a, STROKE, SW))
    s += '<circle cx="149" cy="134" r="8" fill="%s" stroke="%s" stroke-width="3.5"/>' % (d, STROKE)
    return s


def arch_archer(m, d, a):
    """森林弓箭手：斗篷 + 兜帽 + 长弓"""
    s = shadow(rx=52)
    s += ('<path d="M100 62 C74 66 60 104 54 170 L146 170 C140 104 126 66 100 62 Z" '
          'fill="%s" stroke="%s" stroke-width="%.1f" stroke-linejoin="round"/>' % (m, STROKE, SW))
    s += ('<path d="M100 62 C82 74 76 100 74 130 L126 130 C124 100 118 74 100 62 Z" '
          'fill="%s" fill-opacity="0.92" stroke="%s" stroke-width="4.5"/>' % (d, STROKE))
    s += '<ellipse cx="100" cy="100" rx="18" ry="20" fill="#3A2A20"/>'
    s += '<circle cx="93" cy="98" r="4.5" fill="%s"/><circle cx="107" cy="98" r="4.5" fill="%s"/>' % (a, a)
    # 长弓
    s += ('<path d="M42 62 Q22 118 42 174" fill="none" stroke="%s" stroke-width="%.1f" '
          'stroke-linecap="round"/>' % (a, SW + 2))
    s += '<line x1="42" y1="62" x2="42" y2="174" stroke="%s" stroke-width="3.5"/>' % STROKE
    s += ('<line x1="30" y1="118" x2="72" y2="118" stroke="%s" stroke-width="5" '
          'stroke-linecap="round"/>' % a)
    return s


def arch_guard(m, d, a):
    """城堡重装卫兵：方盔 + 塔盾 + 长枪"""
    s = shadow(rx=56)
    s += '<rect x="72" y="146" width="20" height="28" rx="7" fill="%s" stroke="%s" stroke-width="4.5"/>' % (d, STROKE)
    s += '<rect x="108" y="146" width="20" height="28" rx="7" fill="%s" stroke="%s" stroke-width="4.5"/>' % (d, STROKE)
    s += ('<rect x="62" y="84" width="76" height="70" rx="18" fill="%s" stroke="%s" '
          'stroke-width="%.1f"/>' % (m, STROKE, SW))
    s += '<rect x="62" y="112" width="76" height="14" fill="%s" stroke="%s" stroke-width="3.5"/>' % (a, STROKE)
    # 头盔 + 盔缨
    s += ('<path d="M64 84 A36 40 0 0 1 136 84 Z" fill="%s" stroke="%s" stroke-width="%.1f" '
          'stroke-linejoin="round"/>' % (d, STROKE, SW))
    s += ('<path d="M100 24 C112 30 114 42 104 46 L96 46 C86 42 88 30 100 24 Z" fill="%s" '
          'stroke="%s" stroke-width="4.5"/>' % (a, STROKE))
    s += '<rect x="94" y="42" width="12" height="22" rx="5" fill="%s" stroke="%s" stroke-width="4"/>' % (d, STROKE)
    s += stroke_eyes(100, 112, 18, 13, 8)
    # 塔盾
    s += ('<rect x="132" y="92" width="52" height="72" rx="14" fill="%s" stroke="%s" '
          'stroke-width="%.1f"/>' % (a, STROKE, SW))
    s += '<circle cx="158" cy="128" r="11" fill="none" stroke="%s" stroke-width="4.5"/>' % d
    return s


def arch_ballista(m, d, a):
    """弩箭车：木架 + 弓臂 + 弹丸/弩矢"""
    s = shadow(rx=68)
    s += '<rect x="34" y="116" width="132" height="34" rx="10" fill="%s" stroke="%s" stroke-width="%.1f"/>' % (d, STROKE, SW)
    s += '<rect x="44" y="96" width="112" height="24" rx="8" fill="%s" stroke="%s" stroke-width="5"/>' % (m, STROKE)
    for cx in (62.0, 138.0):
        s += '<circle cx="%.1f" cy="156" r="20" fill="%s" stroke="%s" stroke-width="5"/>' % (cx, m, STROKE)
        s += '<circle cx="%.1f" cy="156" r="6" fill="%s" stroke="%s" stroke-width="3" />' % (cx, d, STROKE)
        s += '<line x1="%.1f" y1="138" x2="%.1f" y2="174" stroke="%s" stroke-width="3.5"/>' % (cx, cx, STROKE)
    # 弓臂
    s += ('<path d="M28 84 Q100 46 172 84" fill="none" stroke="%s" stroke-width="%.1f" '
          'stroke-linecap="round"/>' % (a, SW + 2))
    s += '<line x1="28" y1="84" x2="100" y2="104" stroke="%s" stroke-width="3.5"/>' % STROKE
    s += '<line x1="172" y1="84" x2="100" y2="104" stroke="%s" stroke-width="3.5"/>' % STROKE
    # 弹丸
    s += '<circle cx="100" cy="104" r="17" fill="%s" stroke="%s" stroke-width="5"/>' % (m, STROKE)
    s += '<circle cx="94" cy="98" r="5" fill="#FFFFFF" fill-opacity="0.55"/>'
    return s


def arch_bard(m, d, a):
    """城堡军乐手：号角 + 羽帽，负责给全队加攻"""
    s = shadow(rx=50)
    s += ('<path d="M100 78 C76 78 62 108 58 170 L142 170 C138 108 124 78 100 78 Z" '
          'fill="%s" stroke="%s" stroke-width="%.1f" stroke-linejoin="round"/>' % (m, STROKE, SW))
    s += '<rect x="58" y="118" width="84" height="12" fill="%s" stroke="%s" stroke-width="3.5"/>' % (a, STROKE)
    s += '<circle cx="100" cy="72" r="24" fill="%s" stroke="%s" stroke-width="%.1f"/>' % (m, STROKE, SW)
    s += eyes(91, 109, 74, 6.5)
    # 羽帽
    s += ('<path d="M74 62 L100 24 L126 62 Z" fill="%s" stroke="%s" stroke-width="%.1f" '
          'stroke-linejoin="round"/>' % (d, STROKE, SW))
    s += '<rect x="70" y="58" width="60" height="11" rx="5.5" fill="%s" stroke="%s" stroke-width="3.5"/>' % (a, STROKE)
    s += ('<path d="M124 40 C142 32 152 40 150 52" fill="none" stroke="%s" stroke-width="6" '
          'stroke-linecap="round"/>' % a)
    # 号角
    s += ('<path d="M118 100 L156 88 L164 104 L124 118 Z" fill="%s" stroke="%s" stroke-width="5" '
          'stroke-linejoin="round"/>' % (a, STROKE))
    s += '<ellipse cx="162" cy="96" rx="9" ry="15" fill="%s" stroke="%s" stroke-width="4.5"/>' % (m, STROKE)
    # 音符
    s += '<circle cx="176" cy="60" r="7" fill="%s" stroke="%s" stroke-width="3"/>' % (a, STROKE)
    s += '<line x1="182" y1="60" x2="182" y2="34" stroke="%s" stroke-width="4.5" stroke-linecap="round"/>' % STROKE
    return s


def arch_storm(m, d, a):
    """风暴元素：旋涡 + 核心眼"""
    s = shadow(rx=58)
    s += layered_arcs(100, 118, [62, 46, 30], d, 11)
    s += layered_arcs(100, 118, [70, 54], a, 6, sweep=200, start=-170)
    s += '<circle cx="100" cy="118" r="24" fill="%s" stroke="%s" stroke-width="5"/>' % (a, STROKE)
    s += '</circle>'
    s += '<ellipse cx="100" cy="118" rx="9" ry="13" fill="#2A1F17"/>'
    s += '<circle cx="97" cy="114" r="3.4" fill="#FFFFFF"/>'
    # 小闪电
    s += '<path d="M28 52 L46 52 L36 72 L52 70 L32 96 L38 74 L24 76 Z" fill="%s" stroke="%s" stroke-width="3.5" stroke-linejoin="round"/>' % (a, STROKE)
    return s


def arch_cloud(m, d, a):
    """雷云精灵：云团 + 闪电 + 雨点"""
    s = shadow(rx=62)
    s += ('<path d="M46 140 C24 140 20 112 40 106 C38 82 62 68 82 76 C90 56 124 56 134 76 '
          'C160 70 178 88 172 108 C190 114 186 140 164 140 Z" fill="%s" stroke="%s" '
          'stroke-width="%.1f" stroke-linejoin="round"/>' % (m, STROKE, SW))
    s += eyes(80, 120, 108, 9)
    s += '<path d="M92 146 L112 146 L100 172 L118 168 L96 200 L104 172 L86 176 Z" fill="%s" stroke="%s" stroke-width="4" stroke-linejoin="round"/>' % (a, STROKE)
    s += '<circle cx="48" cy="158" r="6" fill="%s"/>' % a
    s += '<circle cx="34" cy="186" r="5" fill="%s" fill-opacity="0.8"/>' % a
    return s


def arch_ruin(m, d, a):
    """遗迹守卫：石像鬼式的石块巨人"""
    s = shadow(rx=60)
    s += '<rect x="60" y="140" width="26" height="34" rx="6" fill="%s" stroke="%s" stroke-width="4.5"/>' % (d, STROKE)
    s += '<rect x="114" y="140" width="26" height="34" rx="6" fill="%s" stroke="%s" stroke-width="4.5"/>' % (d, STROKE)
    s += '<rect x="50" y="70" width="100" height="78" rx="16" fill="%s" stroke="%s" stroke-width="%.1f"/>' % (m, STROKE, SW)
    s += '<rect x="30" y="80" width="26" height="56" rx="10" fill="%s" stroke="%s" stroke-width="4.5"/>' % (d, STROKE)
    s += '<rect x="144" y="80" width="26" height="56" rx="10" fill="%s" stroke="%s" stroke-width="4.5"/>' % (d, STROKE)
    s += '<rect x="70" y="28" width="60" height="46" rx="12" fill="%s" stroke="%s" stroke-width="%.1f"/>' % (m, STROKE, SW)
    s += '<rect x="80" y="44" width="40" height="10" rx="5" fill="%s"/>' % a
    # 裂纹
    s += '<path d="M68 96 L84 112 L72 126 L86 140" fill="none" stroke="%s" stroke-width="4" stroke-linecap="round"/>' % d
    s += '<path d="M128 92 L116 110 L132 122" fill="none" stroke="%s" stroke-width="4" stroke-linecap="round"/>' % d
    # 胸口符文
    s += '<rect x="90" y="92" width="20" height="20" rx="4" fill="%s" stroke="%s" stroke-width="3.5"/>' % (a, STROKE)
    return s


def arch_puppet(m, d, a):
    """傀儡法师：提线人偶 + 法杖宝珠"""
    s = shadow(rx=54)
    s += '<line x1="76" y1="10" x2="88" y2="58" stroke="%s" stroke-width="3" stroke-opacity="0.8"/>' % a
    s += '<line x1="124" y1="10" x2="112" y2="58" stroke="%s" stroke-width="3" stroke-opacity="0.8"/>' % a
    s += ('<path d="M100 72 C74 72 60 106 56 170 L144 170 C140 106 126 72 100 72 Z" '
          'fill="%s" stroke="%s" stroke-width="%.1f" stroke-linejoin="round"/>' % (m, STROKE, SW))
    s += ('<path d="M100 96 L100 170 M74 132 L126 132" stroke="%s" stroke-width="4.5" '
          'stroke-linecap="round"/>' % d)
    s += '<circle cx="100" cy="62" r="26" fill="%s" stroke="%s" stroke-width="%.1f"/>' % (a, STROKE, SW)
    s += '<line x1="86" y1="54" x2="96" y2="64" stroke="%s" stroke-width="4.5" stroke-linecap="round"/>' % STROKE
    s += '<line x1="96" y1="54" x2="86" y2="64" stroke="%s" stroke-width="4.5" stroke-linecap="round"/>' % STROKE
    s += '<line x1="104" y1="54" x2="114" y2="64" stroke="%s" stroke-width="4.5" stroke-linecap="round"/>' % STROKE
    s += '<line x1="114" y1="54" x2="104" y2="64" stroke="%s" stroke-width="4.5" stroke-linecap="round"/>' % STROKE
    s += '<path d="M92 74 Q100 80 108 74" fill="none" stroke="%s" stroke-width="3.5" stroke-linecap="round"/>' % STROKE
    # 法杖
    s += '<line x1="150" y1="176" x2="162" y2="72" stroke="%s" stroke-width="7" stroke-linecap="round"/>' % d
    s += '<circle cx="163" cy="60" r="15" fill="%s" stroke="%s" stroke-width="4.5"/>' % (a, STROKE)
    s += '<circle cx="158" cy="55" r="4.5" fill="#FFFFFF" fill-opacity="0.7"/>'
    return s


def arch_goblin(m, d, a, gear="chief"):
    """哥布林三兄弟：共用身体，靠头饰/武器区分"""
    s = shadow(rx=52)
    s += '<rect x="66" y="140" width="22" height="32" rx="8" fill="%s" stroke="%s" stroke-width="4.5"/>' % (d, STROKE)
    s += '<rect x="112" y="140" width="22" height="32" rx="8" fill="%s" stroke="%s" stroke-width="4.5"/>' % (d, STROKE)
    s += '<rect x="56" y="86" width="88" height="66" rx="24" fill="%s" stroke="%s" stroke-width="%.1f"/>' % (m, STROKE, SW)
    # 大耳朵
    s += ('<path d="M56 82 L18 62 L50 108 Z" fill="%s" stroke="%s" stroke-width="%.1f" '
          'stroke-linejoin="round"/>' % (m, STROKE, SW))
    s += ('<path d="M144 82 L182 62 L150 108 Z" fill="%s" stroke="%s" stroke-width="%.1f" '
          'stroke-linejoin="round"/>' % (m, STROKE, SW))
    s += '<circle cx="100" cy="62" r="34" fill="%s" stroke="%s" stroke-width="%.1f"/>' % (m, STROKE, SW)
    s += eyes(86, 114, 62, 8)
    s += '<path d="M88 78 Q100 88 112 78" fill="none" stroke="%s" stroke-width="4" stroke-linecap="round"/>' % STROKE
    s += '<path d="M92 74 L88 82 M108 74 L112 82" stroke="#FFFFFF" stroke-width="5" stroke-linecap="round"/>'

    if gear == "chief":
        # 百夫长：红缨盔 + 大手斧
        s += ('<path d="M68 44 A34 34 0 0 1 132 44 Z" fill="%s" stroke="%s" stroke-width="%.1f" '
              'stroke-linejoin="round"/>' % (a, STROKE, SW))
        s += '<rect x="64" y="40" width="72" height="10" rx="5" fill="%s" stroke="%s" stroke-width="3.5"/>' % (d, STROKE)
        s += '<path d="M100 42 C112 30 118 16 112 6" fill="none" stroke="%s" stroke-width="7" stroke-linecap="round"/>' % a
        s += '<line x1="150" y1="176" x2="150" y2="80" stroke="%s" stroke-width="7" stroke-linecap="round"/>' % d
        s += ('<path d="M132 82 L172 74 L176 96 L136 104 Z" fill="%s" stroke="%s" stroke-width="4.5" '
              'stroke-linejoin="round"/>' % (a, STROKE))
    elif gear == "slinger":
        # 投石手：皮兜 + 石弹 + 束发
        s += '<path d="M76 40 Q100 22 124 40" fill="none" stroke="%s" stroke-width="7" stroke-linecap="round"/>' % d
        s += ('<path d="M170 96 Q196 122 168 150" fill="none" stroke="%s" stroke-width="5" '
              'stroke-linecap="round"/>' % a)
        s += '<circle cx="168" cy="152" r="10" fill="%s" stroke="%s" stroke-width="3.5"/>' % (d, STROKE)
        s += '<circle cx="180" cy="124" r="14" fill="%s" stroke="%s" stroke-width="4.5"/>' % (m, STROKE)
        s += '<circle cx="175" cy="119" r="4.5" fill="#FFFFFF" fill-opacity="0.55"/>'
    else:
        # 萨满：骨面具 + 法杖 + 治疗光
        s += ('<path d="M66 46 A34 34 0 0 1 134 46 Z" fill="%s" stroke="%s" stroke-width="%.1f" '
              'stroke-linejoin="round"/>' % (a, STROKE, SW))
        s += '<path d="M78 30 L86 12 L100 26 L114 12 L122 30" fill="none" stroke="%s" stroke-width="5" stroke-linecap="round"/>' % d
        s += '<circle cx="86" cy="62" r="9" fill="%s"/><circle cx="114" cy="62" r="9" fill="%s"/>' % (STROKE, STROKE)
        s += '<circle cx="86" cy="62" r="3.4" fill="%s"/><circle cx="114" cy="62" r="3.4" fill="%s"/>' % (a, a)
        s += '<line x1="148" y1="176" x2="158" y2="70" stroke="%s" stroke-width="7" stroke-linecap="round"/>' % d
        s += '<circle cx="160" cy="58" r="16" fill="%s" stroke="%s" stroke-width="4.5"/>' % (a, STROKE)
        s += '<circle cx="160" cy="58" r="6" fill="#FFFFFF" fill-opacity="0.7"/>'
    return s


def arch_boss(m, d, a):
    """巨石守卫（Boss）：花岗岩巨躯 + 尖角盔 + 符文盾"""
    s = shadow(rx=78, cy=180, alpha=0.28)
    s += '<rect x="52" y="146" width="34" height="40" rx="8" fill="%s" stroke="%s" stroke-width="5"/>' % (d, STROKE)
    s += '<rect x="114" y="146" width="34" height="40" rx="8" fill="%s" stroke="%s" stroke-width="5"/>' % (d, STROKE)
    s += '<rect x="36" y="66" width="128" height="88" rx="20" fill="%s" stroke="%s" stroke-width="%.1f"/>' % (m, STROKE, SW)
    # 肩甲
    s += '<rect x="20" y="58" width="46" height="40" rx="14" fill="%s" stroke="%s" stroke-width="5"/>' % (d, STROKE)
    s += '<rect x="134" y="58" width="46" height="40" rx="14" fill="%s" stroke="%s" stroke-width="5"/>' % (d, STROKE)
    # 头 + 双角
    s += '<rect x="66" y="20" width="68" height="52" rx="14" fill="%s" stroke="%s" stroke-width="%.1f"/>' % (m, STROKE, SW)
    # 犄角收在画布内：原稿顶端画到 y=-6 会被 viewBox 裁掉一段
    s += '<path d="M74 30 C58 24 50 12 56 2" fill="none" stroke="%s" stroke-width="11" stroke-linecap="round"/>' % d
    s += '<path d="M126 30 C142 24 150 12 144 2" fill="none" stroke="%s" stroke-width="11" stroke-linecap="round"/>' % d
    s += '<rect x="78" y="36" width="44" height="12" rx="6" fill="%s"/>' % a
    # 裂纹与符文
    s += '<path d="M50 92 L70 112 L54 130 L72 146" fill="none" stroke="%s" stroke-width="4.5" stroke-linecap="round"/>' % d
    s += '<path d="M148 88 L130 108 L150 124" fill="none" stroke="%s" stroke-width="4.5" stroke-linecap="round"/>' % d
    s += '<circle cx="100" cy="106" r="17" fill="none" stroke="%s" stroke-width="6"/>' % a
    s += '<circle cx="100" cy="106" r="6" fill="%s"/>' % a
    # 符文盾
    s += ('<rect x="150" y="86" width="48" height="78" rx="16" fill="%s" stroke="%s" stroke-width="%.1f"/>' % (a, STROKE, SW))
    s += '<path d="M174 100 L174 132 M160 112 L188 112" stroke="%s" stroke-width="5" stroke-linecap="round"/>' % d
    return s


# --------------------------------------------------------------------------- 规格表
# 14 只怪：键 = 文件名，值 = (原型, 元素, 装备变体)
SPECS = [
    ("mob_slime",           "slime",   "water", None),
    ("mob_nut_soldier",     "nut",     "earth", None),
    ("mob_forest_archer",   "archer",  "wind",  None),
    ("mob_castle_guard",    "guard",   "light", None),
    ("mob_ballista",        "ballista", "earth", None),
    ("mob_castle_bard",     "bard",    "light", None),
    ("mob_storm_elemental", "storm",   "wind",  None),
    ("mob_cloud_sprite",    "cloud",   "wind",  None),
    ("mob_ruin_guard",      "ruin",    "earth", None),
    ("mob_puppet_mage",     "puppet",  "dark",  None),
    ("mob_goblin_chief",    "goblin",  "fire",  "chief"),
    ("mob_stone_slinger",   "goblin",  "earth", "slinger"),
    ("mob_goblin_shaman",   "goblin",  "dark",  "shaman"),
    ("mob_stone_warden",    "boss",    "earth", None),
]

ARCH = {
    "slime": arch_slime,
    "nut": arch_nut_soldier,
    "archer": arch_archer,
    "guard": arch_guard,
    "ballista": arch_ballista,
    "bard": arch_bard,
    "storm": arch_storm,
    "cloud": arch_cloud,
    "ruin": arch_ruin,
    "puppet": arch_puppet,
    "goblin": arch_goblin,
    "boss": arch_boss,
}

TEMPLATE = (
    '<svg xmlns="http://www.w3.org/2000/svg" width="200" height="200" viewBox="0 0 200 200">\n'
    '  <title>%s</title>\n'
    '%s\n'
    '</svg>\n'
)


def mix(hex_color, ratio, target="#FFFFFF"):
    """把主色往目标色混，得到「暗色/亮色」配套（避免额外维护三套色值表）"""
    h = hex_color.lstrip("#")
    t = target.lstrip("#")
    out = "#"
    for i in range(3):
        a = int(h[i * 2:i * 2 + 2], 16)
        b = int(t[i * 2:i * 2 + 2], 16)
        out += "%02X" % max(0, min(255, int(round(a + (b - a) * ratio))))
    return out


def main():
    check_only = "--check" in sys.argv
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_dir = os.path.join(root, "assets", "icons", "monsters")

    if check_only:
        missing = [n for n, _, _, _ in SPECS
                   if not os.path.isfile(os.path.join(out_dir, n + ".svg"))]
        if missing:
            print("缺失 %d 个图标：%s" % (len(missing), ", ".join(missing)))
            return 1
        print("14 只怪物图标齐备：%s" % out_dir)
        return 0

    os.makedirs(out_dir, exist_ok=True)
    for name, arch, elem, gear in SPECS:
        main_c = ELEM_COLOR[elem]
        dark_c = mix(main_c, 0.34, "#2A1F17")
        accent_c = mix(main_c, 0.62)
        body = ARCH[arch](main_c, dark_c, accent_c)
        if arch == "goblin":
            body = arch_goblin(main_c, dark_c, accent_c, gear)
        svg = TEMPLATE % (name, body)
        path = os.path.join(out_dir, name + ".svg")
        with open(path, "w", encoding="utf-8") as f:
            f.write(svg)
        print("写出 %s  (%d 字节)" % (os.path.relpath(path, root), len(svg)))
    print("完成：%d 只" % len(SPECS))
    return 0


if __name__ == "__main__":
    sys.exit(main())
