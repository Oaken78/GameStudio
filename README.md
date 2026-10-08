# DevelopmentRoot

Claude Code environment for building Godot 4.7 games. One Godot project per folder under `games/`.

## Start here
1. Open this folder in Claude Code (desktop app). `CLAUDE.md` is loaded automatically.
2. New game: `/new-game <name>` scaffolds `games/<name>/` from `templates/game-template/`.
3. Design first: `/gdd <name>` interviews you and writes `games/<name>/design/gdd.md`, then run through `docs/preproduction-checklist.md`.
4. Build: `/plan-feature <name> <milestone>` writes task packets, `/dispatch <name> ready` runs implementers in parallel worktrees, `/merge-branch` merges reviewed work.

## Layout
- `CLAUDE.md` project rules every session loads (keep it short).
- `.claude/agents/` the agent team, `.claude/skills/` one-command workflows, `.claude/rules/` path-scoped coding rules.
- `tools/` PowerShell scripts that run Godot (tests, smoke runs, screenshots, verification tiers). The only way agents run Godot.
- `templates/game-template/` runnable Godot project with the test harness, copied by `/new-game`.
- `docs/` best practices, workflow (tiers, worktrees, timings), GDD and task templates.
- `games/<name>/` one Godot project per game. `.reports/` inside a game is scratch output (gitignored).

## Check the environment
`./tools/selftest.ps1` builds a throwaway game and runs every tier end to end. Run it after changing anything in `tools/` or the template.
