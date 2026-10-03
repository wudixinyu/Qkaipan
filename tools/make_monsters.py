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
import inspect

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


def gear(cx, cy, r, color, teeth=8, stroke=STROKE, sw=4.0):
    """齿轮：一圈方齿 + 内圈空心，机械主题反复用"""
    import math
    parts = []
    for i in range(teeth):
        ang = 2 * math.pi * i / teeth
        x = cx + r * math.cos(ang)
        y = cy + r * math.sin(ang)
        parts.append('<circle cx="%.1f" cy="%.1f" r="%.1f" fill="%s" stroke="%s" stroke-width="%.1f"/>'
                     % (x, y, r * 0.22, color, stroke, sw * 0.6))
    parts.append('<circle cx="%.1f" cy="%.1f" r="%.1f" fill="%s" stroke="%s" stroke-width="%.1f"/>'
                 % (cx, cy, r * 0.82, color, stroke, sw))
    parts.append('<circle cx="%.1f" cy="%.1f" r="%.1f" fill="#2A1F17" fill-opacity="0.35" stroke="%s" stroke-width="%.1f"/>'
                 % (cx, cy, r * 0.34, stroke, sw))
    return "".join(parts)


def arch_mech_spider(m, d, a):
    """机械蜘蛛：圆壳机身 + 八条节肢 + 复眼"""
    s = shadow(rx=64)
    # 八条腿（左右各四，折线节肢）
    for sx in (-1, 1):
        for i, (y0, y1) in enumerate([(108, 150), (122, 168), (136, 180), (150, 186)]):
            x0 = 100 + sx * 34
            knee = 100 + sx * (74 + i * 6)
            s += ('<path d="M%.1f %.1f L%.1f %.1f L%.1f %.1f" fill="none" stroke="%s" '
                  'stroke-width="6.5" stroke-linecap="round" stroke-linejoin="round"/>'
                  % (x0, y0, knee, y0 - 22, knee - sx * 8, y1, d))
    # 机身
    s += '<ellipse cx="100" cy="128" rx="46" ry="38" fill="%s" stroke="%s" stroke-width="%.1f"/>' % (m, STROKE, SW)
    s += '<ellipse cx="100" cy="120" rx="30" ry="22" fill="%s" fill-opacity="0.85" stroke="%s" stroke-width="4"/>' % (d, STROKE)
    # 头部 + 复眼
    s += '<circle cx="100" cy="94" r="22" fill="%s" stroke="%s" stroke-width="%.1f"/>' % (d, STROKE, SW)
    s += '<circle cx="92" cy="90" r="5" fill="%s"/><circle cx="108" cy="90" r="5" fill="%s"/>' % (a, a)
    s += '<circle cx="86" cy="100" r="3.5" fill="%s"/><circle cx="114" cy="100" r="3.5" fill="%s"/>' % (a, a)
    s += gear(100, 130, 14, a, teeth=6, sw=3.2)
    return s


