---
name: approve-baseline
description: Promote the latest screenshots of a game to golden baselines in test/baselines (the only sanctioned way to change them).
argument-hint: <game> <shot name | all>
---
1. `./tools/shots.ps1 -Game $0 -Scenario <scenario> -SaveBaseline` (add `-Shot $1` unless `$1` is `all`). The script
   runs the scenario and copies its PNGs into `games/$0/test/baselines/`; agents are blocked from editing that folder directly.
2. Report the saved file names and RMSE values in the status update. Baselines are the lead's call (after the
   playtest-critic recommends them and the lead has looked); Klas does not need to approve them.
3. In the game's own repo: `git -C games/$0 add test/baselines`, then commit there as
   `test($0): approve baseline <shot>`.
