---
name: verify
description: Decide and run the verification tier for a game with tools/verify.ps1 and return the summary lines as evidence. Reuses a fresh full run of the same commit. Use before reporting any code change as done.
argument-hint: <game> [tier] [scenarios a,b]
context: fork
agent: test-runner
allowed-tools: Bash, PowerShell, Read, Grep, Glob
---
One full run per commit, at tiers 1, 2 and 3 alike (Klas, 2026-10-11). Tier `$1` (use `auto` when none was
given); run `./tools/import.ps1 -Game $0` first if `games/$0/.godot/` is missing.

1. `./tools/verify.ps1 -Game $0 -Tier $1 -CheckFresh` runs nothing and prints FRESH or STALE.
2. FRESH (summary.txt is a PASS at that tier or higher of HEAD's commit on a clean tree): run the scoped check
   `./tools/verify.ps1 -Game $0 -Tier $1 -Scenario $2` (`-Scenario none` when no scenarios were given) and read
   `games/$0/.reports/summary-scoped.txt`; summary.txt stays the full-run evidence.
3. STALE: run `./tools/verify.ps1 -Game $0 -Tier $1` and read `games/$0/.reports/summary.txt`.

Report in the test-runner shape: RESULT, tier, duration, evidence (reused full run + scoped, or full run, with the
commit= and tree= from the header), failing tests, first error, artifacts.
