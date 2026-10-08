---
name: verify
description: Decide and run the verification tier for a game with tools/verify.ps1 and return the summary lines as evidence. Use before reporting any code change as done.
argument-hint: <game> [tier]
context: fork
agent: test-runner
allowed-tools: Bash, PowerShell, Read, Grep, Glob
---
Run `./tools/verify.ps1 -Game $0 -Tier $1` from the repo root (use `auto` when no tier was given; run
`./tools/import.ps1 -Game $0` first if `games/$0/.godot/` is missing). Read `games/$0/.reports/summary.txt`
and report in the test-runner shape: RESULT, tier, duration, failing tests, first error, artifacts.
