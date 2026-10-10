---
name: screenshot-review
description: Visual before/after check - reuse (or run) the windowed scenarios of the current commit, compare screenshots against baselines, read the changed images and judge readability, composition and contrast. Use after any visual change.
argument-hint: <game> [scenario]
---
1. Reuse a run of the current commit when there is one: `./tools/verify.ps1 -Game $0 -Tier 3 -CheckFresh` says
   FRESH (its summary.txt names the shots folder), or a `.reports/shots-<timestamp>/shots-summary.txt` has a
   `checkout:` line with HEAD's commit and `tree=clean`. Otherwise run `./tools/shots.ps1 -Game $0` (add
   `-Scenario $1` if given; without it, only scenarios with a screenshot or metrics step run). The summary has one
   line per screenshot: SAME / CHANGED (with RMSE) / NEW / MISSING, plus diff PNGs for CHANGED ones.
2. Read each CHANGED or NEW PNG and its diff image once. Report: what changed, readability of game state,
   composition and contrast, consistency with the GDD visual direction.
3. If the change was intentional visual work, spawn `playtest-critic` on the same scenario (it reuses the same run).
4. If the new look is correct, tell Klas to run `/approve-baseline $0 <shot|all>`. Never update baselines yourself.
