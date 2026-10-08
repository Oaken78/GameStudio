# Checks out a branch of a game repo as a sibling folder games/<game>--<branch-slug>, so every tool works on it
# with -Game <game>--<branch-slug>. Each game under games/ is its own git repo; the root repo ignores games/.
#   Implementer in a Claude worktree:  ./tools/game-worktree.ps1 -Game rift
#       new game branch named after the current root worktree branch (worktree-<name>), from the game's main.
#   Lead, test-runner, reviewer:       ./tools/game-worktree.ps1 -Game rift -Branch worktree-agent-ab12
#   After merging:                     ./tools/game-worktree.ps1 -Game rift -Branch worktree-agent-ab12 -Remove
# Never deletes branches. Prints "GAME <id>" as the first line.
param(
    [Parameter(Mandatory = $true)][string]$Game,
    [string]$Branch = '',
    [switch]$Remove
)
. "$PSScriptRoot/_lib.ps1"
$root = Get-RepoRoot
$repo = Join-Path $root (Join-Path 'games' $Game)
if (-not (Test-Path (Join-Path $repo '.git') -PathType Container)) { throw "games/$Game is not a game repo (no .git folder)" }

if (-not $Branch) {
    Push-Location $script:RepoRootDefault
    try { $Branch = (git branch --show-current) } finally { Pop-Location }
    if (-not $Branch -or $Branch -eq 'main') { throw 'Not inside a Claude worktree branch: pass -Branch <name>.' }
}
$slug = ($Branch.ToLower() -replace '[^a-z0-9-]', '-').Trim('-')
$id = "$Game--$slug"
$dst = Join-Path $root (Join-Path 'games' $id)

Push-Location $repo
try {
    if ($Remove) {
        if (Test-Path $dst) {
            git worktree remove $dst
            if ($LASTEXITCODE -ne 0) { throw "git worktree remove failed for games/$id (uncommitted changes?)" }
        }
        git worktree prune
        Write-Host "GAME $id removed (branch $Branch kept)"
        exit 0
    }
    if (Test-Path (Join-Path $dst 'project.godot')) {
        Write-Host "GAME $id"
        Write-Host "exists: $dst on branch $Branch. Use -Game $id with every tool."
        exit 0
    }
    $exists = git rev-parse --verify -q "refs/heads/$Branch"
    if ($exists) { git worktree add -q $dst $Branch } else { git worktree add -q -b $Branch $dst main }
    if ($LASTEXITCODE -ne 0) { throw "git worktree add failed for $Branch" }
} finally { Pop-Location }
Write-Host "GAME $id"
Write-Host "created: $dst on branch $Branch (game repo games/$Game). Use -Game $id with every tool."
exit 0
