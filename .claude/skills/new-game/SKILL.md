---
name: new-game
description: Scaffold a new Godot project under games/<name> as its own git repo from templates/game-template and prove it runs (import, tests, headless smoke, first screenshot baseline).
disable-model-invocation: true
argument-hint: <name>
---
Scaffold the game `$0` (lowercase letters, digits and hyphens only; refuse anything else or an existing folder).

1. `./tools/new-game.ps1 -Name $0` copies the template, rewrites `config/name` in `project.godot` and runs
   `git init -b main` in `games/$0` (each game is its own repo; the root repo ignores `games/`).
2. `./tools/verify.ps1 -Game $0 -Tier 2` proves import, GUT and the headless boot scenario. Quote the summary lines.
3. `./tools/shots.ps1 -Game $0 -SaveBaseline` records the first boot screenshot as the golden baseline.
   Read the PNG once to confirm it is not black.
4. Commit in the game repo: `git -C games/$0 add -A`, then `git -C games/$0 commit` with
   `chore($0): scaffold from game template` and the tier result in the body. Adding a remote is Klas's call.
5. Tell Klas: next is `/gdd $0`, then `docs/preproduction-checklist.md`.
