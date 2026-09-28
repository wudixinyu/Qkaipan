---
kind: business_term
name: Business Glossary
category: business_term
scope:
    - '**'
---

### 卡牌大冒险
- Definition：Project name / internal title of this Godot card-collection RPG; English surface form used in README headers is PROJECT: CARD ADVENTURE.
- Aliases：CARD ADVENTURE

### 云上浮岛 · 初始之痕
- Definition：Chapter 1 story title and its opening area; the first playable chapter containing all 10 stages currently implemented.
- Aliases：第一章《云上浮岛 · 初始之痕》

### 召集
- Definition：Main-menu right-rail entry that routes to the gacha scene; distinct from `modes` entries because it carries a `route` config field.

### 群星召唤
- Definition：The in-game name of the gacha system (summoning via standard tickets, limited scrolls, or guild tokens across three pools).

### 心愿水晶
- Definition：Gacha pity currency accumulated per pull; 120 points can be exchanged in the recruitment shop for the current UP UR/SSR as a hard floor.

### 编队
- Definition：Pre-battle team-building screen where players select up to 5 heroes onto the 3×3 board, apply filters/sorting/search, manage presets, and confirm stamina spend.

### 羁绊
- Definition：Declarative synergy rules (`cond` + `effect`) evaluated against the active formation; effects multiply into final stats so they affect both UI numbers and actual combat.

### 战力
- Definition：Unified combat-power metric computed by `GrowthCore.power_of` (HP×0.12 + ATK×2.4 + DEF×1.6 + MRES×1.1 + SPD×2.0 + crit×600); single source of truth across selection, formation, and settlement screens.
- Aliases：队伍战力、阵容战力、建议战力

### ATB
- Definition：Active Time Battle turn order: each unit's next action time = elapsed + 1000 / speed; earliest unit acts each tick, making battle deterministic under a fixed seed.

### 祭坛节点
- Definition：Non-combat event node (id 1005) whose blessing is displayed during battle but whose full cost/payoff loop (spend stamina/gold → grant buff) is not yet wired.

### 冒烟测试
- Definition：Headless smoke-test suite run via `--script res://tools/smoke_*.gd`, covering data consistency, battle determinism, formation rules, menu skeleton, and gacha probability — ~1200 assertions total.

### 截图自检
- Definition：Windowed screenshot harness (`tools/shot_*.gd`) that drives scenes and writes visual artifacts to `shots/`; must run with a real window, not headless.
