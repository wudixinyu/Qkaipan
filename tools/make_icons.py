"""生成 UI 图标 SVG（全部纯白填充，运行时用 modulate 上色）。

Godot 4 会用 ThorVG 把 SVG 光栅化，所以只用最基础的图元，避免兼容问题。
"""
from pathlib import Path

OUT = Path(r"D:/Godot_v4.7.2-stable_win64.exe/卡片游戏/卡牌大冒险/assets/icons")
OUT.mkdir(parents=True, exist_ok=True)

W = '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 24 24" fill="#ffffff">'
WE = ('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 24 24" '
      'fill="#ffffff" fill-rule="evenodd">')

RING = 'M12 5A7 7 0 1 0 12 19A7 7 0 1 0 12 5ZM12 9A3 3 0 1 1 12 15A3 3 0 1 1 12 9Z'

# Godot 用 ThorVG 光栅化 SVG，实测 fill-rule="evenodd" 不生效 —— 靠它做「挖洞」的
# 图标会变成实心块。所以凡是需要中空/描边的形状，一律改用 stroke 画法。
SW = 'fill="none" stroke="#ffffff" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"'

# 齿轮：外圈描边 + 8 颗短齿
GEAR = ('<circle cx="12" cy="12" r="5.4" fill="none" stroke="#ffffff" stroke-width="3.6"/>'
        + "".join(f'<rect x="10.9" y="1.0" width="2.2" height="4.8" rx="1.1" '
                  f'transform="rotate({a} 12 12)"/>' for a in range(0, 360, 45)))

