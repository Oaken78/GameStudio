---
name: merge-branch
description: Merge a reviewed implementer branch into main safely (PR + squash with gh when available, local --no-ff otherwise), re-verify main, prune the worktree, update plan.md.
disable-model-invocation: true
argument-hint: <branch>
---
Merge branch `$0`.

1. Confirm the branch has a passing test-runner result and no blocking review findings in this session;
   otherwise stop and say what is missing.
2. If `gh` is installed and authenticated: `gh pr create --fill --head $0`, then `gh pr merge --squash --delete-branch`
   (this prompts; that is intended). Otherwise `git merge --no-ff $0` on `main`.
3. On a conflict in `project.godot` or any `.tscn`: stop, show both sides, never auto-resolve.
4. `./tools/verify.ps1 -Game <game> -Tier 1` on `main`; quote the summary lines.
5. `git worktree prune`; set the packet status to `done` in `design/plan.md` with the merge commit hash.
