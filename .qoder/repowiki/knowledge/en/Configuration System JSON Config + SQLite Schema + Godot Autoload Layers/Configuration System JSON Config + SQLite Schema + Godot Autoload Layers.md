---
kind: configuration_system
name: 'Configuration System: JSON Config + SQLite Schema + Godot Autoload Layers'
category: configuration_system
scope:
    - '**'
source_files:
    - project.godot
    - scripts/game_db.gd
    - scripts/save_db.gd
    - scripts/realm_db.gd
    - scripts/stamina.gd
    - data/game_data.json
    - data/db/schema.sql
    - tools/init_game_db.py
---

## Approach

The project uses a **three-layer configuration system** built on top of Godot 4.7.2:

1. **Engine config** — `project.godot` (Godot's native INI-style file) holds engine-level settings (window size, main scene, autoloads).
2. **Static game data** — `data/game_data.json` is the single source of truth for all策划 (designer-facing) configuration: economy, elements, combat formulas, rarities, characters, gacha pools, stamina rules, formation rules, adventure map nodes, monster tables, etc.
3. **SQLite schema** — `data/db/schema.sql` defines two physical databases (`game_cfg.db` = read-only static config, `player_save.db` = writable player state), split at build time by `@db:` markers via `tools/init_game_db.py`.
4. **Player save** — `user://save.json` (managed by SaveDB) is the runtime persistent profile; it is NOT the canonical design doc but mirrors the schema's intent.

There are no `.env`, YAML, TOML, or feature-flag files. Configuration is purely JSON + SQL schema + Godot autoload wiring.

## Key Files and Packages

- `project.godot` — declares six autoload singletons that form the config/runtime layer: `GameDB`, `SaveDB`, `RealmDB`, `StaminaSys`, `GachaSys`, `BattleCtx`.
- `scripts/game_db.gd` — **Config layer (read-only)**. Loads `res://data/game_data.json` in `_ready()`, exposes typed query methods (`elements()`, `characters()`, `gacha_pools()`, `formation()`, `adventure()`, `stamina_cfg()`, `economy()`). Comment explicitly states its sole responsibility: "把 res://data/game_data.json 读进内存，并提供类型化的查询接口。不持有任何玩家存档状态，不写盘。"
- `scripts/save_db.gd` — **Persistence layer**. Reads/writes `user://save.json`. Defines default profile shape, migration helpers (`_migrate_gacha`), team normalization, wallet/materials/gacha state accessors. Enforces slot-count invariant for equipment arrays.
- `scripts/realm_db.gd` — **Runtime derived layer**. Computes final stats from SaveDB + GameDB, evaluates synergies declaratively from `formation.synergies`, produces roster/battle_power/counter_report. Does not write disk.
- `scripts/stamina.gd` — Time-based stamina system reading `GameDB.stamina_cfg()` and persisting to `SaveDB.profile["stamina"]`.
- `data/game_data.json` — ~3500-line JSON document with sections: `meta`, `economy`, `elements`, `combat`, `roles`, `rarities`, `characters`, `gacha`, `stamina`, `menu`, `formation`, `adventure`, `monsters`.
- `data/db/schema.sql` — Single-file dual-database schema with `@db: cfg` / `@db: player` markers, foreign-key constraints only within the player DB, CHECK constraints on enums, JSON columns validated with `json_valid()`.
- `tools/init_game_db.py` — Build tool referenced by schema comments to split the SQL into two `.db` files.

## Architecture and Conventions

### Layered separation of concerns

The codebase enforces a strict three-tier split documented in each module's header comment:

| Layer | File | Responsibility |
|---|---|---|
| Config (read-only) | `GameDB` | Load & expose `game_data.json` as typed getters |
| Persistence (stateful) | `SaveDB` | Read/write `user://save.json`, normalize, migrate |
| Runtime derived | `RealmDB` | Compute stats/synergies from SaveDB + GameDB |

Comments repeatedly reiterate this contract, e.g. GameDB: "所有模块通过它读取策划配置"; RealmDB: "不写盘，不读配置以外的外部资源"; StaminaSys: "唯一职责：维护体力值与恢复计时".

### Data ownership model

- Design/config data lives in `data/game_data.json` and is consumed read-only through `GameDB`.
- Player state lives in `user://save.json` and is accessed exclusively through `SaveDB`.
- Cross-cutting computed values (final stats, synergy buffs, battle power) live in `RealmDB`.
- The SQLite schema under `data/db/` is a **design-time artifact** (the canonical relational model); the running game currently persists to JSON, not SQLite. The schema comments explain why: "配置热更新只替换 game_cfg.db，完全不动玩家存档" and cross-database FK integrity is enforced at the application layer.

### Default-value fallback pattern

Every accessor follows the same shape: read from the section, return `{}` or `[]` if missing, never crash. Examples:

```gdscript
func section(key: String) -> Dictionary:
    var v: Variant = data.get(key, {})
    return v if typeof(v) == TYPE_DICTIONARY else {}
```

This makes the JSON schema intentionally lenient — missing fields fall back to sensible defaults (e.g. `team_max()` returns `maxi(1, int(...))`, `star_max()` returns `maxi(1, ...)`).

### Gacha config convention

Gacha behavior is fully driven by `game_data.json` sections `gacha.pools`, `gacha.rates`, `gacha.pity`, `gacha.cost`, `gacha.tickets`, `gacha.shop`, `gacha.new_player_gift`. Probabilities are normalized at runtime (`gacha_rates`) so even an incomplete table won't index out of bounds. Pity groups allow cross-period carryover (`pity_group`).

### Team/formation conventions

Team composition is governed by `formation.team.max_members` (default 5) and `formation.team.columns` (default 3 → 9 slots). `SaveDB.normalize_team` enforces three hard rules stated in its docstring: "上限 team_max()、同名 hero_id 不可重复、槽位必须是 1..9". Equipment slots are always padded to `GameDB.equipment_slot_count()` with empty strings representing explicit unequip.

### Synergy system

Synergies are declared entirely in `formation.synergies` as condition+effect pairs. `RealmDB.synergy_matches` supports condition types: `member_count`, `row_count`, `role_count`, `element_count`, `rarity_count`, `char_ids`, `distinct_elements`. Effects support modes `mul` (multiplicative stat boost), `add` (for rates like crit), and `battle` (open_energy/open_shield/elem_dmg passed to combat core).

### Stamina persistence

Stamina is stored as `{ value, accounted_at }` in `SaveDB.profile["stamina"]`. Recovery is computed offline using Unix timestamps: `apply_offline()` calculates gained points from `(now - accounted_at) / seconds_per_point`. The timer ticks every second but only persists every 30 seconds to avoid excessive disk writes.

## Conventions and Constraints

- **Single source of truth**: All designer-facing numbers live in `data/game_data.json`; code contains no magic constants for game balance. Verified by scanning `game_db.gd` — every numeric constant is read from `section("...").get(...)` with a default.
- **No environment variables or feature flags**: There is no `.env`, no `ProjectSettings` usage beyond what Godot auto-generates, and no runtime toggle mechanism.
- **Autoload-only global access**: The six autoloads in `project.godot` are the only global entry points; scenes reference them by name (`$GameDB`, `$SaveDB`, etc.) rather than passing references.
- **Schema-driven defaults**: `SaveDB._fill_defaults` recursively merges new keys from `_default_profile()` into existing saves, so adding a new field to the default schema is backward-compatible without migration code.
- **Versioning**: `SAVE_VERSION := 1` in SaveDB and `PRAGMA user_version = 1` in both cfg/player schemas indicate versioned migrations are planned (schema comments describe how they'd work), though no migration logic exists yet beyond `_migrate_gacha`.
- **JSON validity**: The SQLite schema requires all JSON columns to pass `CHECK(json_valid(x))`, enforcing structural integrity at the database level for any future migration to SQLite.
- **Cross-database referential integrity**: Schema comments explicitly state that FK integrity across `cfg` and `player` databases is enforced at the application layer since SQLite cannot enforce FKs across separate files.