def arch_mech_soldier(m, d, a, gear_name="infantry"):
    """发条步兵家族：齿轮躯干 + 面罩头 + 武器（步兵/枪手/弓手/机枪手）"""
    s = shadow(rx=52)
    s += '<rect x="74" y="150" width="18" height="26" rx="6" fill="%s" stroke="%s" stroke-width="4.5"/>' % (d, STROKE)
    s += '<rect x="108" y="150" width="18" height="26" rx="6" fill="%s" stroke="%s" stroke-width="4.5"/>' % (d, STROKE)
    # 躯干（发条盒）
    s += ('<rect x="62" y="84" width="76" height="72" rx="16" fill="%s" stroke="%s" stroke-width="%.1f"/>'
          % (m, STROKE, SW))
    s += gear(100, 120, 20, d, teeth=8, sw=3.5)
    # 头 + 面罩横条眼
    s += '<rect x="78" y="46" width="44" height="40" rx="12" fill="%s" stroke="%s" stroke-width="%.1f"/>' % (d, STROKE, SW)
    s += '<rect x="80" y="60" width="40" height="10" rx="5" fill="%s"/>' % a
    s += '<circle cx="100" cy="40" r="7" fill="%s" stroke="%s" stroke-width="3.5"/>' % (a, STROKE)
    if gear_name == "archer":
        # 蒸汽弓：单手长弓 + 蓄能箭
        s += ('<path d="M40 60 Q18 116 40 172" fill="none" stroke="%s" stroke-width="%.1f" stroke-linecap="round"/>'
              % (a, SW + 2))
        s += '<line x1="40" y1="60" x2="40" y2="172" stroke="%s" stroke-width="3.5"/>' % STROKE
        s += '<line x1="28" y1="116" x2="70" y2="116" stroke="%s" stroke-width="5" stroke-linecap="round"/>' % a
    elif gear_name == "gunner":
        # 蒸汽枪：短管火枪 + 铆钉弹匣
        s += ('<rect x="118" y="104" width="64" height="16" rx="6" fill="%s" stroke="%s" stroke-width="4.5"/>'
              % (d, STROKE))
        s += '<rect x="150" y="118" width="16" height="20" rx="5" fill="%s" stroke="%s" stroke-width="4"/>' % (a, STROKE)
        s += '<circle cx="178" cy="112" r="6" fill="%s" stroke="%s" stroke-width="3.5"/>' % (a, STROKE)
    elif gear_name == "mgner":
        # 蒸汽机枪：多管枪身 + 弹链鼓
        s += ('<rect x="112" y="98" width="76" height="14" rx="5" fill="%s" stroke="%s" stroke-width="4"/>'
              % (d, STROKE))
        s += ('<rect x="112" y="116" width="76" height="14" rx="5" fill="%s" stroke="%s" stroke-width="4"/>'
              % (d, STROKE))
        s += '<circle cx="120" cy="136" r="15" fill="%s" stroke="%s" stroke-width="4.5"/>' % (a, STROKE)
        s += '<circle cx="120" cy="136" r="5" fill="%s"/>' % d
    else:
        # 步兵：齿轮盾 + 短刀
        s += ('<rect x="132" y="94" width="44" height="62" rx="12" fill="%s" stroke="%s" stroke-width="%.1f"/>'
              % (a, STROKE, SW))
        s += gear(154, 125, 12, d, teeth=6, sw=3)
        s += ('<rect x="44" y="108" width="12" height="46" rx="5" fill="%s" stroke="%s" stroke-width="4"/>'
              % (a, STROKE))
    return s


def arch_mech_guard(m, d, a, gear_name="heavy"):
    """重装齿轮家族：厚甲方躯 + 肩甲 + 大盾（重型齿轮卫兵 / 自动化盾卫）"""
    s = shadow(rx=62)
    s += '<rect x="66" y="150" width="24" height="28" rx="7" fill="%s" stroke="%s" stroke-width="4.5"/>' % (d, STROKE)
    s += '<rect x="110" y="150" width="24" height="28" rx="7" fill="%s" stroke="%s" stroke-width="4.5"/>' % (d, STROKE)
    s += ('<rect x="58" y="80" width="84" height="76" rx="14" fill="%s" stroke="%s" stroke-width="%.1f"/>'
          % (m, STROKE, SW))
    s += '<rect x="58" y="110" width="84" height="12" fill="%s" stroke="%s" stroke-width="3.5"/>' % (a, STROKE)
    # 肩甲
    s += '<rect x="38" y="74" width="34" height="30" rx="10" fill="%s" stroke="%s" stroke-width="5"/>' % (d, STROKE)
    s += '<rect x="128" y="74" width="34" height="30" rx="10" fill="%s" stroke="%s" stroke-width="5"/>' % (d, STROKE)
    # 方盔 + 横条眼
    s += ('<path d="M66 78 A34 34 0 0 1 134 78 Z" fill="%s" stroke="%s" stroke-width="%.1f" stroke-linejoin="round"/>'
          % (d, STROKE, SW))
    s += stroke_eyes(100, 100, 18, 15, 9)
    if gear_name == "shield":
        # 自动化盾卫：整面能量塔盾盖住半身
        s += ('<rect x="126" y="78" width="60" height="98" rx="14" fill="%s" stroke="%s" stroke-width="%.1f"/>'
              % (a, STROKE, SW))
        s += '<rect x="138" y="98" width="36" height="58" rx="10" fill="none" stroke="%s" stroke-width="4.5"/>' % d
        s += '<circle cx="156" cy="127" r="9" fill="%s"/>' % d
    else:
        # 重型齿轮卫兵：胸口大齿轮 + 战锤
        s += gear(100, 118, 18, a, teeth=8, sw=3.5)
        s += '<line x1="44" y1="150" x2="44" y2="96" stroke="%s" stroke-width="8" stroke-linecap="round"/>' % d
        s += '<rect x="26" y="74" width="36" height="30" rx="8" fill="%s" stroke="%s" stroke-width="4.5"/>' % (a, STROKE)
    return s


