---
name: godot-cli
description: Godot 4.7 command-line reference for agents - flags, exit codes, headless limits, GUT CLI options, and the scenario JSON schema used by tools/smoke.ps1 and tools/shots.ps1. Read before composing any Godot command the tools/ scripts do not already cover.
user-invocable: false
---
# Godot 4.7 CLI for agents

Binary: `$env:GODOT_BIN` (the `_console.exe` wrapper; it forwards stdout/stderr and the exit code).
Always prefer `tools/*.ps1`; they add timeouts, log capture and the error scan.

## Flags that matter
- `--headless` = `--display-driver headless --audio-driver Dummy`. No rendering: `get_image()` is empty, screenshots impossible.
- `--path <dir>` project dir. `--import` starts the editor, imports everything, quits (needed once per fresh clone or worktree; `.godot/` is gitignored).
- `--quit-after <frames>` exits after N process frames with exit code 0. `--fixed-fps 60` fixed delta, no real-time sync (runs as fast as possible).
- `-s <script>` run a script extending `SceneTree` or `MainLoop` instead of the main scene. `--check-only -s file.gd` parses only; advisory (false errors with autoloads, issues #78587 #111515).
- `--log-file <abs path>` writes the log; scan this, not console output (the Windows console logger reformats lines).
- `--resolution WxH`, `--position X,Y`, `--disable-vsync`, `--rendering-method forward_plus|mobile|gl_compatibility`, `--rendering-driver d3d12|vulkan|opengl3`.
- Everything after `--` is user args: `OS.get_cmdline_user_args()`.
- Never `-d`: on a parse error it drops into an interactive `debug>` prompt and the run hangs.
- Unknown flags are silently ignored. Exit codes: `SceneTree.quit(code)` is the only way to set one; engine errors stay exit 0.
- Error lines: `ERROR: ...`, `SCRIPT ERROR: ...`, `SHADER ERROR: ...` then `   at: func (file:line)`. Warnings are `WARNING:`.

## GUT 9.7.1 (headless)
`& $env:GODOT_BIN --headless --path <proj> -s res://addons/gut/gut_cmdln.gd -gexit -gjunit_xml_file=res://.reports/junit.xml`
- Selection: `-gdir=res://test/unit,res://test/integration -ginclude_subdirs`, `-gtest=res://test/unit/test_x.gd`,
  `-gunit_test_name=test_name_fragment`, `-gselect=substring`. Use `=` with no spaces. `-gconfig=` skips `.gutconfig.json`.
- Exit 0 all pass, 1 any fail. Pending tests do not count.
- "Some GUT class_names have not been imported" means run `--import` first (the tools do this automatically).

## Scenario JSON (test/scenarios/<name>.json)
Run by the `DevHarness` autoload when Godot receives `-- --scenario=res://test/scenarios/<name>.json --out=<abs dir> [--seed=1234] [--screens=1]`.
```json
{ "scene": "res://scenes/main.tscn", "seed": 1234, "timeout_frames": 3600,
  "steps": [
    {"wait_frames": 60},
    {"assert_node": "Player", "exists": true},
    {"action_press": "ui_right", "frames": 30},
    {"key_tap": "Space", "frames": 2},
    {"mouse_click": [640, 360], "button": "left"},
    {"assert_prop": {"node": "Player", "prop": "position:x", "op": ">", "value": 640}},
    {"expect_signal": {"node": ".", "signal": "level_started", "timeout_frames": 300}},
    {"screenshot": "after_first_room"},
    {"metrics": {"name": "room1", "frames": 300}},
    {"assert_no_errors": true}
  ] }
```
Node paths are relative to the current scene root (`.` is the root itself); absolute `/root/...` also works.
Ops: `==`, `!=`, `>`, `>=`, `<`, `<=`. `screenshot` is skipped under `--headless` (reported, not failed).
Extra steps: `{"set_prop": {"node","prop","value"}}`, `{"call": {"node","method","args"}}`, `{"inject_error": "text"}` (tests only).
Input injection works headless on 4.7.2 (verified by tools/selftest.ps1), so input scenarios run in tier 2.
Screenshot compare RMSE is on a 0-255 scale (identical frames = 0; a 48 px square moved 120 px = 8.8); the
threshold lives in `design/budgets.json` under `screens.rmse_threshold` (default 1.0).
Harness exit codes: 0 ok, 10 assertion failed, 11 engine error counted, 12 timeout, 13 scenario could not load.
The wrapper adds 124 for a process timeout and 125 when a windowed run gave up on the window lock.
Output: `result.json`, `metrics__<name>.json`, `<shot>.png`, `godot.log`.
Top-level `"serial": true` makes smoke run the scenario alone (for a wall-clock number the rule below misses).

## tools/ options (verify, smoke, shots)
- `verify.ps1 -Game <g> -Tier <n>`: full run; `.reports/summary.txt` header records `commit=`, `content=` (tree
  hash) and `tree=clean|dirty|changed`. `-Scenario a,b` (or `none`): scoped run, the tier's tests plus only those
  scenarios, written to `summary-scoped.txt` (never summary.txt). `-CheckFresh`: runs nothing, prints FRESH (exit 0)
  when summary.txt is a PASS at `-Tier` or higher of HEAD's content on a clean tree, else STALE (exit 1).
  `-Jobs n` passes to smoke. The stop gate writes `summary-gate.txt` and skips when summary.txt is FRESH.
- `smoke.ps1 [-Scenario a,b] [-Jobs 3]`: headless, 3 scenarios at a time, each in its own process and folder; then
  the timing-sensitive ones alone: a `metrics` step, an `assert_prop` on `*_ms`, `*_usec`, `*_frames`, `*fps*` or
  `*per_frame*`, a name `perf_*`, `world_stream*` or `frame_cold`, or `"serial": true` (`*_s` and tick counts are
  game time under `--fixed-fps`, so they stay parallel). Output order is the scenario order. `-Jobs 1` = one at a time.
- `shots.ps1 [-Scenario a,b] [-LockTimeoutSec 1800]`: without `-Scenario` only scenarios with a `screenshot` or
  `metrics` step run (the skipped ones are listed in one line); a named scenario always runs.
- Window lock: every windowed Godot launch through the tools (shots, `smoke -Windowed`, `godot.ps1` without
  `--headless`) holds a machine-wide named mutex for one scenario, so windows never fight over the mouse.
  "waited N s for the window lock" is recorded; after `-LockTimeoutSec` the run FAILs. Headless runs never wait.
