# 卡牌大冒险 —— 项目长期约定

## 数据层（三级，全部 JSON，`data/db/*.db` 是废弃遗留物）
- `GameDB`（autoload）读 `res://data/game_data.json`，只读配置；新增查询接口都往这里加。
- `SaveDB`（autoload）读写 `user://save.json`；装备空槽写 `""` 表示显式卸下。
  编队（`team`）与 3 栏阵容预设（`team_presets` / `team_active_preset`）也归它，
  写入路径统一过 `normalize_team()`（同名去重 / 槽位 1..9 / 同槽位去重 / 超员截断）。
- `RealmDB`（autoload）由配置 + 存档推导属性与战力，`battle_power()` 是全场统一口径；
  `roster_of()` 是编队构造的唯一入口（缺卡回落展演态），羁绊也在这里结算。
- `StaminaSys`（autoload）体力，1 点 / 300 秒、离线按时间戳结算。
- `GachaSys`（autoload）抽卡内核：掷点 / 保底 / 扣费 / 发卡 / 心愿水晶 / 兑换。
- `BattleCtx`（autoload）单场战斗上下文（本场关卡、祭坛增益、固定种子），不落盘。

## 抽卡口径（GachaSys）
- **决策全是纯函数**：`pick_rarity(概率表, 品质桶有效性, 保底下限, roll)` 与
  `choose_entry(品质桶, UP名单, up_rate, branch_roll, pick_roll)` 的 roll 从参数进 → 边界可断言。
- **品质桶按 `rarities.order` 升序累加**（R→UR），`min_rarity` 保底是在「不低于它」里重新归一（UR 概率不冻结）；
  空桶（配置写空）权重为 0 不参与。掷点上限 0.999999，别用 1.0。
- **保底按 `pity_group` 分组存档**（不跟卡池 id 绑定）→ 限时池换代复用同组即「跨期全额继承」；
  大保底压过小保底；十连保底在最后一抽兜底；`use_pity=false` 得纯基础概率、`free=true` 不落盘。
- **扣费券优先**，券不够整份才整体回落绑定钻石（不拆混用）；一次 pull 只落一次盘
  （`add_currency/add_material/grant_card` 都有 save 标志）。重复卡升星但星级钳制 `star_max`。
- **卡面**：单抽 336×520 复用 CardView；十连 2×5 用紧凑贴纸卡（CardView 三围条在窄卡上必被卡框切掉）；
  角标横排在卡**上沿之外**；缺立绘走占位（品质色底+元素徽记）。
- **演出**：`animate=false` 直接落静止态（测试用）；粒子贴图 256px 必须 scale 0.02-0.075；
  `Color(str(Color))` 会报 Invalid color name。

## 编队口径
- 界面流转：`stage_select` 点「进入关卡」→ **只校验体力、不扣** → `formation` →
  点「确认选择」才扣体力 + 写档 + 进 `battle`。扣减时机由 `formation.spend_stamina_at` 控制。
- 队伍总战力 = Σ `battle_power(卡牌最终属性)` = 基础战力 + 羁绊加成；
  界面读 `RealmDB.formation_report()`，战斗读 `RealmDB.roster()`，内部共用 `roster_of()`。
- **羁绊是声明式规则**（`formation.synergies` 的 `cond` + `effect`/`effects`），
  `apply_synergies()` 会把增幅**乘进 hp/atk/def/mres/spd**，所以界面加成战斗里真的生效。
- 预设切换：切走前由**界面**把工作副本 `save_preset` 回旧槽位，再 `switch_preset` 载新预设
  （`SaveDB` 看不到界面手里的 `_team`，替它存会用旧值覆盖）。
- 3x3 棋盘格子位置直接由 `combat.board.slot_to_cell` 反推，UI 不做第二套编号。
- **CardFan 左右滚动**：内容宽过陈列区自动启用（`scrollable()`，主界面 4 卡自动失效）。
  拖拽武装要求按下点在条带内且 hover 链能找到 CardFan（防弹层误滚）；CardView 的
  hover 回落基准 `_base_pos` 由 `set_base_pos()` 随滚动同步。点选走 `focus_card()`
  （端点卡只能贴边），进场 default_selected 不回中（`formation._boot_ready` 门槛）。
  `make_input_local()` 返回基类 InputEvent，取 position 必须 `as InputEventMouse`。

