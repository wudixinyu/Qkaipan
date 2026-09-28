---
kind: logging_system
name: Godot Built-in Logging via print/push_error/push_warning
category: logging_system
scope:
    - '**'
source_files:
    - scripts/game_db.gd
    - scripts/save_db.gd
    - scripts/battle_core.gd
    - tools/build_main_menu.gd
    - tools/shot_main_menu.gd
    - tools/shot_gacha.gd
---

## What system/approach is used

The project does **not** define a custom logging framework, logger class, log-level manager, or structured log sink. Instead, it relies entirely on Godot 4’s built-in output functions:
- `print(...)` — informational / status messages (e.g. config loaded, save created).
- `push_error("[Tag] ...")` — error-level diagnostics (e.g. missing config file, JSON parse failure, file write error).
- `push_warning("[Tag] ...")` — warning-level diagnostics (e.g. stage references a nonexistent monster).

There are no `log/` or `logging/` directories, no singleton logger autoload, and no external logging library.

## Key files and packages

Logging calls are scattered across the same scripts that own the domain logic; there is no centralized logging module:

| File | Role | Example usage |
|---|---|---|
| `scripts/game_db.gd` | Configuration loader | `push_error("[GameDB] 配置表不存在: %s" % DATA_PATH)`, `print("[GameDB] 配置载入完成 v%s…")` |
| `scripts/save_db.gd` | Save/load persistence | `print("[SaveDB] 存档已载入：…")`, `push_error("[SaveDB] 存档写入失败，错误码 %d" % …)` |
| `scripts/battle_core.gd` | Battle core engine | `push_warning("[BattleCore] 关卡 %d 引用了不存在的怪物 %s" % …)`, `_push("环境效果【%s】…")` |
| `tools/build_main_menu.gd` | Headless scene builder | `push_error("[build] 缺少 %s", …)`, `print("[build] 已写出 %s")` |
| `tools/shot_*.gd` | Screenshot automation | `push_error("[shot] 无法加载 %s", …)`, `print("[shot] 已保存 %s …")` |

## Architecture and conventions

1. **No abstraction layer.** Every script calls `print` / `push_error` / `push_warning` directly at the point of interest. There is no `Logger` class, no global log level toggle, and no way to redirect output to a file.
2. **Human-readable tag prefix.** Messages start with a bracketed tag identifying the subsystem: `[GameDB]`, `[SaveDB]`, `[BattleCore]`, `[build]`, `[shot]`. This is the only consistent convention for distinguishing sources in the Godot console.
3. **Structured-ish fields via `%` formatting.** Messages embed key-value-like fragments using Godot string interpolation (`% [stage_id, mob_id]`, `% [profile.player.name, profile.player.level, …]`). They are not machine-parsable structured logs (no JSON, no fixed schema), but they consistently include the most important context variables inline.
4. **Error vs warning vs info split by function choice:**
   - `push_error` is used for fatal/config-load failures, file I/O errors, and tool build failures — things that stop normal flow.
   - `push_warning` is used for recoverable data issues (e.g. a stage referencing a missing monster id).
   - `print` is used for lifecycle milestones (config loaded, save created/written, screenshot saved).
5. **Internal battle log helper.** `battle_core.gd` defines an internal `_push(...)` helper used exclusively inside the battle engine to emit human-readable combat events (environment effects, synergy openings, etc.). It is not exposed outside the file and is not routed through `print`/`push_*` uniformly — it appears to feed the battle debug UI rather than the console.
6. **No log rotation, filtering, or capture.** Output goes straight to Godot’s default console/stdout. Tool scripts (`tools/*.gd`) rely on this stdout when run headless so their progress/error lines can be captured by whatever invokes them.

## Conventions and constraints

- **Observed convention (not enforced by code):** Prefix every diagnostic message with a `[Subsystem]` tag so Godot console output remains readable when multiple autoloads print simultaneously.
- **Observed convention:** Use `push_error` for anything that indicates a broken configuration or failed disk operation; use `push_warning` for data inconsistencies that can be skipped; use `print` for successful completion milestones.
- **Constraint from architecture:** Because there is no central logger, adding a new subsystem means choosing one of the three built-in functions directly — there is no API contract to follow beyond the tag-prefix convention.
- **Constraint from tooling:** The headless build/shot scripts under `tools/` depend on `print` going to stdout; replacing those calls with a custom logger would require ensuring the logger still writes to stdout in headless mode.