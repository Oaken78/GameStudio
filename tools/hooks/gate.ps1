# SubagentStop hook on gameplay-dev / visuals-dev (declared as Stop in their frontmatter).
# Runs tier <= 1 verification for the game checkouts the subagent works in and blocks the stop when it fails.
# Games are separate git repos under games/; an implementer checks its branch out as games/<g>--<branch> with
# tools/game-worktree.ps1, which prints "GAME <id>". The hook finds those ids in the subagent's own transcript
# (agent_transcript_path). Fallback for an agent in a Claude worktree on branch worktree-<name>: a checkout on that
# same branch. A checkout on main is never checked (developers run from the root repo, which sits on main).
# Cached by diff hash in games/<id>/.reports/gate-stamp.json, so stopping again after a green run costs nothing.
# Exits 0 in every case; a broken hook must never trap an agent.
$ErrorActionPreference = 'Continue'
try {
    $raw = [Console]::In.ReadToEnd()
    if (-not $raw) { exit 0 }
    $j = $raw | ConvertFrom-Json
    if ($j.stop_hook_active -eq $true) { exit 0 }
    $cwd = $j.cwd
    if (-not $cwd -or -not (Test-Path $cwd)) { $cwd = (Get-Location).Path }
    $tools = Split-Path $PSScriptRoot -Parent
    $verify = Join-Path $tools 'verify.ps1'
    if (-not (Test-Path $verify)) { exit 0 }
    . (Join-Path $tools '_lib.ps1')

    Push-Location $cwd
    try { $branch = git branch --show-current } finally { Pop-Location }
    $root = Get-RepoRoot
    $gamesDir = Join-Path $root 'games'
    if (-not (Test-Path $gamesDir)) { exit 0 }
    $ids = New-Object 'System.Collections.Generic.HashSet[string]'
    $tp = [string]$j.agent_transcript_path
    if ($tp -and (Test-Path $tp)) {
        foreach ($m in @(Select-String -Path $tp -Pattern 'GAME ([A-Za-z0-9_]+--[A-Za-z0-9._-]+)' -AllMatches)) {
            foreach ($mm in $m.Matches) { $null = $ids.Add($mm.Groups[1].Value) }
        }
    }

    foreach ($d in @(Get-ChildItem $gamesDir -Directory)) {
        $proj = $d.FullName
        if (-not (Test-Path (Join-Path $proj 'project.godot'))) { continue }
        if (-not (Test-Path (Join-Path $proj '.git'))) { continue }
        if (-not $ids.Contains($d.Name)) {
            if (-not $branch -or $branch -eq 'main' -or $branch -eq 'master') { continue }
            Push-Location $proj
            try { $b = git branch --show-current } finally { Pop-Location }
            if ($b -ne $branch) { continue }
        }
        Push-Location $proj
        try { $b = git branch --show-current } finally { Pop-Location }
        if ($b -eq 'main' -or $b -eq 'master') { continue }

        $files = @(Get-ChangedFiles -Root $root -GameRel ('games/' + $d.Name))
        if ($files.Count -eq 0) { continue }
        Push-Location $proj
        try {
            $head = git rev-parse --verify -q HEAD
            $diffText = ''
            if ($head) { $diffText = (git diff HEAD -- . | Out-String) }
        } finally { Pop-Location }
        $parts = @([string]$head, [string]$diffText)
        foreach ($f in $files) {
            $fp = Join-Path $root $f
            if (Test-Path $fp -PathType Leaf) { $fi = Get-Item $fp; $parts += ($f + ':' + $fi.Length + ':' + $fi.LastWriteTimeUtc.Ticks) }
        }
        $sha = [System.Security.Cryptography.SHA1]::Create()
        $hash = [System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes(($parts -join "`n")))).Replace('-', '')

        $reports = Join-Path $proj '.reports'
        if (-not (Test-Path $reports)) { $null = New-Item -ItemType Directory -Path $reports }
        $stampPath = Join-Path $reports 'gate-stamp.json'
        if (Test-Path $stampPath) {
            try {
                $stamp = Get-Content $stampPath -Raw | ConvertFrom-Json
                if ($stamp.hash -eq $hash -and $stamp.pass -eq $true) { continue }
            } catch { }
        }
        $g = $d.Name
        & $verify -Game $g -Root $root -Tier auto -MaxTier 1 -Quiet
        $code = $LASTEXITCODE
        $pass = ($code -eq 0)
        [System.IO.File]::WriteAllText($stampPath, (@{ hash = $hash; pass = $pass; at = (Get-Date).ToString('s') } | ConvertTo-Json -Compress))
        if (-not $pass) {
            $summary = @()
            $sp = Join-Path $reports 'summary.txt'
            if (Test-Path $sp) { $summary = @(Get-Content $sp | Select-Object -Last 25) }
            $reason = "Tier 1 verification failed for games/$g (tools/hooks/gate.ps1). Fix the failure, re-run ./tools/verify.ps1 -Game $g -Tier auto, then finish.`n" + ($summary -join "`n")
            $out = @{ decision = 'block'; reason = $reason } | ConvertTo-Json -Compress
            [Console]::Out.WriteLine($out)
            exit 0
        }
    }
    exit 0
} catch {
    exit 0
}
