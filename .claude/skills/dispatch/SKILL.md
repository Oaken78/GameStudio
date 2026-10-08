---
name: dispatch
description: Run ready task packets in parallel implementer subagents (gameplay-dev or visuals-dev), each in its own worktree, then test, review and report. Max 3 at once.
disable-model-invocation: true
argument-hint: <game> <packet ids | ready>
---
Dispatch packets `$1` for game `$0` (`ready` means every packet with status `ready` in `design/plan.md`).

1. Read the packets. Verify their owned-path sets are disjoint; abort and say which overlap otherwise.
2. For each packet spawn `gameplay-dev` (or `visuals-dev` when the packet is visual), in the background, with
   the packet path and tier in the prompt. At most 3 concurrent (Godot runs are CPU and GPU heavy). Set the
   packet's status to `in-progress` with the branch name once known.
3. As each returns: spawn `test-runner` at the packet tier on its branch (never trust the claim); then
   `code-reviewer` if tier 2+; then `playtest-critic` if tier 3. Blocking findings go back to the same
   implementer with the findings quoted.
4. Report a table: id, branch, tier result, review verdict, open questions. Set status `review-passed`.
5. Suggest `/merge-branch <branch>` for each passing packet. Never merge without being asked.
