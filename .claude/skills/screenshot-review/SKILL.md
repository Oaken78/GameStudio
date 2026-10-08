---
name: screenshot-review
description: Visual before/after check - run the windowed scenarios, compare screenshots against baselines, read the changed images and judge readability, composition and contrast. Use after any visual change.
argument-hint: <game> [scenario]
---
1. Run `./tools/shots.ps1 -Game $0` (add `-Scenario $1` if given). It prints one line per screenshot:
   SAME / CHANGED (with RMSE) / NEW / MISSING and writes diff PNGs for CHANGED ones.
2. Read each CHANGED or NEW PNG and its diff image once. Report: what changed, readability of game state,
   composition and contrast, consistency with the GDD visual direction.
3. If the change was intentional visual work, spawn `playtest-critic` on the same scenario.
4. If the new look is correct, tell Klas to run `/approve-baseline $0 <shot|all>`. Never update baselines yourself.
