# -*- coding: utf-8 -*-
"""apply_gacha.py —— 把抽卡系统（Gacha）的策划配置写回 data/game_data.json

幂等：只覆写 `gacha` 与 `menu.system_entries` 两个键，其余内容原样保留。

    python tools/_inspect/apply_gacha.py

覆盖的策划案条目
----------------
1. 抽卡池分类与概率：常驻英雄池（UR 0.5% / SSR 3.5% / SR 18.0% / R 78.0%）、
   限时活动 UP 池（同品质内 UP 英雄占 50%）、友情池。
2. 保底与继承：小保底 50 抽（连续 49 抽未出 SSR 及以上，第 50 抽必出）、
   大保底 100 抽（连续 99 抽未出当期 UP 英雄，第 100 抽必出）；计数按
   `pity_group` 存取，限时池换代后同组计数继续累计 —— 天然实现「跨期全额继承」。
3. 商业化：单抽（召唤券 ×1 或 绑定钻石 ×160）、十连（券 ×10 或 1600，必得 SR 及以上）、
   心愿水晶商店（每抽 1 点，120 点兑换当期 UP 的 UR / SSR）。

设计约定
--------
* 卡池内容（`pool`）里每一项是 { type: hero | item, id, weight, ... }：
  hero 走 SaveDB.grant_card（重复即升星），item 走材料仓。
  留空则按品质自动收集全部同品质英雄，所以以后加英雄不用改这里。
* 单价 / 保底尺在池上可覆盖全局默认 —— 友情池用公会代币、无保底，就是靠这个。
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
DATA_PATH = os.path.join(ROOT, "data", "game_data.json")

ICON_TICKET = "res://assets/icons/icon_gift.svg"
ICON_GEM = "res://assets/icons/icon_gem.svg"
ICON_STAR = "res://assets/icons/icon_star.svg"
ICON_EARTH = "res://assets/icons/icon_earth.svg"

# 策划案 §2.1 常驻英雄池概率公示
STANDARD_RATES = {"UR": 0.005, "SSR": 0.035, "SR": 0.18, "R": 0.78}

GACHA = {
    "title": "群星召唤",
    "subtitle": "SUMMONING ALTAR",
    "scene": "res://scenes/gacha.tscn",
    "back_button": {
        "text": "返回主界面",
        "sub_text": "BACK",
        "route": "res://scenes/main_menu.tscn",
    },

    # ---- 消耗品定义：券是道具（材料仓），钻石是货币（钱包）----
    "tickets": {
        "basic": {
            "id": "ticket_basic",
            "name": "基础召唤券",
            "icon": ICON_TICKET,
            "color": "#7BE0FF",
        },
        "advanced": {
            "id": "ticket_advanced",
            "name": "高级召唤卷轴",
            "icon": ICON_TICKET,
            "color": "#C08BFF",
        },
    },
    # 全局缺省单价；卡池可用自己的 cost 覆盖
    "cost": {
        "single": {"ticket": 1, "gem": 160},
        "ten": {"ticket": 10, "gem": 1600},
        # 券优先：券够了就不动钻石
        "pay_order": ["ticket", "gem"],
    },
    "gem_currency": "bound_gem",
    "ten_guarantee": {
        "rarity": "SR",
        "label": "必得 SR 及以上",
        "desc": "十连抽中若前 9 抽没有 SR 及以上品质，第 10 抽必定为 SR 或更高。",
    },

    # ---- 心愿水晶（招募商店积分）：每抽 1 点，120 点兑换当期 UP ----
    "crystal": {
        "currency": "wish_crystal",
        "name": "心愿水晶",
        "icon": ICON_GEM,
        "color": "#C08BFF",
        "per_pull": 1,
        "exchange_cost": {"UR": 120, "SSR": 120},
        "desc": "每抽卡 1 次获得 1 点心愿水晶，累积 120 点可在招募商店内指定兑换当期 UP 的 UR / SSR 英雄。",
    },

    # ---- 新号赠送：保证刚进游戏就能抽（否则默认存档 0 券 0 绑定钻石）----
    "new_player_gift": {
        "bound_gem": 1600,
        "ticket_basic": 10,
        "ticket_advanced": 10,
    },

    # ---- 召唤演出（配色 / 时长 / 语音音效钩子）----
    "reveal": {
        "pack_raise_seconds": 0.55,
        "pack_burst_seconds": 0.42,
        "card_stagger": 0.12,
        "card_in_seconds": 0.34,
        # SSR 紫色光柱 / UR 彩虹光柱
        "pillar_colors": {
            "SSR": "#B06BE8",
            "UR": "#FFD45E",
            "default": "#BFE3FF",
        },
        "rainbow": ["#FF6B6B", "#FFB347", "#FFE9A8", "#7BE0A8", "#7BC8FF", "#C08BFF"],
        "shake": {"SSR": 9.0, "UR": 16.0, "seconds": 0.55},
        # 资源缺失即静默跳过；美术 / 音频给图给音后填路径即可生效
        "voice": {"R": "", "SR": "", "SSR": "", "UR": ""},
        "sfx": {"pack": "", "burst": "", "reveal": ""},
        "note": "voice / sfx 为空表示暂无音频资源，界面会跳过播放；填入 res:// 路径即生效。",
    },

    # ---- 概率公示（界面「概率公示」弹层逐条展示，也是合规底线）----
    "rate_notice": [
        "本卡池所有可获取内容与概率均在此公示，抽取结果由随机数决定。",
        "卡池概率为单次抽取的独立概率，历史抽取结果不影响后续概率（保底机制除外）。",
        "保底计数在不同期数的同类型卡池之间全额继承，不会因卡池结束而清空。",
        "每抽卡 1 次获得 1 点心愿水晶，可在招募商店内兑换当期 UP 英雄。",
    ],

    # ---- 保底尺：全局默认，卡池按 pity / pity_group 取用 ----
    "pity": {
        "small": {
            "count": 50,
            "guarantee": "SSR",
            "desc": "连续 49 抽未获得 SSR 及以上品质卡牌时，第 50 抽必定产出 SSR 或 UR。",
        },
        "large": {
            "count": 100,
            "guarantee": "UP",
            "desc": "连续 99 抽未获得当期 UP 英雄时，第 100 抽必定产出现期限定 UP 英雄。",
        },
    },

    "pools": [
        {
            "id": "standard",
            "name": "常驻召唤",
            "subtitle": "STANDARD SUMMON",
            "tag": "常驻",
            "kind": "standard",
            "accent": "#7BE0FF",
            "desc": "全套英雄常驻开放，无当期 UP，抽取结果全池均匀。",
            "ticket": "basic",
            "rates": STANDARD_RATES,
            "pity_group": "standard",
            "pity": {"small": True, "large": False, "inherit": True},
            "featured": ["pyro_girl", "elf_ranger", "holy_priest", "knight_rock"],
            "pool": {
                "UR": [{"type": "hero", "id": "holy_priest", "weight": 1}],
                "SSR": [
                    {"type": "hero", "id": "pyro_girl", "weight": 1},
                    {"type": "hero", "id": "arcane_girl", "weight": 1},
                    {"type": "hero", "id": "shadow_assassin", "weight": 1},
                ],
                "SR": [
                    {"type": "hero", "id": "elf_ranger", "weight": 1},
                    {"type": "hero", "id": "earth_guardian", "weight": 1},
                ],
                "R": [
                    {"type": "hero", "id": "knight_rock", "weight": 4},
                    {"type": "hero", "id": "flame_knight", "weight": 3},
                    {"type": "item", "id": "hero_exp", "name": "英雄经验",
                     "count": 200, "weight": 3, "icon": ICON_STAR},
                    {"type": "item", "id": "break_stone_1", "name": "初级突破石",
                     "count": 3, "weight": 1, "icon": ICON_EARTH},
                ],
            },
        },
        {
            "id": "limited",
            "name": "星辉召唤 · 神圣牧师",
            "subtitle": "LIMITED EVENT BANNER",
            "tag": "限时 UP",
            "kind": "limited",
            "accent": "#C08BFF",
            "desc": "当期 UR【神圣牧师】与 SSR【紫焰少女】获取概率提升，占同品质产出率的 50%。",
            "ticket": "advanced",
            "rates": STANDARD_RATES,
            "pity_group": "limited",
            "pity": {"small": True, "large": True, "inherit": True},
            # 同品质内 UP 占 50%；其余 50% 走同品质非 UP 内容
            "up_rate": 0.5,
            "up": {"UR": ["holy_priest"], "SSR": ["pyro_girl"]},
            "up_note": "特定 UR / SSR 英雄获取概率提升（占同品质卡牌产出率的 50%）。",
            "period": {"start": "2026-09-25", "end": "2026-10-09", "inherit": True},
            "featured": ["holy_priest"],
            "pool": {
                "UR": [{"type": "hero", "id": "holy_priest", "weight": 1}],
                "SSR": [
                    {"type": "hero", "id": "pyro_girl", "weight": 1},
                    {"type": "hero", "id": "arcane_girl", "weight": 1},
                    {"type": "hero", "id": "shadow_assassin", "weight": 1},
                ],
                "SR": [
                    {"type": "hero", "id": "elf_ranger", "weight": 1},
                    {"type": "hero", "id": "earth_guardian", "weight": 1},
                ],
                "R": [
                    {"type": "hero", "id": "knight_rock", "weight": 4},
                    {"type": "hero", "id": "flame_knight", "weight": 3},
                    {"type": "item", "id": "hero_exp", "name": "英雄经验",
                     "count": 300, "weight": 3, "icon": ICON_STAR},
                ],
            },
        },
        {
            "id": "friend",
            "name": "友情召唤",
            "subtitle": "FRIEND SUMMON",
            "tag": "友情点",
            "kind": "friend",
            "accent": "#8FD98F",
            "desc": "消耗公会代币的友情池，不出 UR，适合日常清点数。",
            "ticket": "",
            "cost": {"single": {"currency": "guild_token", "amount": 10},
                     "ten": {"currency": "guild_token", "amount": 100}},
            "rates": {"UR": 0.0, "SSR": 0.01, "SR": 0.15, "R": 0.84},
            "pity_group": "friend",
            "pity": {"small": False, "large": False, "inherit": False},
            "featured": ["elf_ranger", "knight_rock"],
            "pool": {
                "UR": [],
                "SSR": [
                    {"type": "hero", "id": "pyro_girl", "weight": 1},
                    {"type": "hero", "id": "arcane_girl", "weight": 1},
                    {"type": "hero", "id": "shadow_assassin", "weight": 1},
                ],
                "SR": [
                    {"type": "hero", "id": "elf_ranger", "weight": 1},
                    {"type": "hero", "id": "earth_guardian", "weight": 1},
                ],
                "R": [
                    {"type": "hero", "id": "knight_rock", "weight": 4},
                    {"type": "hero", "id": "flame_knight", "weight": 3},
                    {"type": "item", "id": "hero_exp", "name": "英雄经验",
                     "count": 100, "weight": 4, "icon": ICON_STAR},
                ],
            },
        },
    ],

    "shop": {
        "title": "心愿水晶商店",
        "subtitle": "WISH CRYSTAL SHOP",
        "hint": "累积心愿水晶，指定兑换当期 UP 的 UR / SSR 英雄，防止极度非酋体验。",
        "button_text": "兑换",
        "owned_text": "已持有",
        "empty_text": "当前卡池没有可兑换的 UP 英雄",
    },

    # 招募记录最多保留条数（存档侧只留最近这些条，避免存档无限膨胀）
    "history_max": 30,

    # ---- 商业化包装（保留原有条目，按要求补全按钮语义）----
    "monetization": [
        {"id": "first_charge", "desc": "首充赠送强力前排 SSR 卡牌"},
        {"id": "battle_pass", "desc": "战令（通行证）：等级战令与推图战令"},
        {"id": "cosmetic", "desc": "专属卡面装扮 / Q 版潮玩皮肤售卖"},
        {"id": "gacha_pass", "desc": "召唤特权：每日折扣单抽 + 心愿水晶加成"},
    ],
}

# 召集入口与「卡牌」并列，都挂在主界面右侧竖栏的 system_entries 上
SYSTEM_ENTRIES = [
    {
        "id": "gacha",
        "name": "召集",
        "tag": "抽卡 / 水晶商店",
        "icon": "res://assets/icons/icon_gacha.svg",
        "color": "#C08BFF",
        "route": "res://scenes/gacha.tscn",
        "hint": "群星召唤：常驻 / 限时 UP 卡池与心愿水晶商店",
    },
    {
        "id": "cards",
        "name": "卡牌",
        "tag": "编队 / 收藏",
        "icon": "res://assets/icons/icon_cards.svg",
        "color": "#7BE0FF",
        # 有 route 的入口直接切场景；留空才回落到「模块待接入」提示
        "route": "res://scenes/formation.tscn",
        "hint": "查看全部英雄、调整上阵阵容与羁绊",
    },
]

# 心愿水晶是货币，进钱包；与既有 bound_gem / arena_token 同一张表
WISH_CRYSTAL = {
    "name": "心愿水晶",
    "kind": "soft",
    "icon": ICON_GEM,
    "color": "#C08BFF",
}


def main():
    with open(DATA_PATH, "r", encoding="utf-8") as f:
        data = json.load(f)

    data["gacha"] = GACHA
    data.setdefault("menu", {})["system_entries"] = SYSTEM_ENTRIES
    data.setdefault("economy", {}).setdefault("currencies", {})["wish_crystal"] = WISH_CRYSTAL

    with open(DATA_PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")

    total = sum(sum(p["rates"].values()) for p in GACHA["pools"])
    print("[apply_gacha] 已写入 %d 个卡池（概率之和校验 %s）" % (len(GACHA["pools"]), total))
    for p in GACHA["pools"]:
        r = p["rates"]
        print("  · %-10s %s  UR %.1f%% / SSR %.1f%% / SR %.1f%% / R %.1f%%  Σ=%.3f"
              % (p["id"], p["name"], r["UR"] * 100, r["SSR"] * 100,
                 r["SR"] * 100, r["R"] * 100, sum(r.values())))


if __name__ == "__main__":
    main()
