---
name: gdd
description: Interview Klas with AskUserQuestion and write or refresh games/<name>/design/gdd.md plus the milestone table in design/plan.md. Runs in the main session because subagents cannot ask questions.
disable-model-invocation: true
argument-hint: <game> [section]
---
Write or refresh the GDD for `$0` (section `$1` only if given). Use `docs/gdd-template.md` as the structure
and the existing `games/$0/design/gdd.md` as the starting point.

Interview with AskUserQuestion, hard parts first, no obvious questions:
1. Player fantasy and the one risk hypothesis (why is it fun, what kills it if wrong).
2. Core loop at 30 s / 5 min / session; the failure state.
3. Feel targets as numbers; verbs and input map action names.
4. Visual direction: readability rules, palette, three references.
5. Scope: M0 playable loop in at most two weeks of agent work; what is cut first.

Then:
- Write the GDD. Numbers, not adjectives. Append decisions to the Decisions log.
- Derive `design/plan.md`: milestones (M0 first) with acceptance criteria, and an empty task table
  (id, title, owned paths, tier, status, branch).
- Fill `design/budgets.json` from section 13.
- Spawn `game-designer` to critique fun, scope and pillar conflicts; fold the useful parts in; list its open questions.
- Run through `docs/preproduction-checklist.md` and report what is still open.
