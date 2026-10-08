---
name: plan-feature
description: Turn a milestone or feature into worktree-sized task packets with disjoint owned paths, written to games/<name>/design/tasks/, and append them to design/plan.md. Use plan mode.
disable-model-invocation: true
argument-hint: <game> <milestone or feature>
---
Plan `$1` for game `$0` into task packets.

1. Read the relevant GDD sections and `games/$0/design/plan.md`. Use `Explore` for lookups; do not read whole files yourself.
2. Split into packets of at most one agent-day each. Every packet: `docs/task-template.md` shape, written to
   `games/$0/design/tasks/<id>.md`, with goal, pillar, quoted GDD refs, owned paths, not-allowed paths,
   acceptance checks (test names, scenario steps, screenshots), tier, out of scope.
3. Owned paths must be disjoint across packets that will run in parallel. Anything touching `project.godot`,
   autoloads or shared scenes goes into one integration packet that the lead does last on `main`.
4. Append the packets to the task table in `plan.md` (status `ready`).
5. Show Klas the list with one line per packet and ask for approval before `/dispatch`.
