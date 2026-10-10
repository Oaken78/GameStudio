# Workflow reference

Details that do not belong in CLAUDE.md. Read on demand.

## Verification tiers

`tools/verify.ps1 -Game <g> -Tier auto` classifies the change from `git status` plus the diff against `main`
in the game's own repo (files under `games/<g>/`). You may always run a higher tier than `auto` picks.

| Tier | Trigger (files changed) | Runs | Typical time |
|---|---|---|---|
| 0 | only `*.md`, `design/` | nothing | 0 s |
| 1 | at most one `.gd` under `scripts/` or `autoload/` (plus its test), no scene, shader or UI | gdformat check (if installed), `--check-only` parse (advisory), GUT unit tests for the matching `test_<name>.gd`, else all unit tests | 10-30 s |
| 2 | more scripts, `.tscn`/`.tres`, `project.godot`, `autoload/` | tier 1 + all GUT tests + every `test/scenarios/*.json` headless (3 at a time, timing-sensitive ones alone after) + log scan + metrics vs `design/budgets.json` | 30-90 s |
| 3 | any `.gdshader`, `ui/`, `shaders/`, `assets/`, images, audio, theme, or the packet says feel/milestone | tier 2 + `tools/shots.ps1` (windowed screenshots of the scenarios with a screenshot or metrics step, compare vs `test/baselines/`, budgets; one window at a time on the machine) | 2-5 min |

Output: at most 40 lines on the console and `games/<g>/.reports/summary.txt` with one line per stage,
failing tests with assertion lines, up to 20 log-scan lines, `BUDGET FAIL` lines, a `timing:` line and the
artifact folders. Exit code 0 pass, 1 fail. The header records `commit=`, `content=` (tree hash) and
`tree=clean|dirty|changed`, so a run is tied to exactly one commit.

One full run per commit (Klas, 2026-10-11), at tiers 1, 2 and 3 alike: the implementer commits and then runs
the packet tier once on the clean tree. The test-runner asks `verify.ps1 -CheckFresh`; FRESH (a PASS at that
tier or higher, same content as HEAD, clean then and now) means it re-runs only the tests and the packet's
scenarios with `-Scenario a,b`, which writes `summary-scoped.txt` and leaves summary.txt alone. STALE means
the full tier again. The playtest-critic judges that commit's `shots-*` run instead of repeating it.

Policy the agents apply:

| Change | Tier | Who runs it | Review |
|---|---|---|---|
| tunable, typo, rename | 1 | SubagentStop gate (automatic) | none |
| logic fix | 1 + failing-then-passing test | implementer, gate | `/code-review low` on the diff |
| new mechanic, enemy, screen | 2 (3 if it has a look) + a scenario step | implementer, then test-runner | code-reviewer |
| shader, particles, UI, palette | 3 | visuals-dev, then `/screenshot-review` | playtest-critic |
| milestone | 3 on all scenarios | lead | code-reviewer + playtest-critic + Klas plays it |

The SubagentStop gate on `gameplay-dev` and `visuals-dev` never runs above tier 1 and caches the result by
diff hash, so re-stopping after a green run is free. It skips when summary.txt is FRESH at tier 1, and its own
runs go to `summary-gate.txt`, so a stop never overwrites the developer's full-run evidence. Claude Code stops blocking after 8 consecutive blocks,
so a hopeless implementer returns with the failure visible instead of looping forever.

## Parallel work

1. Inside one lead session: `/dispatch <game> ready` spawns up to 3 implementers in the background, each in a
   Claude worktree `.claude/worktrees/<name>/` of the root repo on branch `worktree-<name>`, with disjoint owned
   paths from their packets. That root worktree has no games, so each implementer runs
   `tools/game-worktree.ps1 -Game <game>` and works in `games/<game>--worktree-<name>/`: a worktree of the game
   repo on a branch with the same name. The stop gate finds it by that shared branch name. The game checkout
   outlives the Claude worktree, so test-runner, code-reviewer and `/merge-branch` use it afterwards.
2. Across desktop sessions: start a second session with the worktree option for a long-lived human-steered
   stream (art direction vs mechanics). Sessions can message each other for handovers.
3. `/batch` for 5-30 mechanical units (a typing pass, an API rename).

Conventions:
- One task = one game checkout = one owner = disjoint files. `project.godot`, autoloads and `design/plan.md`
  are edited only by the lead on the game's `main` (integration packet last).
- Keep the automatic `worktree-<name>` branch name; the commit and PR title carry the meaning.
- Fresh worktrees have no `.godot/`; `verify.ps1` and `test.ps1` run `import.ps1` when the class cache is missing.
- All worktrees of one game share `user://`; tests and the harness never write there (output goes to `.reports/`).
  Scenario runs log to their own `--log-file`, so they do not touch `user://logs` either.
- Nobody passes `-d` to Godot. Headless runs open no ports, so parallel runs do not collide.
- Windowed runs share the real mouse and focus, so every windowed Godot launch through `tools/` holds a
  machine-wide lock (named mutex `Global\GameStudio-GodotWindow`) for one scenario; others wait and say so.

Merge flow: implementer finishes (committed, full packet tier run once on the clean tree) -> test-runner reuses
that run when FRESH and re-runs the tests and the packet's scenarios (the full tier otherwise) on the branch
-> code-reviewer (tier 2+) -> playtest-critic (tier 3) -> findings go back to the same implementer ->
`/merge-branch <game> <branch>` (PR + squash via `gh` when the game repo has a remote, local `--no-ff` otherwise;
merging is ask-gated) -> tier 1 on `main` -> `tools/game-worktree.ps1 -Remove` and `git worktree prune`. Conflicts in `.tscn` or `project.godot` are never auto-resolved.