def arch_mech_dog(m, d, a):
    """机械维修犬：四足机身 + 扳手前爪 + 头顶警示灯"""
    s = shadow(rx=64)
    for x in (56, 84, 118, 146):
        s += '<rect x="%d" y="140" width="16" height="30" rx="6" fill="%s" stroke="%s" stroke-width="4"/>' % (x - 8, d, STROKE)
    s += ('<rect x="48" y="98" width="104" height="52" rx="16" fill="%s" stroke="%s" stroke-width="%.1f"/>'
          % (m, STROKE, SW))
    s += gear(80, 122, 15, d, teeth=6, sw=3)
    # 头
    s += ('<rect x="128" y="80" width="48" height="42" rx="12" fill="%s" stroke="%s" stroke-width="%.1f"/>'
          % (d, STROKE, SW))
    s += '<circle cx="160" cy="96" r="6" fill="%s"/><circle cx="146" cy="96" r="6" fill="%s"/>' % (a, a)
    s += ('<path d="M162 122 L182 132 L174 146" fill="none" stroke="%s" stroke-width="6" stroke-linecap="round" stroke-linejoin="round"/>'
          % a)
    # 头顶维修警示灯
    s += '<rect x="146" y="64" width="16" height="12" rx="4" fill="%s" stroke="%s" stroke-width="3.5"/>' % (a, STROKE)
    s += '<circle cx="154" cy="60" r="7" fill="%s" stroke="%s" stroke-width="3.5"/>' % (a, STROKE)
    # 背上的十字医疗标
    s += '<rect x="60" y="108" width="22" height="7" rx="3" fill="%s"/>' % a
    s += '<rect x="67" y="101" width="7" height="22" rx="3" fill="%s"/>' % a
    return s


def arch_mech_support(m, d, a):
    """发条补给车：箱式车身 + 大轮 + 头顶货叉/补给灯"""
    s = shadow(rx=70)
    s += ('<rect x="40" y="92" width="120" height="58" rx="12" fill="%s" stroke="%s" stroke-width="%.1f"/>'
          % (m, STROKE, SW))
    s += '<rect x="52" y="104" width="46" height="34" rx="7" fill="%s" stroke="%s" stroke-width="4"/>' % (d, STROKE)
    s += '<rect x="108" y="104" width="40" height="16" rx="5" fill="%s" stroke="%s" stroke-width="3.5"/>' % (a, STROKE)
    s += '<rect x="108" y="124" width="40" height="14" rx="5" fill="%s" fill-opacity="0.8" stroke="%s" stroke-width="3.5"/>' % (a, STROKE)
    for cx in (66, 134):
        s += '<circle cx="%d" cy="158" r="22" fill="%s" stroke="%s" stroke-width="5"/>' % (cx, d, STROKE)
        s += gear(cx, 158, 10, a, teeth=6, sw=3)
    s += '<rect x="150" y="72" width="30" height="12" rx="5" fill="%s" stroke="%s" stroke-width="4"/>' % (a, STROKE)
    s += '<line x1="165" y1="84" x2="165" y2="92" stroke="%s" stroke-width="5"/>' % d
    return s