ICONS = {
    # ---- 顶栏 / 功能入口 ----
    "gear": '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 24 24" fill="#ffffff">'
            + GEAR + "</svg>",
    # 信封：矩形描边 + 折角
    "mail": '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 24 24">'
            '<rect x="2.2" y="5.4" width="19.6" height="13.2" rx="2.4" ' + SW + '/>'
            '<path d="M3.6 7.4L12 13.4L20.4 7.4" ' + SW + '/></svg>',
    "gift": ('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 24 24" fill="#ffffff">'
             '<rect x="1.2" y="6" width="21.6" height="4.4" rx="1.4"/>'
             '<rect x="2.6" y="11" width="18.8" height="11" rx="1.6"/>'
             '<rect x="10.6" y="1.6" width="2.8" height="20.4"/>'
             '<circle cx="7.6" cy="3.6" r="2.6"/><circle cx="16.4" cy="3.6" r="2.6"/></svg>'),
    "tower": ('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 24 24" fill="#ffffff">'
              '<path d="M8.4 22L9.8 8H14.2L15.6 22Z"/>'
              '<rect x="8.2" y="4.6" width="2.4" height="3.4"/>'
              '<rect x="10.8" y="4.6" width="2.4" height="3.4"/>'
              '<rect x="13.4" y="4.6" width="2.4" height="3.4"/>'
              '<rect x="7.4" y="20.4" width="9.2" height="2.2" rx="1"/></svg>'),
    # 迷宫：外框描边 + 内部回形通路
    "maze": '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 24 24">'
            '<rect x="3.2" y="3.2" width="17.6" height="17.6" rx="2.6" ' + SW + '/>'
            '<path d="M7.6 7.4V14.4H14.4V10.4H10.6V12.6" ' + SW + '/></svg>',
    "arena": ('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 24 24" fill="#ffffff">'
              '<g transform="rotate(45 12 12)"><rect x="10.9" y="2" width="2.2" height="14" rx="1"/>'
              '<rect x="8" y="15" width="8" height="2.2" rx="1"/>'
              '<rect x="10.9" y="17" width="2.2" height="5" rx="1"/></g>'
              '<g transform="rotate(-45 12 12)"><rect x="10.9" y="2" width="2.2" height="14" rx="1"/>'
              '<rect x="8" y="15" width="8" height="2.2" rx="1"/>'
              '<rect x="10.9" y="17" width="2.2" height="5" rx="1"/></g></svg>'),
    "gacha": ('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 24 24" fill="#ffffff">'
              '<rect x="6.4" y="6.4" width="11.2" height="15" rx="1.8"/>'
              '<path d="M18.4 1.2L19.5 4.1L22.4 5.2L19.5 6.3L18.4 9.2L17.3 6.3L14.4 5.2L17.3 4.1Z"/>'
              '<path d="M4.6 1.6L5.4 3.8L7.6 4.6L5.4 5.4L4.6 7.6L3.8 5.4L1.6 4.6L3.8 3.8Z"/></svg>'),

    # ---- 货币 / 资源 ----
    # 铜钱：外圈描边 + 中间方孔
    "coin": '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 24 24">'
            '<circle cx="12" cy="12" r="9" ' + SW + '/>'
            '<rect x="9.2" y="9.2" width="5.6" height="5.6" rx="0.8" ' + SW + '/></svg>',
    "gem": '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 24 24" fill="#ffffff">'
           '<path d="M12 1.6L22 8.8L12 22.4L2 8.8Z"/></svg>',
    "stamina": '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 24 24" fill="#ffffff">'
               '<path d="M13.6 1L3.4 13.4H10.4L9.2 23L20 10.2H12.6Z"/></svg>',
    "star": '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 24 24" fill="#ffffff">'
            '<path d="M12 1.6L15.1 8.6L22.6 9.4L17 14.4L18.6 21.8L12 18L5.4 21.8L7 14.4L1.4 9.4L8.9 8.6Z"/></svg>',

    # ---- 卡面三围 ----
    "hp": '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 24 24" fill="#ffffff">'
          '<path d="M12 21.4C4.4 15.9 1.8 12.6 1.8 9C1.8 5.9 4.2 3.9 6.9 3.9C9 3.9 10.8 5.2 12 7.1'
          'C13.2 5.2 15 3.9 17.1 3.9C19.8 3.9 22.2 5.9 22.2 9C22.2 12.6 19.6 15.9 12 21.4Z"/></svg>',
    "atk": '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 24 24" fill="#ffffff">'
           '<path d="M12 0.8L15.2 7.6V14.4H8.8V7.6Z"/>'
           '<rect x="5" y="14.4" width="14" height="3.2" rx="1.2"/>'
           '<rect x="10.4" y="17.6" width="3.2" height="5.6" rx="1.2"/></svg>',
    "def": '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 24 24" fill="#ffffff">'
           '<path d="M12 1.6L20.4 5.2V11.2C20.4 16.4 16.8 20.6 12 22.6'
           'C7.2 20.6 3.6 16.4 3.6 11.2V5.2Z"/></svg>',

    # ---- 元素 ----
    "water": '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 24 24" fill="#ffffff">'
             '<path d="M12 1.6C12 1.6 4.6 10.3 4.6 14.8C4.6 19 7.9 22.4 12 22.4'
             'C16.1 22.4 19.4 19 19.4 14.8C19.4 10.3 12 1.6 12 1.6Z"/></svg>',
    "fire": '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 24 24" fill="#ffffff">'
            '<path d="M12 1.2C15.4 7 18.6 10.4 18.6 14.6C18.6 19.2 15.6 22.8 12 22.8'
            'C8.4 22.8 5.4 19.2 5.4 14.6C5.4 10.4 8.6 7 12 1.2Z"/></svg>',
    "wind": '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 24 24" fill="#ffffff">'
            '<rect x="1.6" y="5" width="12.4" height="2.8" rx="1.4"/>'
            '<rect x="1.6" y="10.6" width="18" height="2.8" rx="1.4"/>'
            '<rect x="1.6" y="16.2" width="9" height="2.8" rx="1.4"/></svg>',
    "earth": '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 24 24" fill="#ffffff">'
             '<path d="M1.6 20.6L8.8 6.6L12.8 13L16 8.6L22.4 20.6Z"/></svg>',
    "light": ('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 24 24" fill="#ffffff">'
              '<circle cx="12" cy="12" r="5.4"/>'
              + "".join(f'<rect x="11" y="0.4" width="2" height="4.4" rx="1" transform="rotate({a} 12 12)"/>'
                        for a in (0, 45, 90, 135, 180, 225, 270, 315)) + "</svg>"),
    "dark": '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 24 24" fill="#ffffff">'
            '<path d="M16.4 1.4A11 11 0 1 0 16.4 22.6A8.6 8.6 0 1 1 16.4 1.4Z"/></svg>',
}

for name, svg in ICONS.items():
    (OUT / f"icon_{name}.svg").write_text(svg, encoding="utf-8")

print(f"wrote {len(ICONS)} icons -> {OUT}")
print(", ".join(sorted(ICONS)))
