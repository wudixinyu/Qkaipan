# -*- coding: utf-8 -*-
"""apply_formation.py —— 把「卡牌选择与编队」的策划配置写回 data/game_data.json

幂等：整个 `formation` 段覆写，其余段落原样保留（json round-trip 已验证无损）。

    python tools/_inspect/apply_formation.py

约定：
  * 段里只放**规则与文案**（上限、克制表、羁绊条件与效果、按钮文字）。
    像素级的布局常量一律写在 tools/build_formation.gd 里 —— 与选关页 / 战斗页同一口径。
  * 羁绊是「条件 + 效果」的声明式规则，运行时由 RealmDB 解释，不在代码里写死组合。
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
DATA_PATH = os.path.join(ROOT, "data", "game_data.json")


FORMATION = {
    "title": "选择你的英雄",
    "subtitle": "组成你的冒险小队",

    # ---------------------------------------------------------- 顶部操作栏
    "top_tabs": [
        {"id": "select", "name": "选择", "hint": "点击卡牌查看战术信息"},
        {"id": "filter", "name": "筛选", "hint": "按品质 / 元素 / 职业过滤英雄"},
        {"id": "sort", "name": "排序", "hint": "调整卡牌陈列与英雄库的顺序"},
    ],
    "search": {
        "placeholder": "搜索英雄名称...",
        "hint": "支持 名称 / 称号 / 职业 / 元素 / 品质",
    },
    "filters": {
        # source 决定候选项从哪张表里取：rarities / elements / roles
        "groups": [
            {"id": "rarity", "name": "品质", "source": "rarities"},
            {"id": "element", "name": "元素", "source": "elements"},
            {"id": "role", "name": "职业", "source": "roles"},
        ],
        "reset_text": "重置",
        "apply_text": "确定",
        "all_text": "全部",
    },
    "sorts": [
        {"id": "default", "name": "默认顺序"},
        {"id": "power", "name": "战力 ↓"},
        {"id": "level", "name": "等级 ↓"},
        {"id": "rarity", "name": "品质 ↓"},
        {"id": "element", "name": "元素"},
        {"id": "name", "name": "名称"},
    ],

    # ---------------------------------------------------------- 编队规则
    "team": {
        "label": "编队棋盘",
        # max_members = 绝对封顶（= 棋盘格数 9）；当前可上阵人数随等级解锁，见 unlock。
        "max_members": 9,
        # 上阵人数按玩家等级解锁：base 起步、每 interval 级 +1、封顶 max、玩家等级封顶 level_cap。
        # 运行时口径：SaveDB.team_max() = GameDB.team_max_for_level(player.level)。
        "unlock": {
            "note": "上阵数量按玩家等级解锁：base 起步，每 interval 级 +1，封顶 max",
            "base": 1, "interval": 10, "max": 9, "level_cap": 100,
        },
        "row_order": ["front", "middle", "back"],
        "columns": 3,
        "hint": "点空位放置 · 点已上阵英雄可下阵",
        "count_text": "上阵 %d/%d",
        "power_label": "队伍战力",
        "power_parts": {"base": "基础", "equip": "装备", "synergy": "羁绊"},
    },
    # ---------------------------------------------------------- 卡牌陈列
    # 与 menu.fan 同构（CardFan 直接吃这块），但站位与缩放另有口径：
    # 编队页下方要让出四栏面板，卡牌整体压扁，选中放大也不能把卡尾压到面板上。
    "fan": {
        "scale": 0.68,
        "spacing_x": 385.0,
        "center_x_offset": 80.0,
        "center_y_offset": 2.0,
        "selected_scale": 1.12,
        "per_index": [
            {"rot_deg": -7.0, "y": 28, "scale": 0.93, "z": 0},
            {"rot_deg": -2.0, "y": -26, "scale": 1.02, "z": 3},
            {"rot_deg": 2.0, "y": -8, "scale": 0.97, "z": 2},
            {"rot_deg": 6.5, "y": 22, "scale": 0.93, "z": 1},
        ],
    },
    # 进场默认看谁：概念稿里高亮的是 SSR，这里也默认落在 SSR 上（缺配置则取列表第一张）
    "default_selected": "pyro_girl",

    "library": {
        "title": "备选英雄库",
        "columns": 2,
        "rows": 3,
        "empty_text": "空位",
        "deployed_tag": "已上阵",
        "empty_result": "没有符合条件的英雄",
        "count_text": "%d / %d 名",
    },

    # ---------------------------------------------------------- 战术面板
    "tactical": {
        "boxes": [
            {"id": "role_counter", "title": "职业克制"},
            {"id": "counter_bonus", "title": "克制加成"},
            {"id": "synergy", "title": "羁绊加成"},
            {"id": "battle_role", "title": "战斗定位"},
        ],
        "empty_text": "—",
        "no_synergy": "当前组合未激活羁绊",
        "synergy_count": "%d 条羁绊生效",
        "no_stage": "未选择关卡",
        "counter_none": "本关无克制目标",
        "counter_format": "%s 克 %s　+%d%% 伤害",
        "synergy_hint_format": "上阵 %d 人可激活",
        "role_sep": " / ",
    },

    # 职业克制链（仅用于「职业克制」框里的箭头展示，与伤害计算无关）
    "role_chain": ["tank", "warrior", "archer", "mage"],

    # 职业对职业的伤害加成提示（按当前关卡敌方职业匹配）
    "role_counters": [
        {"id": "magic_vs_armor", "attacker_roles": ["mage"], "defender_roles": ["tank"],
         "pct": 0.25, "text": "魔法对重装 +25% 伤害"},
        {"id": "blade_vs_armor", "attacker_roles": ["warrior"], "defender_roles": ["tank"],
         "pct": 0.15, "text": "近战对重装 +15% 伤害"},
        {"id": "ranged_vs_armor", "attacker_roles": ["archer"], "defender_roles": ["tank"],
         "pct": 0.20, "text": "远程对重装 +20% 伤害"},
        {"id": "assassin_vs_back", "attacker_roles": ["assassin"],
         "defender_roles": ["healer", "support", "mage", "archer"],
         "pct": 0.25, "text": "刺客突袭后排脆皮 +25% 伤害"},
        {"id": "tank_vs_assassin", "attacker_roles": ["tank"], "defender_roles": ["assassin"],
         "pct": 0.30, "text": "重装拦截刺客 +30% 减伤"},
    ],

    # 战斗定位文案：位置 + 职责
    "role_tactics": {
        "tank":     {"position": "前排承伤",     "duty": "嘲讽控制"},
        "warrior":  {"position": "前排近战输出", "duty": "单体爆发"},
        "mage":     {"position": "中排魔法输出", "duty": "范围破盾"},
        "archer":   {"position": "中排远程输出", "duty": "点杀后排"},
        "assassin": {"position": "后排突袭",     "duty": "斩杀脆皮"},
        "healer":   {"position": "后排治疗",     "duty": "续航驱散"},
        "support":  {"position": "后排辅助",     "duty": "增益控制"},
    },

    # ---------------------------------------------------------- 羁绊
    # cond.type 支持：
    #   role_count       {roles:[role_id], min}        队内命中职业的人数
    #   element_count    {elements:[elem_id], min}     队内命中元素的人数
    #   distinct_elements{min}                         队内不同元素的种类数
    #   rarity_count     {rarities:[R,SR,SSR,UR], min}  队内命中品质的人数
    #   row_count        {row:front|middle|back, min}   队内在该排的人数
    #   member_count     {min}                         上阵总人数
    # effect.stat ∈ hp / atk / def / mres / spd / all；pct 为乘算增幅
    "synergies": [
        {"id": "vanguard", "name": "坚守阵线",
         "cond": {"type": "role_count", "roles": ["tank", "warrior"], "min": 1},
         "effect": {"stat": "def", "pct": 0.10},
         "text": "与前排（重装 / 战士）英雄同时上阵，防御 +10%"},
        {"id": "arcane", "name": "秘法共鸣",
         "cond": {"type": "role_count", "roles": ["mage", "archer"], "min": 2},
         "effect": {"stat": "atk", "pct": 0.08},
         "text": "与输出位（法师 / 游侠）同队 ≥2 人，攻击 +8%"},
        {"id": "dawn", "name": "黎明誓约",
         "cond": {"type": "element_count", "elements": ["light"], "min": 1},
         "effect": {"stat": "hp", "pct": 0.06},
         "text": "队内存在光属性英雄，生命 +6%"},
        {"id": "trinity", "name": "三才阵",
         "cond": {"type": "member_count", "min": 3},
         "effect": {"stat": "all", "pct": 0.05},
         "text": "上阵满 3 人，全属性 +5%"},
        {"id": "rainbow", "name": "五行流转",
         "cond": {"type": "distinct_elements", "min": 3},
         "effect": {"stat": "mres", "pct": 0.12},
         "text": "队内元素 ≥3 种，法抗 +12%"},
        {"id": "full_house", "name": "五方俱备",
         "cond": {"type": "member_count", "min": 5},
         "effect": {"stat": "all", "pct": 0.08},
         "text": "上阵满 5 人，全属性 +8%"},
    ],

    # ---------------------------------------------------------- 快捷编队
    "preset_label": "阵容预设",
    "presets": [
        {"id": "main", "name": "主线队", "seed": ["knight_rock", "pyro_girl", "elf_ranger"]},
        {"id": "pvp", "name": "PVP队", "seed": []},
        {"id": "dungeon", "name": "副本队", "seed": []},
    ],
    "quick_fill": {"text": "一键上阵", "note": "按战力与克制自动补满"},
    "quick_deploy": {"text": "上阵", "note": "放到该英雄的推荐槽位"},
    "quick_remove": {"text": "下阵"},
    "clear_text": "清空",

    # ---------------------------------------------------------- 按钮与场景
    # 体力在哪一步扣：formation（默认，编队页「确认选择」时扣）或 stage_select（选关页扣）。
    # 编队页是准备界面，玩家没出发之前不该已经被扣掉体力 —— 所以默认放在确认选择那一步。
    "spend_stamina_at": "formation",
    "scene": "res://scenes/formation.tscn",
    "confirm_button": {"text": "确认选择", "sub_text": "FORMATION"},
    "back_button": {"text": "返回主界面", "route": "res://scenes/main_menu.tscn"},
    "battle_scene": "res://scenes/battle.tscn",

    "toast": {
        "deployed": "已上阵 %s（%s · 槽位 %d）",
        "removed": "已下阵 %s",
        "team_full": "上阵已满 %d 人，请先下阵",
        "dup": "%s 已在阵中",
        "auto_filled": "一键上阵：%d 人 · 队伍战力 %s",
        "preset_saved": "已把当前阵容保存到「%s」",
        "preset_loaded": "已切换到「%s」（%d 人）",
        "preset_empty": "「%s」还没有阵容，先编好队再切换",
        "no_stamina": "体力不足：需要 %d 点，当前 %d 点\n（%s 后恢复 1 点）",
        "team_empty": "至少上阵 1 名英雄再出发",
        "no_stage": "还没有选择关卡，先回选关页挑一关",
        "ready": "阵容就绪 · 进入关卡 %d · 队伍战力 %s",
        "synergy": "羁绊生效：%s",
        "no_result": "没有符合条件的英雄",
        "board_locked": "该槽位已被占用",
        "slot_locked": "该槽位尚未解锁 · Lv.%d 可上阵 %d 人",
        "no_select": "先在卡牌陈列或英雄库里选一张卡",
    },
}


def main():
    with open(DATA_PATH, "r", encoding="utf-8") as f:
        data = json.load(f)

    data["formation"] = FORMATION

    with open(DATA_PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")

    f = data["formation"]
    print("[apply_formation] 已写入 formation 段：%d 项预设 / %d 条羁绊 / %d 条职业克制"
          % (len(f["presets"]), len(f["synergies"]), len(f["role_counters"])))


if __name__ == "__main__":
    main()