def arch_energy_node(m, d, a, gear_name="capacitor"):
    """能量/符文枢纽家族：悬浮能量核心 + 底座 pylons（电容器/中继站/防御塔核心/符文核心）"""
    s = shadow(rx=56)
    # 底座三脚架
    s += ('<path d="M64 172 L100 118 L136 172 Z" fill="none" stroke="%s" stroke-width="%.1f" stroke-linejoin="round"/>'
          % (d, SW))
    s += '<rect x="72" y="140" width="56" height="16" rx="6" fill="%s" stroke="%s" stroke-width="4"/>' % (d, STROKE)
    if gear_name == "tower":
        # 防御塔核心：方塔 + 顶部炮口
        s += ('<rect x="74" y="58" width="52" height="72" rx="10" fill="%s" stroke="%s" stroke-width="%.1f"/>'
              % (m, STROKE, SW))
        s += '<circle cx="100" cy="88" r="16" fill="%s" stroke="%s" stroke-width="4.5"/>' % (a, STROKE)
        s += '<circle cx="100" cy="88" r="6" fill="%s"/>' % STROKE
        s += '<rect x="88" y="40" width="24" height="22" rx="6" fill="%s" stroke="%s" stroke-width="4"/>' % (d, STROKE)
    elif gear_name == "rune_core":
        # 符文核心：菱形水晶 + 环绕符文
        s += ('<path d="M100 44 L134 92 L100 140 L66 92 Z" fill="%s" stroke="%s" stroke-width="%.1f" stroke-linejoin="round"/>'
              % (a, STROKE, SW))
        s += ('<path d="M100 62 L122 92 L100 122 L78 92 Z" fill="%s" fill-opacity="0.7" stroke="%s" stroke-width="4"/>'
              % (m, STROKE))
        s += '<circle cx="100" cy="92" r="8" fill="%s"/>' % d
        s += '<circle cx="52" cy="92" r="5" fill="%s"/><circle cx="148" cy="92" r="5" fill="%s"/>' % (a, a)
    else:
        # 电容器 / 中继站：球形能量罐 + 电弧
        s += '<circle cx="100" cy="88" r="34" fill="%s" stroke="%s" stroke-width="%.1f"/>' % (m, STROKE, SW)
        s += '<circle cx="100" cy="88" r="20" fill="%s" fill-opacity="0.85" stroke="%s" stroke-width="4"/>' % (a, STROKE)
        if gear_name == "capacitor":
            s += '<path d="M92 78 L108 78 L98 96 L112 92 L94 112 L100 96 L86 100 Z" fill="%s" stroke="%s" stroke-width="3" stroke-linejoin="round"/>' % ("#FFFFFF", STROKE)
            s += '<line x1="66" y1="88" x2="48" y2="70" stroke="%s" stroke-width="5" stroke-linecap="round"/>' % a
            s += '<line x1="134" y1="88" x2="152" y2="70" stroke="%s" stroke-width="5" stroke-linecap="round"/>' % a
        else:
            s += layered_arcs(100, 88, [46, 58], a, 5, sweep=180, start=200)
            s += gear(100, 88, 12, d, teeth=6, sw=3)
    return s


def arch_rune_statue(m, d, a, gear_name="gargoyle"):
    """远古符文家族：石像/符文施法者（石像鬼 / 符文师 / 符文祭司）"""
    s = shadow(rx=58)
    if gear_name == "gargoyle":
        # 石像鬼：蹲伏石兽 + 双翼 + 獠牙
        s += ('<path d="M50 150 C30 96 58 72 100 72 C142 72 170 96 150 150 Z" fill="%s" stroke="%s" stroke-width="%.1f" stroke-linejoin="round"/>'
              % (m, STROKE, SW))
        s += ('<path d="M58 96 L20 60 L34 120 Z" fill="%s" stroke="%s" stroke-width="5" stroke-linejoin="round"/>' % (d, STROKE))
        s += ('<path d="M142 96 L180 60 L166 120 Z" fill="%s" stroke="%s" stroke-width="5" stroke-linejoin="round"/>' % (d, STROKE))
        s += '<circle cx="86" cy="106" r="7" fill="%s"/><circle cx="114" cy="106" r="7" fill="%s"/>' % (a, a)
        s += ('<path d="M84 132 L92 122 L100 132 L108 122 L116 132" fill="none" stroke="%s" stroke-width="4.5" stroke-linecap="round"/>' % STROKE)
        s += '<path d="M62 148 L74 158 M138 148 L126 158" stroke="%s" stroke-width="6" stroke-linecap="round"/>' % d
    else:
        # 符文师 / 符文祭司：兜帽法袍 + 悬浮符文石（祭司带治疗光）
        s += ('<path d="M100 66 C72 66 58 104 54 172 L146 172 C142 104 128 66 100 66 Z" '
              'fill="%s" stroke="%s" stroke-width="%.1f" stroke-linejoin="round"/>' % (m, STROKE, SW))
        s += ('<path d="M100 66 C82 74 76 100 74 130 L126 130 C124 100 118 74 100 66 Z" '
              'fill="%s" fill-opacity="0.92" stroke="%s" stroke-width="4.5"/>' % (d, STROKE))
        s += '<ellipse cx="100" cy="102" rx="17" ry="19" fill="#3A2A20"/>'
        s += '<circle cx="93" cy="100" r="4.5" fill="%s"/><circle cx="107" cy="100" r="4.5" fill="%s"/>' % (a, a)
        s += gear(100, 148, 12, a, teeth=6, sw=3)
        if gear_name == "priest":
            s += '<circle cx="150" cy="96" r="16" fill="%s" stroke="%s" stroke-width="4.5"/>' % (a, STROKE)
            s += '<rect x="146" y="86" width="8" height="20" rx="3" fill="%s"/>' % "#FFFFFF"
            s += '<rect x="140" y="92" width="20" height="8" rx="3" fill="%s"/>' % "#FFFFFF"
        else:
            s += ('<path d="M150 84 L170 104 L150 124 L130 104 Z" fill="%s" stroke="%s" stroke-width="4.5" stroke-linejoin="round"/>'
                  % (a, STROKE))
    return s


