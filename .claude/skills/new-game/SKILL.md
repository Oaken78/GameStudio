---
name: new-game
description: Scaffold a new Godot project under games/<name> from templates/game-template and prove it runs (import, tests, headless smoke, first screenshot baseline).
disable-model-invocation: true
argument-hint: <name>
---
Scaffold the game `$0` (lowercase letters, digits and hyphens only; refuse anything else or an existing folder).

1. `./tools/new-game.ps1 -Name $0` copies the template and rewrites `config/name` in `project.godot`.
2. `./tools/verify.ps1 -Game $0 -Tier 2` proves import, GUT and the headless boot scenario. Quote the summary lines.
3. `./tools/shots.ps1 -Game $0 -SaveBaseline` records the first boot screenshot as the golden baseline.
   Read the PNG once to confirm it is not black.
4. Commit: `chore($0): scaffold from game template`.
5. Tell Klas: next is `/gdd $0`, then `docs/preproduction-checklist.md`.
