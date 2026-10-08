---
name: merge-branch
description: Merge a reviewed implementer branch into the game repo's main safely (PR + squash with gh when the game repo has a remote, local --no-ff otherwise), re-verify main, remove the branch checkout, update plan.md.
disable-model-invocation: true
argument-hint: <game> <branch>
---
Merge branch `$1` of game `$0`. Each game is its own git repo at `games/$0`; run every git command there
with `git -C games/$0`. The branch is checked out at `games/$0--<branch-slug>` (tools/game-worktree.ps1).

1. Confirm the branch has a passing test-runner result and no blocking review findings in this session;
   otherwise stop and say what is missing.
2. `games/$0` must be on `main` with a clean status; otherwise stop and say why.
3. If `gh` is installed and `git -C games/$0 remote` lists a remote: from `games/$0`, `gh pr create --fill --head $1`,
   then `gh pr merge --squash --delete-branch` (this prompts; that is intended). Otherwise
   `git -C games/$0 merge --no-ff $1`.
4. On a conflict in `project.godot` or any `.tscn`: stop, show both sides, never auto-resolve.
5. `./tools/verify.ps1 -Game $0 -Tier 1` on `main`; quote the summary lines.
6. `./tools/game-worktree.ps1 -Game $0 -Branch $1 -Remove` (keeps the branch), then `git worktree prune` in the
   root repo. Set the packet status to `done` in `games/$0/design/plan.md` with the merge commit hash and commit
   that in the game repo.