def arch_mech_boss(m, d, a):
    """机械堡垒巨神兵（Boss）：重装机匣躯 + 单眼 + 巨型齿轮肩 + 蒸汽炮"""
    s = shadow(rx=82, cy=182, alpha=0.30)
    s += '<rect x="52" y="150" width="36" height="40" rx="8" fill="%s" stroke="%s" stroke-width="5"/>' % (d, STROKE)
    s += '<rect x="112" y="150" width="36" height="40" rx="8" fill="%s" stroke="%s" stroke-width="5"/>' % (d, STROKE)
    s += ('<rect x="34" y="64" width="132" height="92" rx="18" fill="%s" stroke="%s" stroke-width="%.1f"/>'
          % (m, STROKE, SW))
    s += '<rect x="34" y="98" width="132" height="14" fill="%s" stroke="%s" stroke-width="3.5"/>' % (a, STROKE)
    # 巨型齿轮肩
    s += gear(40, 60, 24, d, teeth=8, sw=4)
    s += gear(160, 60, 24, d, teeth=8, sw=4)
    # 头 + 单眼扫描
    s += ('<rect x="70" y="18" width="60" height="48" rx="12" fill="%s" stroke="%s" stroke-width="%.1f"/>'
          % (d, STROKE, SW))
    s += '<rect x="78" y="34" width="44" height="14" rx="7" fill="%s"/>' % a
    s += '<circle cx="100" cy="41" r="5" fill="%s"/>' % "#FFFFFF"
    s += '<path d="M70 20 L60 6 M130 20 L140 6" stroke="%s" stroke-width="7" stroke-linecap="round"/>' % a
    # 胸口动力核
    s += '<circle cx="100" cy="110" r="22" fill="%s" stroke="%s" stroke-width="5"/>' % (a, STROKE)
    s += '<circle cx="100" cy="110" r="10" fill="%s"/>' % d
    s += layered_arcs(100, 110, [30, 40], a, 4, sweep=300, start=120)
    # 右臂蒸汽炮
    s += ('<rect x="150" y="96" width="54" height="22" rx="8" fill="%s" stroke="%s" stroke-width="4.5"/>'
          % (m, STROKE))
    s += '<circle cx="200" cy="107" r="10" fill="%s" stroke="%s" stroke-width="4"/>' % (a, STROKE)
    return s


