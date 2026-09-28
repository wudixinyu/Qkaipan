Typical workflow:
- `python tools/init_game_db.py [--force] [--demo] [--verify]` to build the SQLite config + player databases.
- `Godot --headless --path <project> --script res://tools/build_<scene>.gd` to regenerate `res://scenes/<scene>.tscn` from `res://data/game_data.json`.
- `Godot --headless --path <project> --script res://tools/smoke_<system>.gd` to run smoke suites (exit code 0 = pass).
- `Godot --path <project> --resolution 1920x1080 --script res://tools/shot_<scene>.gd [stage_id wait speed skip]` to capture screenshots to `res://shots/` (requires a real window, not headless).