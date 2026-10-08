---
name: approve-baseline
description: Promote the latest screenshots of a game to golden baselines in test/baselines (the only sanctioned way to change them).
disable-model-invocation: true
argument-hint: <game> <shot name | all>
---
1. `./tools/shots.ps1 -Game $0 -SaveBaseline` (add `-Shot $1` unless `$1` is `all`). The script copies the
   latest run's PNGs into `games/$0/test/baselines/`; agents are blocked from editing that folder directly.
2. Show Klas the before/after file names and RMSE values printed by the script.
3. `git add games/$0/test/baselines` and commit as `test($0): approve baseline <shot>`.