# --------------------------------------------------------------------------- 第三章《深渊暗界·影之迷宫》暗系原型
# 深渊风格：紫黑剪影 + 幽光点缀，沿用同一套描边/阴影规范，与前两章同场不打架
def arch_scarecrow(m, d, a):
    """诅咒草人：十字木桩 + 麻布袋头 + 枯草 + X 形邪眼"""
    s = shadow(rx=52)
    # 十字桩（竖 + 横）
    s += '<rect x="93" y="74" width="14" height="100" rx="4" fill="%s" stroke="%s" stroke-width="5"/>' % (d, STROKE)
    s += '<rect x="52" y="96" width="96" height="12" rx="5" fill="%s" stroke="%s" stroke-width="5"/>' % (d, STROKE)
    # 麻布袍（斜披在横臂上）
    s += ('<path d="M100 78 C72 82 60 118 56 168 L144 168 C140 118 128 82 100 78 Z" '
          'fill="%s" stroke="%s" stroke-width="%.1f" stroke-linejoin="round"/>' % (m, STROKE, SW))
    # 头（麻布袋）
    s += '<circle cx="100" cy="60" r="24" fill="%s" stroke="%s" stroke-width="%.1f"/>' % (m, STROKE, SW)
    s += ('<path d="M86 52 L98 64 M98 52 L86 64" stroke="%s" stroke-width="5" stroke-linecap="round"/>' % a)
    s += ('<path d="M102 52 L114 64 M114 52 L102 64" stroke="%s" stroke-width="5" stroke-linecap="round"/>' % a)
    s += '<path d="M90 72 Q100 66 110 72" fill="none" stroke="%s" stroke-width="4" stroke-linecap="round"/>' % STROKE
    # 枯草束
    s += ('<path d="M56 96 L44 82 M144 96 L156 82 M60 108 L46 108 M140 108 L154 108" '
          'stroke="%s" stroke-width="5" stroke-linecap="round"/>' % a)
    return s


def arch_shadow_knight(m, d, a, gear="knight"):
    """亡魂武者家族：无头骑士（悬浮盔 + 长枪）/ 暗影武者·刃（兜帽 + 太刀）"""
    s = shadow(rx=58)
    s += '<rect x="66" y="150" width="24" height="28" rx="7" fill="%s" stroke="%s" stroke-width="4.5"/>' % (d, STROKE)
    s += '<rect x="110" y="150" width="24" height="28" rx="7" fill="%s" stroke="%s" stroke-width="4.5"/>' % (d, STROKE)
    s += ('<rect x="58" y="82" width="84" height="76" rx="16" fill="%s" stroke="%s" stroke-width="%.1f"/>'
          % (m, STROKE, SW))
    s += '<rect x="58" y="112" width="84" height="12" fill="%s" stroke="%s" stroke-width="3.5"/>' % (a, STROKE)
    if gear == "blade":
        # 暗影武者·刃：兜帽 + 横太刀 + 一道寒光
        s += ('<path d="M100 44 C78 44 66 66 66 86 L134 86 C134 66 122 44 100 44 Z" '
              'fill="%s" stroke="%s" stroke-width="%.1f" stroke-linejoin="round"/>' % (d, STROKE, SW))
        s += '<ellipse cx="100" cy="74" rx="16" ry="12" fill="#20161F"/>'
        s += '<circle cx="94" cy="74" r="4" fill="%s"/><circle cx="106" cy="74" r="4" fill="%s"/>' % (a, a)
        s += ('<path d="M40 148 Q100 108 168 96" fill="none" stroke="%s" stroke-width="%.1f" stroke-linecap="round"/>'
              % (a, SW + 2))
        s += '<line x1="40" y1="148" x2="30" y2="156" stroke="%s" stroke-width="7" stroke-linecap="round"/>' % d
    else:
        # 无头骑士：颈上悬浮空盔 + 长枪 + 盔缨鬼火
        s += ('<path d="M66 76 A34 34 0 0 1 134 76 Z" fill="%s" stroke="%s" stroke-width="%.1f" stroke-linejoin="round"/>'
              % (d, STROKE, SW))
        s += '<rect x="70" y="52" width="60" height="22" rx="9" fill="#20161F" stroke="%s" stroke-width="4"/>' % STROKE
        s += stroke_eyes(100, 62, 16, 13, 8, a)
        s += ('<path d="M100 20 C112 26 114 40 104 44 L96 44 C86 40 88 26 100 20 Z" fill="%s" stroke="%s" stroke-width="4.5"/>'
              % (a, STROKE))
        s += '<line x1="150" y1="176" x2="150" y2="74" stroke="%s" stroke-width="7" stroke-linecap="round"/>' % d
        s += ('<path d="M150 74 L138 58 L150 44 L162 58 Z" fill="%s" stroke="%s" stroke-width="4.5" stroke-linejoin="round"/>'
              % (a, STROKE))
    return s