The lead plans, writes packets, dispatches, routes findings, merges, keeps `plan.md` current and asks Klas
only for decisions (design, merge, scope). The lead does not read whole files (Explore does), does not
implement tier 2+ work itself and does not re-run tests itself (test-runner does).

## Git

- Each game is its own repo at `games/<g>` with its own `main`, history and remote. The root repo holds tools,
  agents, skills, docs and the template, and ignores `games/*/`. Game git commands: `git -C games/<g> ...`.
- Commits: Conventional Commits with the game folder as scope: `feat(rift): add dash with i-frames`.
  Shared changes use `root`, `tools`, `docs`. The body quotes the tier result
  (`verify: tier 2 PASS games/rift/.reports/smoke-20261008-1512`).
- Never push, merge or delete branches unless asked.
- `.godot/`, `.reports/`, `.claude/worktrees/` and `settings.local.json` are ignored. `*.import`, `*.uid`,
  `.gutconfig.json`, `test/baselines/*.png` and `export_presets.cfg` (without secrets) are committed.

## Models and cost

| Agent | Model / effort | Why |
|---|---|---|
| Explore | haiku / low | lookups are mechanical and frequent; overrides the built-in Explore |
| test-runner | haiku / low | runs one script, reads one summary; `omitClaudeMd` keeps its prompt small |
| gameplay-dev, visuals-dev | sonnet / medium | highest volume of tokens; tests, gate and Opus review protect quality |
| code-reviewer | opus / medium | low volume, one diff; a different model than the author catches more |
| game-designer, playtest-critic | opus / high | judgement is the product; priorities 1-3 live here |

Knobs: raise implementer effort to `high` in their frontmatter if code-reviewer keeps finding bugs; lower
the lead to Sonnet with `/model` on cheap days. Rough cost per task type: small fix = one Sonnet subagent
plus a tier 1 run; feature = packet + Sonnet implementer + Haiku test-runner + Opus review; milestone adds
screenshots and an Opus playtest read (images capped at 6 per run).

## Settled facts and timings

Filled in by `tools/selftest.ps1` runs. Record the date, the Godot version and the numbers.

| Date | Fact | Result |
|---|---|---|
| 2026-10-08 | GUT 9.7.1 under `--headless` on Godot 4.7.2 | works: 3 tests in 1.6 s, exit 0; a failing test gives exit 1 and a `FAIL` line with the assertion in `test-summary.txt` |
| 2026-10-08 | gdformat 4.5.0 on the 4.7 template scripts | parses and formats them (`--check` exit 1 when unformatted); resolved via `env.GDTOOLKIT_BIN` since pip --user is not on PATH |
| 2026-10-08 | `SceneTree.quit(code)` exit code through `*_console.exe` | works: `quit(10)` arrives as process exit 10 |
| 2026-10-08 | `OS.add_logger()` catches `push_error` (empty rationale, text in `code`) | works; the log-file scan catches the same line, harness exits 11 |
| 2026-10-08 | Input injection under `--headless` (issue #73557) | works on 4.7.2: `Input.parse_input_event` moved the player, so input scenarios run in tier 2 headless |
| 2026-10-08 | `--log-file` with an absolute path, no project setting | works; the file contains the `ERROR:` lines |
| 2026-10-08 | `await RenderingServer.frame_post_draw` windowed (1280x720, `--fixed-fps 60 --disable-vsync`) | works, no hang; two scenarios with screenshots in 8.9 s including compare |
| 2026-10-08 | Screenshot RMSE (`Image.compute_image_metrics`, 0-255 scale) | identical frames 0.0; a 48 px square moved 120 px = 8.77; threshold set to 1.0 |
| 2026-10-08 | Template timings on this machine | import 4 s (8 s cold), headless boot scenario 0.5 s, windowed shots 4 s per scenario, compare 4 s, whole selftest 25 s |
| 2026-10-08 | `${CLAUDE_PROJECT_DIR}` inside hook `args` | substituted correctly (protect hook blocked a write under `addons/`) |
| 2026-10-08 | Metrics monitors `TIME_PROCESS` / `TIME_PHYSICS_PROCESS` | refresh about once per second; `frame_ms` is measured from `Time.get_ticks_usec()` instead |
| 2026-10-11 | Parallel headless scenario runs (3 Godot processes, own `--log-file` and `--out`) | no collisions: nothing written into `.godot/` or `user://logs`; selftest covers order, an 8 s timeout, an early exit and a failed assert among parallel jobs |
| 2026-10-11 | Named mutex as the window lock (`Global\GameStudio-GodotWindow`) | works across processes; free at once when the holding process is killed; a waiting run records "waited N s" |
| 2026-10-11 | walkers tier 3 (49 scenarios) before / after the speed-up | 657 s (unit 16, smoke 245 one at a time, shots 380 for all 47) -> 463 s (tests 24, smoke 233 with 16 parallel and 33 timing-sensitive alone, shots 206 for the 28 with a screenshot or metrics step) |
| 2026-10-11 | walkers' 33 timing-sensitive scenarios 3 at a time (experiment, not the rule) | all PASS in 62 s against 152 s alone; worst `tick_p99_ms` 2.23 vs 1.96 alone (bar 3.0), worst `tick_max_ms` 6.38 vs 7.86 alone (bar 8.0) |
