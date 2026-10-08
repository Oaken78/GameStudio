# Headless scenario runs (tier 2): every test/scenarios/*.json or one named scenario.
# Verdict per scenario = harness exit 0 AND result.json ok AND zero error lines in the log AND budgets met.
# Writes .reports/smoke-<timestamp>/<scenario>/ and .reports/smoke-last.txt. Exit 0 pass, 1 fail.
param(
    [Parameter(Mandatory = $true)][string]$Game,
    [string]$Scenario = 'all',
    [switch]$Windowed,
    [int]$Seed = 1234,
    [int]$TimeoutSec = 0,
    [string]$Root = '',
    [switch]$Quiet
)
. "$PSScriptRoot/_lib.ps1"
$proj = Resolve-GamePath -Game $Game -Root $Root
$null = Invoke-Import -ProjectDir $proj
$ts = Get-Date -Format 'yyyyMMdd-HHmmss'
$run = New-ReportsDir $proj "smoke-$ts"
$reports = New-ReportsDir $proj

$names = @()
if ($Scenario -eq 'all') {
    $sdir = Join-Path $proj 'test\scenarios'
    if (Test-Path $sdir) { $names = @(Get-ChildItem $sdir -Filter '*.json' | ForEach-Object { $_.BaseName }) }
} else {
    $names = @($Scenario)
}

$lines = @()
$allOk = $true
if ($names.Count -eq 0) { $lines += "SMOKE $Game no scenarios found in test/scenarios (nothing to run)" }
foreach ($n in $names) {
    $out = Join-Path $run $n
    $null = New-Item -ItemType Directory -Path $out
    $res = Invoke-Scenario -ProjectDir $proj -ScenarioName $n -OutDir $out -Windowed:$Windowed -Seed $Seed -TimeoutSec $TimeoutSec
    $budget = @(Test-Budgets -ProjectDir $proj -OutDir $out)
    $ok = $res.Ok -and ($budget.Count -eq 0)
    $status = 'FAIL'
    if ($ok) { $status = 'PASS' }
    $lines += "SMOKE $n $status exit=$($res.ExitCode) seconds=$($res.Seconds) errors=$($res.ErrorLines.Count) frames=$(if ($res.Result) { $res.Result.frames } else { '?' })"
    if ($res.Result -and $res.Result.steps) {
        foreach ($s in $res.Result.steps) {
            if ($s.status -ne 'ok') { $lines += "  step $($s.index) $($s.step): $($s.status) $($s.detail)" }
        }
        if ($res.Result.message -and -not $res.Result.ok) { $lines += "  harness: $($res.Result.message)" }
    }
    if ($null -eq $res.Result) {
        $lines += "  no result.json: the harness did not finish (timeout=$($res.TimedOut)); see $out\godot.log"
        $tail = @((($res.Stdout + "`n" + $res.Stderr) -split "`r?`n") | Where-Object { $_.Trim() -ne '' } | Select-Object -Last 8)
        foreach ($t in $tail) { $lines += "  $t" }
    }
    foreach ($e in @($res.ErrorLines | Select-Object -First 20)) { $lines += "  $e" }
    $lines += $budget
    if (-not $ok) { $allOk = $false }
}
$lines += "artifacts: $run"
Write-Lines -Lines $lines -Path (Join-Path $run 'smoke-summary.txt') -Quiet
Write-Lines -Lines $lines -Path (Join-Path $reports 'smoke-last.txt') -Quiet:$Quiet
if ($allOk) { exit 0 } else { exit 1 }
