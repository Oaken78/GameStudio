# Headless scenario runs (tier 2): every test/scenarios/*.json, or the named ones (-Scenario a,b).
# Verdict per scenario = harness exit 0 AND result.json ok AND zero error lines in the log AND budgets met.
# Runs -Jobs scenarios at a time (default 3), each in its own Godot process, folder and log. Timing-sensitive
# scenarios (metrics step, *_ms asserts, perf_*, world_stream*, frame_cold: Get-ScenarioInfo in _lib.ps1) run alone
# afterwards, one at a time. Lines come out in scenario order whatever the run order. -Jobs 1 runs everything one at
# a time in that order; -Windowed always does (one window at a time, through the window lock).
# Writes .reports/smoke-<timestamp>/<scenario>/ and .reports/smoke-last.txt. Exit 0 pass, 1 fail.
param(
    [Parameter(Mandatory = $true)][string]$Game,
    [string[]]$Scenario = @('all'),
    [switch]$Windowed,
    [int]$Jobs = 3,
    [int]$Seed = 1234,
    [int]$TimeoutSec = 0,
    [int]$LockTimeoutSec = 1800,
    [string]$Root = '',
    [switch]$Quiet
)
. "$PSScriptRoot/_lib.ps1"
$proj = Resolve-GamePath -Game $Game -Root $Root
$null = Invoke-Import -ProjectDir $proj
$ts = Get-Date -Format 'yyyyMMdd-HHmmss'
$run = New-ReportsDir $proj "smoke-$ts"
$reports = New-ReportsDir $proj
$state = Get-CheckoutState $proj
$sw = [System.Diagnostics.Stopwatch]::StartNew()

$names = @(Get-ScenarioNames -ProjectDir $proj -Scenario $Scenario)
$parallel = @()
$serial = @()
foreach ($n in $names) {
    $info = Get-ScenarioInfo -ProjectDir $proj -Name $n
    if ($Windowed -or $Jobs -le 1 -or $info.Serial) { $serial += $n } else { $parallel += $n }
}

# Parallel batch: keep up to $Jobs headless runs going; collect each as it finishes.
$results = @{}
$queue = New-Object System.Collections.Queue
foreach ($n in $parallel) { $queue.Enqueue($n) }
$running = @()
while ($queue.Count -gt 0 -or $running.Count -gt 0) {
    while ($queue.Count -gt 0 -and $running.Count -lt $Jobs) {
        $n = $queue.Dequeue()
        $out = Join-Path $run $n
        $null = New-Item -ItemType Directory -Path $out
        $running += Start-Scenario -ProjectDir $proj -ScenarioName $n -OutDir $out -Seed $Seed -TimeoutSec $TimeoutSec
    }
    $still = @()
    foreach ($job in $running) {
        if (Test-GodotDone $job.Run) { $results[$job.ScenarioName] = Complete-Scenario $job } else { $still += $job }
    }
    $running = $still
    if ($running.Count -gt 0) { Start-Sleep -Milliseconds 100 }
}

# Then the rest, alone and in order. A window lock timeout stops the windowed runs that are left.
$lockFailed = $false
foreach ($n in $serial) {
    if ($lockFailed) { continue }
    $out = Join-Path $run $n
    $null = New-Item -ItemType Directory -Path $out
    $res = Invoke-Scenario -ProjectDir $proj -ScenarioName $n -OutDir $out -Windowed:$Windowed -Seed $Seed -TimeoutSec $TimeoutSec -LockTimeoutSec $LockTimeoutSec
    $results[$n] = $res
    if ($res.LockFailed) { $lockFailed = $true }
}
$sw.Stop()

$lines = @()
$allOk = $true
if ($names.Count -eq 0) { $lines += "SMOKE $Game no scenarios found in test/scenarios (nothing to run)" }
foreach ($n in $names) {
    if (-not $results.ContainsKey($n)) {
        $lines += "SMOKE $n FAIL not run (window lock timeout above)"
        $allOk = $false
        continue
    }
    $res = $results[$n]
    $out = $res.OutDir
    $budget = @(Test-Budgets -ProjectDir $proj -OutDir $out)
    $ok = $res.Ok -and ($budget.Count -eq 0)
    $status = 'FAIL'
    if ($ok) { $status = 'PASS' }
    $lines += "SMOKE $n $status exit=$($res.ExitCode) seconds=$($res.Seconds) errors=$($res.ErrorLines.Count) frames=$(if ($res.Result) { $res.Result.frames } else { '?' })"
    if ($res.LockWaitedSec -ge 1) { $lines += "  waited $($res.LockWaitedSec) s for the window lock" }
    if ($res.LockFailed) {
        $lines += "  $($res.Stderr)"
        $allOk = $false
        continue
    }
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
$secs = [math]::Round($sw.Elapsed.TotalSeconds, 1)
if ($parallel.Count -gt 0) {
    $alone = 'none'
    if ($serial.Count -gt 0) { $alone = ($serial -join ', ') }
    $lines += "smoke: $($names.Count) scenarios in $secs s; $($parallel.Count) headless $Jobs at a time, then $($serial.Count) alone (timing-sensitive): $alone"
} elseif ($names.Count -gt 0) {
    $why = "-Jobs $Jobs"
    if ($Windowed) { $why = '-Windowed' } elseif ($Jobs -gt 1) { $why = 'all timing-sensitive' }
    $lines += "smoke: $($names.Count) scenarios in $secs s, one at a time ($why)"
}
$lines += "checkout: $($state.Text)"
$lines += "artifacts: $run"
Write-Lines -Lines $lines -Path (Join-Path $run 'smoke-summary.txt') -Quiet
Write-Lines -Lines $lines -Path (Join-Path $reports 'smoke-last.txt') -Quiet:$Quiet
if ($allOk) { exit 0 } else { exit 1 }