## 英雄图鉴与 GDD 数值口径
- 角色共 8 名（knight_rock / pyro_girl / elf_ranger / holy_priest +
  arcane_girl 许知夏 / shadow_assassin 影刃 / earth_guardian 托尔 / flame_knight 亚瑟）。
  编队卡库唯一入口 = `RealmDB.all_heroes()`（逐 `GameDB.characters()`，缺卡回落展演态）；
  主界面陈列仍走 `showcase_lineup()`（读 `menu.demo_lineup` 4 张）。
- **图鉴信息**挂在 `characters[].codex`（hero_name / class / battle_role / attack / ult /
  passive / gdd_panel_lv30），战斗只读 base/growth/skill；GameDB 侧接口：
  `codex_of()` / `hero_name()` / `full_name()` / `card_battle_role()` / `class_of()` / `class_matrix()`。
- **GDD 面板 = Lv.30 未计星级的基础属性**；base/growth 拆分 = 面板 × 同稀有度参照卡的
  base 占比（脚本头注释有 REF_RATIO 说明）。改 GDD 数值后重跑
  `tools/_inspect/apply_gdd_codex.py`（幂等）。
- **羁绊 schema（向后兼容）**：`cond.type` 支持 `char_ids`（指定英雄组合，min 缺省 = 全到齐）；
  效果用 `effects` 数组逐条声明，`mode` 三类——`mul`（pct 乘算，stat=all 五维全吃）、
  `add`（crit 加算）、`battle`（`open_energy` 点数 / `open_shield` 最大生命比 / `elem_dmg`
  元素伤害比，target 支持 `row:front` 定向）。battle 级效果由 `apply_synergies` 写进
  unit 的 `synergy_buffs` → `battle_core._apply_synergy_open()` 开局兑现，界面战力=战斗实况。
- 新羁绊 id：cloud_vanguard / nature_guard / light_dark_weave / all_element_resonance。
- `resolve_targets` 认 `back_lowest_hp` 与 `lowest_hp_back` 两种语序（曾只认后者，
  `enemy_back_lowest_hp` 会被静默降级成打前排）；敌方全体 = `enemy_all_foes`。
- `free_slot_for` 推荐位被占时**先在推荐排内**找空位再跨排兜底（法师不上前排）。
- 新英雄立绘流水线：AI 出图 → `tools/_inspect/prepare_new_heroes.py`
  （LUMA_MIN=216 / CHROMA_MAX=18 的边界洪泛抠图，阈值松了会留灰底）→ 900 高 RGBA → headless --import。

## 场景程序化构建（不用 MCP build_godot_scene 覆盖既有场景）
`tools/build_<scene>.gd`（extends SceneTree）→ `scenes/<scene>.tscn`。
构建脚本不依赖 autoload，直接读 JSON；动态内容只留空容器，运行时由界面脚本填充。

## 主界面右栏入口
- `modes` = **占位玩法模式**（无限之塔 / 迷宫 / 竞技场 / 巅峰对决），点了弹「模块待接入」。
- `menu.system_entries` = **已做好的系统入口**，带 `route`，点了真切场景；目前「召集」→ 抽卡页、「卡牌」→ 编队页。
- 两组共用竖栏外观，中间画一条分隔线；加新入口只追加配置，不用改代码。
- 按钮名前缀 `Mode_` / `Sys_` 决定绑哪个处理器（`_on_mode_pressed` / `_on_system_pressed`）。

## 关卡配置口径
- 第一章全 10 关在 `adventure.chapter_stages.list`（含敌方槽位、机制、奖励、配色 theme）。
- 敌方强度 = 怪物基础面板 × 关卡 `power_scale`，scale 由 `tools/_inspect/apply_chapter1.py`
  按「建议战力 × difficulty」反解，改战力后必须重跑该脚本。
