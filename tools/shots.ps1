# Windowed scenario runs with screenshots (tier 3). A game window opens; that is expected.
# Compares every screenshot with test/baselines/<scenario>__<shot>.png and prints SAME / CHANGED / NEW / MISSING.
# -SaveBaseline copies this run's screenshots into test/baselines (the only sanctioned way to change them).
# Writes .reports/shots-<timestamp>/ and .reports/shots-last.txt. Exit 0 pass, 1 fail (CHANGED or MISSING counts as fail; NEW does not).
param(
    [Parameter(Mandatory = $true)][string]$Game,
    [string]$Scenario = 'all',
    [switch]$SaveBaseline,
    [string]$Shot = '',
    [int]$Seed = 1234,
    [int]$TimeoutSec = 0,
    [string]$Root = '',
    [switch]$Quiet
)
. "$PSScriptRoot/_lib.ps1"
$proj = Resolve-GamePath -Game $Game -Root $Root
$null = Invoke-Import -ProjectDir $proj
$ts = Get-Date -Format 'yyyyMMdd-HHmmss'
$run = New-ReportsDir $proj "shots-$ts"
$reports = New-ReportsDir $proj
$bdir = Join-Path $proj 'test\baselines'
if (-not (Test-Path $bdir)) { $null = New-Item -ItemType Directory -Path $bdir }
$gdi = Join-Path $bdir '.gdignore'
if (-not (Test-Path $gdi)) { $null = New-Item -ItemType File -Path $gdi }

$threshold = 0.02
$bf = Join-Path $proj 'design\budgets.json'
if (Test-Path $bf) {
    try {
        $b = Get-Content $bf -Raw | ConvertFrom-Json
        if ($b.screens -and $b.screens.rmse_threshold) { $threshold = [double]$b.screens.rmse_threshold }
    } catch { }
}

$names = @()
if ($Scenario -eq 'all') {
    $sdir = Join-Path $proj 'test\scenarios'
    if (Test-Path $sdir) { $names = @(Get-ChildItem $sdir -Filter '*.json' | ForEach-Object { $_.BaseName }) }
} else {
    $names = @($Scenario)
}

$lines = @()
$allOk = $true
foreach ($n in $names) {
    $out = Join-Path $run $n
    $null = New-Item -ItemType Directory -Path $out
    $res = Invoke-Scenario -ProjectDir $proj -ScenarioName $n -OutDir $out -Windowed -Screens -Seed $Seed -TimeoutSec $TimeoutSec
    $budget = @(Test-Budgets -ProjectDir $proj -OutDir $out)
    $ok = $res.Ok -and ($budget.Count -eq 0)
    $status = 'FAIL'
    if ($ok) { $status = 'PASS' }
    $lines += "SHOTS $n $status exit=$($res.ExitCode) seconds=$($res.Seconds) errors=$($res.ErrorLines.Count)"
    if ($res.Result -and $res.Result.steps) {
        foreach ($s in $res.Result.steps) {
            if ($s.status -ne 'ok') { $lines += "  step $($s.index) $($s.step): $($s.status) $($s.detail)" }
        }
    }
    if ($null -eq $res.Result) {
        $lines += "  no result.json: the harness did not finish (timeout=$($res.TimedOut)); see $out\godot.log"
    }
    foreach ($e in @($res.ErrorLines | Select-Object -First 20)) { $lines += "  $e" }
    $lines += $budget

    $pngs = @(Get-ChildItem $out -Filter '*.png' -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike '*__diff.png' })
    if ($pngs.Count -gt 0) {
        if ($SaveBaseline) {
            foreach ($png in $pngs) {
                if ($Shot -and $png.BaseName -ne $Shot) { continue }
                $dest = Join-Path $bdir ($n + '__' + $png.BaseName + '.png')
                Copy-Item $png.FullName $dest -Force
                $lines += ('  BASELINE saved ' + $n + '__' + $png.BaseName + '.png')
            }
        }
        $cmpReport = Join-Path $out 'compare.json'
        $cmpArgs = @('--headless', '--path', $proj, '-s', 'res://test/compare_screens.gd', '--',
            ('--shots=' + (ConvertTo-ForwardSlash $out)), ('--baselines=' + (ConvertTo-ForwardSlash $bdir)),
            ('--report=' + (ConvertTo-ForwardSlash $cmpReport)), ('--prefix=' + $n), ('--threshold=' + (Format-Invariant $threshold)))
        $c = Invoke-Godot -GodotArgs $cmpArgs -TimeoutSec 120 -WorkDir $proj
        if (Test-Path $cmpReport) {
            try {
                $cj = Get-Content $cmpReport -Raw | ConvertFrom-Json
                foreach ($e in $cj.results) {
                    $rm = ''
                    if ($e.rmse -ge 0) { $rm = ' rmse=' + (Format-Invariant ([double]$e.rmse)) }
                    $lines += ('  SHOT ' + $n + '__' + $e.shot + ' ' + $e.status + $rm)
                    if ($e.status -eq 'CHANGED' -and $e.diff) { $lines += ('    diff: ' + $e.diff) }
                    if ($e.status -in @('CHANGED', 'MISSING', 'ERROR')) { $ok = $false }
                }
            } catch { $lines += "  compare: could not read compare.json ($($_.Exception.Message))"; $ok = $false }
        } else {
            $lines += "  compare: no report written (exit $($c.ExitCode)); $($c.Stderr)"
            $ok = $false
        }
    } elseif ($res.Result -and -not $res.Result.headless) {
        $lines += '  no screenshots produced (no screenshot steps in this scenario)'
    }
    if (-not $ok) { $allOk = $false }
}
if ($names.Count -eq 0) { $lines += "SHOTS $Game no scenarios found in test/scenarios" }
$lines += "artifacts: $run"
Write-Lines -Lines $lines -Path (Join-Path $run 'shots-summary.txt') -Quiet
Write-Lines -Lines $lines -Path (Join-Path $reports 'shots-last.txt') -Quiet:$Quiet
if ($allOk) { exit 0 } else { exit 1 }