def arch_void_demon(m, d, a):
    """虚空恶魔：犄角 + 蝠翼 + 幽光竖瞳"""
    s = shadow(rx=58)
    # 蝠翼
    s += ('<path d="M58 92 L18 66 L30 104 L16 118 L44 128 Z" fill="%s" stroke="%s" stroke-width="5" stroke-linejoin="round"/>' % (d, STROKE))
    s += ('<path d="M142 92 L182 66 L170 104 L184 118 L156 128 Z" fill="%s" stroke="%s" stroke-width="5" stroke-linejoin="round"/>' % (d, STROKE))
    # 躯干
    s += ('<path d="M100 74 C74 78 60 112 56 170 L144 170 C140 112 126 78 100 74 Z" '
          'fill="%s" stroke="%s" stroke-width="%.1f" stroke-linejoin="round"/>' % (m, STROKE, SW))
    # 头 + 双犄角
    s += '<circle cx="100" cy="62" r="26" fill="%s" stroke="%s" stroke-width="%.1f"/>' % (d, STROKE, SW)
    s += '<path d="M80 44 C66 30 64 18 72 10" fill="none" stroke="%s" stroke-width="8" stroke-linecap="round"/>' % d
    s += '<path d="M120 44 C134 30 136 18 128 10" fill="none" stroke="%s" stroke-width="8" stroke-linecap="round"/>' % d
    # 幽光竖瞳
    s += '<ellipse cx="91" cy="60" rx="6" ry="9" fill="%s"/><ellipse cx="109" cy="60" rx="6" ry="9" fill="%s"/>' % (a, a)
    s += '<rect x="89.5" y="55" width="3" height="10" rx="1.5" fill="#20161F"/>'
    s += '<rect x="107.5" y="55" width="3" height="10" rx="1.5" fill="#20161F"/>'
    s += ('<path d="M88 76 L96 70 L104 76 L112 70" fill="none" stroke="%s" stroke-width="4" stroke-linecap="round"/>' % STROKE)
    return s


def arch_shadow_lord(m, d, a):
    """影之魔王·萨尔加斯（Boss）：王冠犄角 + 斗篷 + 胸口暗影核"""
    s = shadow(rx=84, cy=182, alpha=0.30)
    s += '<rect x="54" y="150" width="34" height="40" rx="8" fill="%s" stroke="%s" stroke-width="5"/>' % (d, STROKE)
    s += '<rect x="112" y="150" width="34" height="40" rx="8" fill="%s" stroke="%s" stroke-width="5"/>' % (d, STROKE)
    # 斗篷
    s += ('<path d="M100 40 C60 46 40 108 34 176 L166 176 C160 108 140 46 100 40 Z" '
          'fill="%s" fill-opacity="0.9" stroke="%s" stroke-width="%.1f" stroke-linejoin="round"/>' % (d, STROKE, SW))
    s += ('<rect x="40" y="66" width="120" height="90" rx="18" fill="%s" stroke="%s" stroke-width="%.1f"/>'
          % (m, STROKE, SW))
    # 肩刺
    s += ('<path d="M44 66 L22 34 L54 58 Z" fill="%s" stroke="%s" stroke-width="5" stroke-linejoin="round"/>' % (d, STROKE))
    s += ('<path d="M156 66 L178 34 L146 58 Z" fill="%s" stroke="%s" stroke-width="5" stroke-linejoin="round"/>' % (d, STROKE))
    # 头 + 王冠犄角
    s += '<rect x="74" y="24" width="52" height="46" rx="12" fill="%s" stroke="%s" stroke-width="%.1f"/>' % (d, STROKE, SW)
    s += '<path d="M74 30 C56 22 52 8 62 0" fill="none" stroke="%s" stroke-width="9" stroke-linecap="round"/>' % a
    s += '<path d="M126 30 C144 22 148 8 138 0" fill="none" stroke="%s" stroke-width="9" stroke-linecap="round"/>' % a
    s += '<rect x="82" y="40" width="36" height="12" rx="6" fill="%s"/>' % a
    s += '<circle cx="90" cy="46" r="4" fill="#FFFFFF"/><circle cx="110" cy="46" r="4" fill="#FFFFFF"/>'
    # 胸口暗影核 + 环绕暗焰
    s += '<circle cx="100" cy="112" r="22" fill="%s" stroke="%s" stroke-width="5"/>' % (a, STROKE)
    s += '<circle cx="100" cy="112" r="10" fill="%s"/>' % d
    s += layered_arcs(100, 112, [30, 40], a, 4, sweep=300, start=120)
    return s