- 选关页 `adventure.select_map.nodes` 只有 3 个节点（有背景锚点的那些），
  其余关卡从战斗侧可达但地图上暂时没有节点。

## 结算与进度口径
- 星数的**唯一真源**是 `progress.stage_stars[str(sid)]`，由 `SaveDB.record_stage_stars()` 写入且**只升不降**；
  选关地图优先读它，`select_map.nodes[].demo_stars` 只是「无记录时」的展演回落值。
- 星级规则在 `adventure.star_rating`（`max` + `rules`：win / wipe / hp_ratio / max_actions / no_death），
  `battle.gd._rate_stars()` 只判定、不改口径；撤退 / 失败 0 星，不写档。
- 材料 = `progress.pending_items`（所有非货币奖励的唯一落点，背包未做）；货币仍走 `SaveDB.wallet`。
  「持有量 / 种类 / 件数 / 累计 ★ / 场次」的统计口径统一在 `SaveDB`，结算面板与选关页读同一份，不各自算。
- 结算面板尺寸（`ResultPanel` 800x790、奖励区 480x500）与选关页 footer 位置都写在 build 脚本里，
  要改就改 `tools/build_*.gd` 后重建，别手改 .tscn。

## 验证流程（每轮收尾都跑）
```bash
G="D:/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe"
"$G" --headless --path . --script res://tools/smoke_battle.gd        # 317
"$G" --headless --path . --script res://tools/smoke_formation.gd     # 252
"$G" --headless --path . --script res://tools/smoke_gacha.gd         # 216
"$G" --headless --path . --script res://tools/smoke_stage_select.gd  # 140
"$G" --headless --path . --script res://tools/smoke_main_menu.gd     # 151
"$G" --headless --path . --script res://tools/smoke_adventure_data.gd# 114
"$G" --headless --path . --script res://tools/smoke_fan_scroll.gd    # 18  CardFan 左右滚动内核
"$G" --headless --path . --quit-after 120                            # 常规启动回归
"$G" --path . --resolution 1920x1080 --script res://tools/shot_battle.gd -- <关卡id> <等待秒> <倍速> [skip]
# 第 4 个参数给 skip：加载后直接跳结算，产出 shots/battle_result.png
# 另四页：shot_main_menu.gd / shot_stage_select.gd / shot_formation.gd / shot_gacha.gd
# shot_gacha 的 mode：page / reveal1 / reveal10 / pillar_ssr / pillar_ur / rate / shop
#   pillar_ssr/pillar_ur 先用 SaveDB.set_pity 把保底计到 49/99 把光柱逼出来；shot 会 _top_up 补资源
# shot_formation_scroll.gd：push_input 注入真实拖拽，产出 shots/formation_scroll_{before,after}.png
```

> 截图脚本会真实写档（评星 / 领奖 / 编队 / 抽卡扣券）。跑之前先备份
> `%APPDATA%/Godot/app_userdata/卡牌大冒险/save.json`，跑完还原。

## Godot 4.7 硬性注意
- `var x := dict.get(...)` 是**编译错误**（Variant 无法推断），必须显式标注类型。
- `%唯一名` 在表达式里的静态类型是 `Node`：`var x := %Foo` 之后访问 `position` / `visible`
  会编译失败，要写 `var x: Control = %Foo`。
- `--script` 模式的入口脚本看不到 autoload 全局名，要走 `get_node_or_null("/root/X")` + `.call()`。
- `custom_minimum_size` 是尺寸**下限**：按比例缩的血条必须先把 `.x` 归零。
- `UI.place()` 会写 `custom_minimum_size`；`UI.fill()` 必须显式清四个 offset。
- 运行期拼的正文要防溢出：容器 `clip_contents = true` + 按宽度估算截断 + 长文案挂 tooltip。
- 卡牌选中放大走 `CardView._rest_scale()`（扇形排布与 hover 补间共用），别在界面里再写 scale。
