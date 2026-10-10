# Single entry point for verification. Picks the tier from the diff (-Tier auto) or runs the given tier.
#   tier 0: nothing   tier 1: format + parse (advisory) + unit tests   tier 2: + all tests + headless smoke
#   tier 3: + windowed screenshots compared with baselines (scenarios with a screenshot or metrics step)
# Full run: writes games/<g>/.reports/summary.txt (the only file agents need to read). Exit 0 pass, 1 fail.
# The header records what was verified: commit=<short hash> content=<tree hash> tree=clean|dirty|changed|unknown
# (changed: HEAD or the files changed during the run).
#   -Scenario a,b    scoped run: the tests of the tier plus only these scenarios (smoke, and shots at tier 3).
#                    Writes summary-scoped.txt and never touches summary.txt. -Scenario none: tests only.
#   -CheckFresh      runs nothing; says whether summary.txt can stand in for a full run at -Tier: FRESH (exit 0)
#                    when it is a PASS at that tier or higher of HEAD's content on a clean tree, else STALE (exit 1).
#   -Jobs n          headless smoke scenarios at a time (default 3; metrics/perf_*/world_stream* ones run alone).
#   -SummaryName f   write the full-run summary to .reports/<f> (tools/hooks/gate.ps1 uses summary-gate.txt).
param(
    [Parameter(Mandatory = $true)][string]$Game,
    [string]$Tier = 'auto',
    [int]$MaxTier = 3,
    [string[]]$Scenario = @(),
    [int]$Jobs = 3,
    [switch]$CheckFresh,
    [string]$SummaryName = 'summary.txt',
    [string]$Root = '',
    [switch]$Quiet
)
. "$PSScriptRoot/_lib.ps1"
$root = Get-RepoRoot $Root
$proj = Resolve-GamePath -Game $Game -Root $root
$gameRel = Get-GameRel -Root $root -ProjectDir $proj
$reports = New-ReportsDir $proj

$files = @(Get-ChangedFiles -Root $root -GameRel $gameRel)
$requested = $Tier
if ($Tier -eq 'auto') { $t = Get-AutoTier -Files $files -GameRel $gameRel } else { $t = [int]$Tier }
if ($t -gt $MaxTier) { $t = $MaxTier }

if ($CheckFresh) {
    $fresh = Test-SummaryFresh -ProjectDir $proj -MinTier $t
    if ($fresh.Fresh) { Write-Host "FRESH tier $t`: $($fresh.Reason)"; exit 0 }
    Write-Host "STALE tier $t`: $($fresh.Reason)"
    exit 1
}

# Scoped run: -Scenario names (comma-separated or an array); 'none' keeps the tests only.
$scoped = (($Scenario -join ',').Trim(' ', ',') -ne '')
$names = @()
if ($scoped) {
    $names = @(Get-ScenarioNames -ProjectDir $proj -Scenario $Scenario)
    if ($names.Count -eq 1 -and $names[0] -eq 'none') { $names = @() }
}
$summaryPath = Join-Path $reports $SummaryName
if ($scoped) { $summaryPath = Join-Path $reports 'summary-scoped.txt' }

$state = Get-CheckoutState $proj
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$lines = @()
$timing = @()
$ok = $true
function Add-Line { param([string]$s) $script:lines += $s }
# Merges a tool's summary file into ours, minus its checkout line (the header carries that).
function Add-ToolLines {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return }
    foreach ($l in Get-Content $Path) { if (-not $l.StartsWith('checkout: ')) { Add-Line $l } }
}

