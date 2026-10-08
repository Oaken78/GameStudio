# Single entry point for verification. Picks the tier from the diff (-Tier auto) or runs the given tier.
#   tier 0: nothing   tier 1: format + parse (advisory) + unit tests   tier 2: + all tests + headless smoke
#   tier 3: + windowed screenshots compared with baselines
# Writes games/<g>/.reports/summary.txt (the only file agents need to read). Exit 0 pass, 1 fail.
param(
    [Parameter(Mandatory = $true)][string]$Game,
    [string]$Tier = 'auto',
    [int]$MaxTier = 3,
    [string]$Root = '',
    [switch]$Quiet
)
. "$PSScriptRoot/_lib.ps1"
$root = Get-RepoRoot $Root
$proj = Resolve-GamePath -Game $Game -Root $root
$gameRel = Get-GameRel -Root $root -ProjectDir $proj
$reports = New-ReportsDir $proj
$summaryPath = Join-Path $reports 'summary.txt'
$sw = [System.Diagnostics.Stopwatch]::StartNew()

$files = @(Get-ChangedFiles -Root $root -GameRel $gameRel)
$requested = $Tier
if ($Tier -eq 'auto') { $t = Get-AutoTier -Files $files -GameRel $gameRel } else { $t = [int]$Tier }
if ($t -gt $MaxTier) { $t = $MaxTier }

$lines = @()
$ok = $true
function Add-Line { param([string]$s) $script:lines += $s }

if ($t -ge 1) {
    $scripts = @(Get-ChangedScripts -Files $files -GameRel $gameRel)
    if ($Tier -ne 'auto') { $scripts = @() }
    # format check (only when gdformat is installed)
    $gdformat = Get-Command gdformat -ErrorAction SilentlyContinue
    if ($gdformat) {
        $bad = 0
        foreach ($s in $scripts) {
            $full = Join-Path $proj $s
            if (-not (Test-Path $full)) { continue }
            $null = & gdformat --check $full 2>&1
            if ($LASTEXITCODE -ne 0) { $bad++; $ok = $false; Add-Line "FORMAT FAIL $s (run: gdformat $s)" }
        }
        Add-Line "format: checked $($scripts.Count) changed scripts, $bad need formatting"
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
    Add-Line "parse: checked $parsed changed scripts (advisory)"
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
    $tsum = Join-Path $reports 'test-summary.txt'
    if (Test-Path $tsum) { foreach ($l in Get-Content $tsum) { Add-Line $l } }
    if ($code -ne 0) { $ok = $false }
}

if ($t -ge 2) {
    & (Join-Path $PSScriptRoot 'smoke.ps1') -Game $Game -Root $root -Quiet
    $code = $LASTEXITCODE
    $ssum = Join-Path $reports 'smoke-last.txt'
    if (Test-Path $ssum) { foreach ($l in Get-Content $ssum) { Add-Line $l } }
    if ($code -ne 0) { $ok = $false }
}

if ($t -ge 3) {
    & (Join-Path $PSScriptRoot 'shots.ps1') -Game $Game -Root $root -Quiet
    $code = $LASTEXITCODE
    $hsum = Join-Path $reports 'shots-last.txt'
    if (Test-Path $hsum) { foreach ($l in Get-Content $hsum) { Add-Line $l } }
    if ($code -ne 0) { $ok = $false }
}

$sw.Stop()
$status = 'FAIL'
if ($ok) { $status = 'PASS' }
$header = "VERIFY $Game tier=$t (requested $requested, max $MaxTier) result=$status duration=$([math]::Round($sw.Elapsed.TotalSeconds, 1))s changed_files=$($files.Count)"
$final = @($header) + $lines
if ($final.Count -gt 40) { $final = @($final | Select-Object -First 39) + @("... ($($final.Count - 39) more lines in $summaryPath)") }
Write-Lines -Lines (@($header) + $lines) -Path $summaryPath -Quiet
if (-not $Quiet) { foreach ($l in $final) { Write-Host $l } }
if ($ok) { exit 0 } else { exit 1 }
