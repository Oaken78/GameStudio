# SubagentStop hook on gameplay-dev / visuals-dev (declared as Stop in their frontmatter).
# Runs tier <= 1 verification for every game touched in the subagent's checkout (cwd from the hook input,
# so worktrees work) and blocks the stop when it fails. Cached by diff hash in games/<g>/.reports/gate-stamp.json,
# so stopping again after a green run costs nothing. Exits 0 in every case; a broken hook must never trap an agent.
$ErrorActionPreference = 'Continue'
try {
    $raw = [Console]::In.ReadToEnd()
    if (-not $raw) { exit 0 }
    $j = $raw | ConvertFrom-Json
    if ($j.stop_hook_active -eq $true) { exit 0 }
    $cwd = $j.cwd
    if (-not $cwd -or -not (Test-Path $cwd)) { $cwd = (Get-Location).Path }
    $verify = Join-Path (Split-Path $PSScriptRoot -Parent) 'verify.ps1'
    if (-not (Test-Path $verify)) { exit 0 }
    if (-not (Test-Path (Join-Path $cwd 'games'))) { exit 0 }

    Push-Location $cwd
    try {
        $changed = @(git status --porcelain --untracked-files=all -- games)
        $head = git rev-parse --verify -q HEAD
        $main = git rev-parse --verify -q main
        $committed = @()
        if ($head -and $main -and ($head -ne $main)) {
            $base = git merge-base main HEAD
            if ($base) { $committed = @(git diff --name-only $base HEAD -- games) }
        }
        $diffText = ''
        if ($head) { $diffText = (git diff HEAD -- games | Out-String) }
    } finally { Pop-Location }

    $games = New-Object 'System.Collections.Generic.HashSet[string]'
    $untracked = @()
    foreach ($line in $changed) {
        if ($null -eq $line -or $line.Length -le 3) { continue }
        $p = ($line.Substring(3).Trim().Trim('"') -replace '\\', '/')
        if ($p.Contains(' -> ')) { $p = ($p -split ' -> ')[-1] }
        if ($line.StartsWith('??')) { $untracked += $p }
        if ($p -match '^games/([^/]+)/') { $null = $games.Add($Matches[1]) }
    }
    foreach ($f in $committed) { if ($f -match '^games/([^/]+)/') { $null = $games.Add($Matches[1]) } }
    if ($games.Count -eq 0) { exit 0 }

    $parts = @([string]$head, [string]$diffText)
    foreach ($u in $untracked) {
        $fp = Join-Path $cwd $u
        if (Test-Path $fp) { $fi = Get-Item $fp; $parts += ($u + ':' + $fi.Length + ':' + $fi.LastWriteTimeUtc.Ticks) }
    }
    $sha = [System.Security.Cryptography.SHA1]::Create()
    $hash = [System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes(($parts -join "`n")))).Replace('-', '')

    foreach ($g in $games) {
        $proj = Join-Path $cwd (Join-Path 'games' $g)
        if (-not (Test-Path (Join-Path $proj 'project.godot'))) { continue }
        $reports = Join-Path $proj '.reports'
        if (-not (Test-Path $reports)) { $null = New-Item -ItemType Directory -Path $reports }
        $stampPath = Join-Path $reports 'gate-stamp.json'
        if (Test-Path $stampPath) {
            try {
                $stamp = Get-Content $stampPath -Raw | ConvertFrom-Json
                if ($stamp.hash -eq $hash -and $stamp.pass -eq $true) { continue }
            } catch { }
        }
        & $verify -Game $g -Root $cwd -Tier auto -MaxTier 1 -Quiet
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