# --------------------------------------------------------------------------- 规格表
# 键 = 文件名，值 = (原型, 元素, 装备变体)
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
    # 第二章《机械迷城》：机械 + 符文两大谱系（共 17 只）
    ("mob_mech_spider",        "mech_spider",  "earth", None),
    ("mob_clockwork_soldier",  "mech_soldier", "wind",  "infantry"),
    ("mob_repair_dog",         "mech_dog",     "light", None),
    ("mob_steam_archer",       "mech_soldier", "fire",  "archer"),
    ("mob_heavy_gear_guard",   "mech_guard",   "earth", "heavy"),
    ("mob_energy_capacitor",   "energy_node",  "wind",  "capacitor"),
    ("mob_steam_gunner",       "mech_soldier", "fire",  "gunner"),
    ("mob_supply_cart",        "mech_support", "earth", None),
    ("mob_ancient_gargoyle",   "rune_statue",  "dark",  "gargoyle"),
    ("mob_ancient_runemaster", "rune_statue",  "dark",  "runemaster"),
    ("mob_rune_core",          "energy_node",  "light", "rune_core"),
    ("mob_steam_mgner",        "mech_soldier", "fire",  "mgner"),
    ("mob_tower_core",         "energy_node",  "earth", "tower"),
    ("mob_auto_shield_guard",  "mech_guard",   "light", "shield"),
    ("mob_energy_relay",       "energy_node",  "wind",  "relay"),
    ("mob_rune_priest",        "rune_statue",  "dark",  "priest"),
    ("mob_mech_colossus",      "mech_boss",    "fire",  None),
    # 第三章《深渊暗界·影之迷宫》：暗系谱系（共 13 只）
    ("mob_shadow_spiderling",  "mech_spider",  "dark",  None),
    ("mob_void_mage",          "puppet",       "dark",  None),
    ("mob_bone_shield",        "guard",        "dark",  None),
    ("mob_cursed_scarecrow",   "scarecrow",    "dark",  None),
    ("mob_night_archer",       "archer",       "dark",  None),
    ("mob_headless_knight",    "shadow_knight","dark",  "knight"),
    ("mob_night_assassin",     "archer",       "dark",  None),
    ("mob_soul_priest",        "rune_statue",  "dark",  "priest"),
    ("mob_void_demon",         "void_demon",   "dark",  None),
    ("mob_shadow_blade",       "shadow_knight","dark",  "blade"),
    ("mob_cedric_guardian",    "ruin",         "earth", None),
    ("mob_katherine_judge",    "rune_statue",  "light", "runemaster"),
    ("mob_shadow_lord",        "shadow_lord",  "dark",  None),
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
    "mech_spider": arch_mech_spider,
    "mech_soldier": arch_mech_soldier,
    "mech_guard": arch_mech_guard,
    "mech_dog": arch_mech_dog,
    "mech_support": arch_mech_support,
    "energy_node": arch_energy_node,
    "rune_statue": arch_rune_statue,
    "mech_boss": arch_mech_boss,
    "scarecrow": arch_scarecrow,
    "shadow_knight": arch_shadow_knight,
    "void_demon": arch_void_demon,
    "shadow_lord": arch_shadow_lord,
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
        print("%d 只怪物图标齐备：%s" % (len(SPECS), out_dir))
        return 0

    os.makedirs(out_dir, exist_ok=True)
    for name, arch, elem, gear in SPECS:
        main_c = ELEM_COLOR[elem]
        dark_c = mix(main_c, 0.34, "#2A1F17")
        accent_c = mix(main_c, 0.62)
        fn = ARCH[arch]
        # 带变体的原型（goblin / mech_soldier / …）多接一个 gear 参数，
        # 其余原型只收三色；按参数个数统一路由，不必再逐个特判。
        if len(inspect.signature(fn).parameters) >= 4:
            body = fn(main_c, dark_c, accent_c, gear)
        else:
            body = fn(main_c, dark_c, accent_c)
        svg = TEMPLATE % (name, body)
        path = os.path.join(out_dir, name + ".svg")
        with open(path, "w", encoding="utf-8") as f:
            f.write(svg)
        print("写出 %s  (%d 字节)" % (os.path.relpath(path, root), len(svg)))
    print("完成：%d 只" % len(SPECS))
    return 0


if __name__ == "__main__":
    sys.exit(main())
