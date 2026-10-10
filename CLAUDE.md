# GameStudio

Godot 4.7.2 (GDScript) games, one Godot project and one git repo per folder under `games/<name>/`.
Owner: Klas, senior game designer. Explain choices in design terms; prefer boring, readable code.
Godot binary: `$env:GODOT_BIN` (set in .claude/settings.json). Run it through `tools/*.ps1`, never by hand.

## Commands (PowerShell, from the repo root)
- `./tools/verify.ps1 -Game <g> -Tier auto|0|1|2|3`  run the checks; result in `games/<g>/.reports/summary.txt`, whose
  header records `commit=` and `tree=clean|dirty`. `-Scenario a,b|none`: scoped run (tests + those scenarios) into
  `summary-scoped.txt`, never summary.txt. `-CheckFresh`: FRESH when summary.txt is a PASS of HEAD at that tier or higher
- `./tools/test.ps1 -Game <g> [-File test/unit/test_x.gd] [-Test name]`  GUT unit tests, headless
- `./tools/smoke.ps1 -Game <g> [-Scenario a,b] [-Jobs 3]`  headless scenario runs, 3 at a time; metrics/perf_*/world_stream* ones alone after
- `./tools/shots.ps1 -Game <g> [-Scenario a,b]`  windowed run with screenshots (a game window opens; expected). Without
  `-Scenario` only scenarios with a screenshot or metrics step. One window at a time on the machine (a lock; it may wait)
- `./tools/pixels.ps1 -Image <png>[,<png>] label=x:y ... [-Column x -Rows a,b]`  pixel colors and luma; never ad-hoc `Add-Type` scripts
- `./tools/import.ps1 -Game <g> [-Force]`  once per fresh clone or worktree (verify/test call it when `.godot/` is missing);
  `-Force` after a merge or a new `class_name`: a stale class cache makes GUT skip test files while test.ps1 still says PASS
- `./tools/new-game.ps1 -Name <n>`  scaffold a game from `templates/game-template` (runs `git init`)
- `./tools/game-worktree.ps1 -Game <g> [-Branch b] [-Remove]`  check out a game branch as `games/<g>--<branch>`
- Shapes that run without a prompt: `./tools/<t>.ps1` (or `C:/game-dev/tools/<t>.ps1` from any folder), `git -C <path> ...`,
  and pipes into `Select-Object`, `Select-String`, `Out-Null`. These always prompt: `& <tool>`, `Set-Location`/`cd`
  before a command, `ForEach-Object { }` (use `Select-Object -ExpandProperty`). Write paths out instead of `$var = ...`.
  In allow rules a `*` inside a script path never matches, so a new `tools/<t>.ps1` needs its own rules. Only Klas
  edits `.claude/settings.json`.

## Verification tiers (`-Tier auto` picks from the diff; go up when unsure, never down)
- 0 docs/design only: nothing.  1 one script, no scene: format + parse + unit tests.
- 2 feature, several files, scene or project.godot: 1 + full unit + headless smoke scenarios.
- 3 anything the player sees or feels (shader, UI, art, juice) or a milestone: 2 + screenshots + playtest-critic + code-reviewer.
- Evidence or it did not happen: quote the command and the summary.txt lines. Never say "tests pass" without them.
- One full run per commit, at every tier (Klas, 2026-10-11): implementers iterate with tier 2 plus `shots.ps1 -Scenario`
  for their own scenarios, commit, then run the full tier once on the clean tree. The test-runner reuses that run when
  `-CheckFresh` says FRESH and re-runs only the tests and the packet's scenarios (`-Scenario`); otherwise the full tier.
- Screenshot baselines are the lead's call, not Klas's: once the playtest-critic recommends a shot and the lead has
  looked at it, follow the approve-baseline steps on the game's main (scoped with `-Scenario`) and report it.

## Delegation
- Design, GDD, "is this fun": game-designer. Code: gameplay-dev / visuals-dev (own game checkout each, max 3 at once).
- Running checks: test-runner. Tier >= 2 diffs: code-reviewer. Tier 3: playtest-critic. Lookups: Explore.
- Creative direction is Klas's: story, main goal, setting, tone and pillars. Ask him (with options if useful)
  before any agent writes them into a GDD; never brief an agent to settle them or commit them as defaults.
- Klas does no hands-on work. Edits (including `project.godot`), commands and commits belong to the lead or an
  agent. When a guard blocks an edit, ask Klas to authorize it and then make it yourself; only
  `.claude/settings.json` stays Klas's to apply.
- Klas plays remotely: every build for Klas goes out by the `playtest-build` skill (a temporary `playtest` branch on
  the game's GitHub repo, deleted once Klas has saved it).
- Playable first (Klas, standing): get playable builds to Klas early and often. Review rounds fix only what breaks
  play, a pillar or a budget; polish, test hygiene and optional findings go to plan.md follow-ups, not new rounds.
  Do not sink time into details that may not survive play; Klas judges feel in the build.
- Plan first for anything beyond a one-sentence diff. Tell Klas when to `/clear` (task done, decisions in files,
  work committed) or `/compact` (long session mid-task); only Klas can type them.

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
- Commit and push freely (root and game repos, each to its own origin). Merge a branch once it is review-passed
  (test-runner PASS, no blocking review findings) by the merge-branch steps. Deleting a branch needs Klas's ask.
- Only the lead edits `design/plan.md` and `project.godot`, on the game's main.

When compacting, keep: modified files, current task id, last verify command and its result.