if ($t -ge 1) {
    $partWatch = [System.Diagnostics.Stopwatch]::StartNew()
    $scripts = @(Get-ChangedScripts -Files $files -GameRel $gameRel)
    # An explicit -Tier skips the per-script format and parse checks (changed scripts still load in the tests and
    # smoke runs, whose log scan catches parse errors); -Tier auto runs them on the changed scripts.
    $perScript = ($Tier -eq 'auto')
    if (-not $perScript) { $scripts = @() }
    # format check (only when gdformat is installed)
    $gdformat = Get-GdTool 'gdformat'
    if ($gdformat) {
        $bad = 0
        foreach ($s in $scripts) {
            $full = Join-Path $proj $s
            if (-not (Test-Path $full)) { continue }
            $null = & $gdformat --check $full 2>&1
            if ($LASTEXITCODE -ne 0) { $bad++; $ok = $false; Add-Line "FORMAT FAIL $s (run: gdformat $s)" }
        }
        if ($perScript) { Add-Line "format: checked $($scripts.Count) changed scripts, $bad need formatting" }
        else { Add-Line 'format: skipped (explicit -Tier; use -Tier auto for per-script checks)' }
    } else {
        Add-Line 'format: gdformat not installed, skipped (pip install "gdtoolkit==4.*")'
    }
    # parse check (advisory: --check-only reports false errors with autoloads, see godot-cli skill)
    $parsed = 0
    foreach ($s in $scripts) {
        if ($s.StartsWith('test/')) { continue }
        $full = Join-Path $proj $s
        if (-not (Test-Path $full)) { continue }
        $parsed++
        $pr = Invoke-Godot -GodotArgs @('--headless', '--path', $proj, '--check-only', '-s', ('res://' + $s)) -TimeoutSec 60 -WorkDir $proj
        if ($pr.ExitCode -ne 0) {
            $first = @((($pr.Stderr + "`n" + $pr.Stdout) -split "`r?`n") | Where-Object { $_ -match 'ERROR' } | Select-Object -First 1)
            Add-Line "PARSE WARN $s exit=$($pr.ExitCode) $first"
        }
    }
    if ($perScript) { Add-Line "parse: checked $parsed changed scripts (advisory)" }
    else { Add-Line 'parse: skipped (explicit -Tier; scripts still load in tests and smoke, whose log scan catches parse errors)' }
    # unit tests
    $testArgs = @{ Game = $Game; Root = $root; Quiet = $true }
    if ($t -eq 1) {
        $gameplay = @($scripts | Where-Object { -not $_.StartsWith('test/') })
        if ($gameplay.Count -eq 1) {
            $base = [System.IO.Path]::GetFileNameWithoutExtension($gameplay[0])
            $cand = "test/unit/test_$base.gd"
            if (Test-Path (Join-Path $proj $cand)) { $testArgs.File = $cand } else { $testArgs.Dirs = @('res://test/unit') }
        } else {
            $testArgs.Dirs = @('res://test/unit')
        }
    }
    & (Join-Path $PSScriptRoot 'test.ps1') @testArgs
    $code = $LASTEXITCODE
    Add-ToolLines (Join-Path $reports 'test-summary.txt')
    if ($code -ne 0) { $ok = $false }
    $timing += "tests $([math]::Round($partWatch.Elapsed.TotalSeconds, 1)) s"
}

if ($t -ge 2) {
    if ($scoped -and $names.Count -eq 0) {
        Add-Line 'smoke: skipped (-Scenario none)'
    } else {
        $partWatch = [System.Diagnostics.Stopwatch]::StartNew()
        $smokeArgs = @{ Game = $Game; Root = $root; Jobs = $Jobs; Quiet = $true }
        if ($scoped) { $smokeArgs.Scenario = $names }
        & (Join-Path $PSScriptRoot 'smoke.ps1') @smokeArgs
        $code = $LASTEXITCODE
        Add-ToolLines (Join-Path $reports 'smoke-last.txt')
        if ($code -ne 0) { $ok = $false }
        $timing += "smoke $([math]::Round($partWatch.Elapsed.TotalSeconds, 1)) s"
    }
}

if ($t -ge 3) {
    if ($scoped -and $names.Count -eq 0) {
        Add-Line 'shots: skipped (-Scenario none)'
    } else {
        $partWatch = [System.Diagnostics.Stopwatch]::StartNew()
        $shotsArgs = @{ Game = $Game; Root = $root; Quiet = $true }
        if ($scoped) { $shotsArgs.Scenario = $names }
        & (Join-Path $PSScriptRoot 'shots.ps1') @shotsArgs
        $code = $LASTEXITCODE
        Add-ToolLines (Join-Path $reports 'shots-last.txt')
        if ($code -ne 0) { $ok = $false }
        $timing += "shots $([math]::Round($partWatch.Elapsed.TotalSeconds, 1)) s"
    }
}
if ($scoped -and $t -lt 2 -and $names.Count -gt 0) { Add-Line "scenarios: not run at tier $t ($($names -join ', '))" }

$sw.Stop()
# The tree counts as clean only when it was clean before and after the run, on the same commit.
$after = Get-CheckoutState $proj
$tree = $state.Tree
if ($state.Tree -eq 'clean' -and ($after.Tree -ne 'clean' -or $after.Commit -ne $state.Commit)) { $tree = 'changed' }
if ($timing.Count -gt 0) { Add-Line ('timing: ' + ($timing -join ', ')) }
$status = 'FAIL'
if ($ok) { $status = 'PASS' }
$kind = 'VERIFY'
if ($scoped) { $kind = 'VERIFY-SCOPED' }
$header = "$kind $Game tier=$t (requested $requested, max $MaxTier) result=$status duration=$([math]::Round($sw.Elapsed.TotalSeconds, 1))s changed_files=$($files.Count) commit=$($state.Commit) content=$($state.Content) tree=$tree"
if ($scoped) {
    $list = 'none'
    if ($names.Count -gt 0) { $list = ($names -join ',') }
    $header += " scenarios=$list (scoped run: summary-scoped.txt; summary.txt keeps the last full run)"
}
$final = @($header) + $lines
if ($final.Count -gt 40) { $final = @($final | Select-Object -First 39) + @("... ($($final.Count - 39) more lines in $summaryPath)") }
Write-Lines -Lines (@($header) + $lines) -Path $summaryPath -Quiet
if (-not $Quiet) { foreach ($l in $final) { Write-Host $l } }
if ($ok) { exit 0 } else { exit 1 }
