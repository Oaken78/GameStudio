# DevelopmentRoot

Godot 4.7.2 (GDScript) games, one Godot project and one git repo per folder under `games/<name>/`.
Owner: Klas, senior game designer. Explain choices in design terms; prefer boring, readable code.
Godot binary: `$env:GODOT_BIN` (set in .claude/settings.json). Run it through `tools/*.ps1`, never by hand.

## Commands (PowerShell, from the repo root)
- `./tools/verify.ps1 -Game <g> -Tier auto|0|1|2|3`  run the checks; result in `games/<g>/.reports/summary.txt`
- `./tools/test.ps1 -Game <g> [-File test/unit/test_x.gd] [-Test name]`  GUT unit tests, headless
- `./tools/smoke.ps1 -Game <g> [-Scenario name]`  headless scenario run (log scan, metrics)
- `./tools/shots.ps1 -Game <g> [-Scenario name]`  windowed run with screenshots (a game window opens; expected)
- `./tools/import.ps1 -Game <g>`  once per fresh clone or worktree (verify/test call it when `.godot/` is missing)
- `./tools/new-game.ps1 -Name <n>`  scaffold a game from `templates/game-template` (runs `git init`)
- `./tools/game-worktree.ps1 -Game <g> [-Branch b] [-Remove]`  check out a game branch as `games/<g>--<branch>`

## Verification tiers (`-Tier auto` picks from the diff; go up when unsure, never down)
- 0 docs/design only: nothing.  1 one script, no scene: format + parse + unit tests.
- 2 feature, several files, scene or project.godot: 1 + full unit + headless smoke scenarios.
- 3 anything the player sees or feels (shader, UI, art, juice) or a milestone: 2 + screenshots + playtest-critic + code-reviewer.
- Evidence or it did not happen: quote the command and the summary.txt lines. Never say "tests pass" without them.

## Delegation
- Design, GDD, "is this fun": game-designer. Code: gameplay-dev / visuals-dev (own worktree each, max 3 at once).
- Running checks: test-runner. Tier >= 2 diffs: code-reviewer. Tier 3: playtest-critic. Lookups: Explore.
- Plan first for anything beyond a one-sentence diff. /clear between unrelated tasks.

## Godot gotchas
- Never pass `-d` to Godot unattended (an interactive `debug>` prompt hangs the run).
- Engine errors do not change the exit code: trust the log scan in summary.txt, not the exit code alone.
- `--headless` cannot render; screenshots only via `tools/shots.ps1`.
- Never edit `.godot/`, `addons/`, `*.import`, `test/baselines/` (a hook blocks it). Hand-edit `.tscn` only for trivial property changes.
- `games/<g>/design/gdd.md` is the source of truth. A change that alters a design decision appends to its Decisions log in the same commit.

## Git
- Each game is its own repo at `games/<g>`; the root repo (tools, agents, docs, template) ignores `games/`.
  Run game git commands with `git -C games/<g>`. A game branch is checked out as `games/<g>--<branch>`,
  which every tool accepts as `-Game`. Root-only changes commit in the root repo with scope `root|tools|docs`.
- Branches: `worktree-*` (automatic) or `feat|fix|art|docs/<game>-<slug>`. Commits `type(game): summary`; body quotes the tier result.
- Never push, merge or delete branches unless asked. Only the lead edits `design/plan.md` and `project.godot`, on the game's main.

When compacting, keep: modified files, current task id, last verify command and its result.
