# <Game name> - Game Design Document

Copy to `games/<name>/design/gdd.md`. Write numbers, not adjectives. Keep sections short; link references.
`/gdd <name>` fills this in through an interview.

## 1. One-liner and player fantasy
One sentence for the store page. One sentence for what the player feels like doing.

## 2. Pillars (max 3)
Each pillar: name, one line, and "we cut X before we compromise this".

## 3. Core loop
- 30 seconds: what the hands do.
- 5 minutes: what changes.
- One session: what the player walks away with.

## 4. Why it is fun (the risk hypothesis)
The one assumption that, if wrong, kills the game. How milestone M0 tests it.

## 5. Feel targets (numbers)
Input latency, jump/dash timings, hit-stop, camera lag, time-to-kill, pacing. These become scenario checks.

## 6. Player verbs, controls, input map
Action names are fixed here (`move_left`, `jump`, `dash`...). Code, tests and scenarios use these names.

## 7. Failure, success, difficulty curve

## 8. Systems
For each system: state it owns, rules, edge cases, test ideas.

## 9. Content scope per milestone

## 10. Visual direction
Readability rules first (what must be parsed at a glance), then palette, lighting, post FX, references in `design/refs/`.

## 11. Audio direction

## 12. UX and UI flows

## 13. Tech constraints
2D/3D, renderer, resolution, target FPS, platforms. Feeds `design/budgets.json`.

## 14. Milestones
M0 playable loop, M1 vertical slice, ... Each with acceptance criteria and the scenarios/screenshots that prove them.

## 15. Out of scope

## 16. Risks and unknowns (spike tasks)

## 17. Decisions log (append-only)
| Date | Decision | Why | Rejected alternatives |
|---|---|---|---|

## 18. Open questions
