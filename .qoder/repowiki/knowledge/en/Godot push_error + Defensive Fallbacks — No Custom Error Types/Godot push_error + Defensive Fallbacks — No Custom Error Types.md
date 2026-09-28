---
kind: error_handling
name: Godot push_error + Defensive Fallbacks — No Custom Error Types
category: error_handling
scope:
    - '**'
source_files:
    - scripts/game_db.gd
    - scripts/save_db.gd
    - scripts/stamina.gd
    - scripts/battle_core.gd
    - tools/build_battle.gd
    - tools/shot_battle.gd
    - tools/shot_formation.gd
    - tools/diag_battle.gd
    - tools/diag_gacha.gd
    - tools/preview_monsters.gd
---

## What system/approach is used

The project does **not** define a custom error type hierarchy, sentinel errors, or exception-style propagation. Instead it follows Godot's built-in conventions:

- **`push_error(...)`** is the primary mechanism for reporting I/O and configuration failures (file open, JSON parse, scene load). It writes to Godot's console/error log; callers typically return `false` / empty dictionaries after logging.
- **Defensive fallbacks** are the main runtime strategy: missing config entries resolve to safe defaults (`{}`, `[]`, `""`, `0`, `1.0`) rather than raising. This keeps the game running even when data is malformed.
- **Signals** (`SaveDB.saved`, `SaveDB.loaded`, `StaminaSys.changed`, `StaminaSys.recovered`) are used to propagate state changes upward instead of returning error codes.
- There is **no `try/catch`**, no `throw`, no `panic/recover`, and no middleware layer — this is a single-process Godot game, not a server.

## Key files and packages

| Area | File | Error-handling behavior |
|---|---|---|
| Config loading | `scripts/game_db.gd` | On missing/invalid `game_data.json`: calls `push_error(...)`, returns `false` from `load_data()`. All downstream getters fall back to `{}` / `[]` via `section()` and `typeof(v) == TYPE_DICTIONARY` checks. |
| Save persistence | `scripts/save_db.gd` | On write failure: `push_error("[SaveDB] 存档写入失败，错误码 %d" % FileAccess.get_open_error())`, then returns. Load path silently falls back to `_default_profile()` and persists it. Includes explicit migration (`_migrate_gacha`) so old save shapes don't crash. |
| Stamina system | `scripts/stamina.gd` | `spend(amount)` returns `false` when insufficient stamina; otherwise mutates in-memory state and persists via `SaveDB.save_profile()`. Offline recovery is additive-only (`apply_offline`), never negative. |
| Battle core | `scripts/battle_core.gd` | Missing monster entry triggers `push_warning` and skips that enemy; combat proceeds with remaining units. Deterministic RNG seeded per battle enables reproducible smoke tests. |
| Tools & headless scripts | `tools/build_battle.gd`, `tools/shot_*.gd`, `tools/diag_*.gd`, `tools/preview_monsters.gd` | Use `push_error` with scoped prefixes (`[build]`, `[shot]`, `[diag]`, `[preview]`) to report build/shot/preview failures during automated runs. |

## Architecture and conventions

1. **Layered separation of concerns**: `GameDB` is read-only config, `SaveDB` is persistence, `BattleCore` is pure logic, `StaminaSys` is time-based state. Errors at one layer do not bubble as exceptions — they are logged and the caller receives a safe default.
2. **Fail-open defaults**: Every config accessor wraps its result in a `if typeof(v) == TYPE_DICTIONARY else {}` or `if v is Array else []` guard. Unknown keys are ignored; unknown IDs return `{}` or `""`. This means a bad row in `game_data.json` cannot crash the game.
3. **Validation before mutation**: `SaveDB.normalize_team()` enforces three hard rules (max team size, unique hero id, slot 1–9) and strips invalid entries before persisting. A parallel `team_errors()` returns human-readable Chinese messages for UI display.
4. **Idempotent saves**: `save_profile()` always writes `version = SAVE_VERSION`; `_fill_defaults()` merges new schema fields into existing profiles without overwriting user data. Old gacha pity keys are migrated once and erased.
5. **Deterministic simulation**: `BattleCore` seeds `RandomNumberGenerator` from an option or `Time.get_ticks_usec()`, so `run_all()` produces identical event streams for the same seed — enabling smoke-test assertions on exact values.
6. **No cross-cutting error middleware**: There is no global try/catch wrapper around `_process`/`_physics_process`. Each subsystem handles its own boundary conditions locally.

## Conventions and constraints

- **I/O failures are reported via `push_error`** and followed by a graceful return value (`false`, empty dict/array). Callers must check return values or treat empty results as "not available".
- **Config lookups never throw**: `GameDB.section(key)` returns `{}` if the key is missing; `character(id)`, `monster(id)`, `gacha_pool(pool_id)` all return `{}` when not found.
- **User-facing validation errors are collected as arrays of strings** (see `team_errors`) rather than raised — suitable for rendering in Godot UI labels.
- **Save schema evolution is handled in-code**: `_fill_defaults`, `_normalize_cards`, `_migrate_gacha` run on load to bridge old profiles to the current shape.
- **Tool scripts prefix every `push_error` with a module tag** (`[build]`, `[shot]`, `[diag]`, `[preview]`) so automated logs can be filtered by subsystem.
- **Battle outcomes use structured events** (`{"t": "end", "winner": ..., "reason": ...}`) returned from `step()`/`run_all()` rather than throwing — the UI consumes the event stream to render animations.