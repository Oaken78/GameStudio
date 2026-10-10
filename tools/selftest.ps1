# End-to-end proof that the environment works, on a throwaway game (games/selftest-tmp).
# Run after changing tools/ or templates/. Prints a table and timings. Exit 0 when no step FAILed.
# Also covers parallel smoke (order, timeout, crash), the scenario rules, the window lock, the commit record in
# summary.txt, scoped verify and the stop gate. The window-lock-wait step holds the real lock for about 4 s.
#   ./tools/selftest.ps1 [-Keep] [-SkipWindowed]
param(
    [switch]$Keep,
    [switch]$SkipWindowed,
    [string]$Root = ''
)
. "$PSScriptRoot/_lib.ps1"
$root = Get-RepoRoot $Root
$gameName = 'selftest-tmp'
$proj = Join-Path $root (Join-Path 'games' $gameName)
$gutPresent = Test-Path (Join-Path $root 'templates\game-template\addons\gut\gut_cmdln.gd')
$results = New-Object System.Collections.ArrayList
$total = [System.Diagnostics.Stopwatch]::StartNew()

function Add-Result {
    param($Step, $Status, $Detail, $Seconds)
    $null = $script:results.Add([pscustomobject]@{ Step = $Step; Status = $Status; Detail = $Detail; Seconds = $Seconds })
    Write-Host ("[{0,-4}] {1,-28} {2,6}s  {3}" -f $Status, $Step, $Seconds, $Detail)
}

function Invoke-Step {
    # Note: step bodies run in a child scope of this function, so its locals must not shadow script variables.
    param([string]$StepLabel, [scriptblock]$StepBody)
    $stepWatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $stepDetail = & $StepBody
        $stepWatch.Stop()
        $stepText = ''
        if ($null -ne $stepDetail) { $stepText = (@($stepDetail) | ForEach-Object { [string]$_ }) -join ' ' }
        $stepStatus = 'PASS'
        if ($stepText.StartsWith('SKIP')) { $stepStatus = 'SKIP' } elseif ($stepText.StartsWith('INFO')) { $stepStatus = 'INFO' }
        Add-Result $StepLabel $stepStatus $stepText ([math]::Round($stepWatch.Elapsed.TotalSeconds, 1))
    } catch {
        $stepWatch.Stop()
        Add-Result $StepLabel 'FAIL' $_.Exception.Message ([math]::Round($stepWatch.Elapsed.TotalSeconds, 1))
    }
}

function Get-ShotsLine {
    param([string]$Pattern)
    $sum = @(Get-Content (Join-Path $proj '.reports\shots-last.txt'))
    $line = @($sum | Where-Object { $_ -like $Pattern } | Select-Object -First 1)
    if ($line.Count -eq 0) { throw ("no line matching $Pattern in shots-last.txt: " + ($sum -join ' | ')) }
    return $line[0].Trim()
}

# Starts a separate PowerShell process that takes the named window lock, says so through a file, holds the lock
# for HoldSec and releases it. Returns the process (kill it to make Windows abandon the lock).
function Start-LockHolder {
    param([string]$Name, [int]$HoldSec, [int]$ReadyTimeoutSec = 600)
    $ready = Join-Path ([System.IO.Path]::GetTempPath()) ('gamestudio-selftest-holder-' + $PID + '.txt')
    if (Test-Path $ready) { Remove-Item $ready -Force }
    $cmd = "`$m = New-Object System.Threading.Mutex(`$false, '$Name'); try { `$null = `$m.WaitOne(600000) } catch [System.Threading.AbandonedMutexException] { }; [System.IO.File]::WriteAllText('$ready', 'held'); Start-Sleep -Seconds $HoldSec; `$m.ReleaseMutex()"
    $p = Start-Process powershell.exe -ArgumentList @('-NoProfile', '-Command', $cmd) -PassThru -WindowStyle Hidden
    $wait = [System.Diagnostics.Stopwatch]::StartNew()
    while (-not (Test-Path $ready)) {
        if ($p.HasExited -or $wait.Elapsed.TotalSeconds -gt $ReadyTimeoutSec) { throw "the lock holder process did not get $Name" }
        Start-Sleep -Milliseconds 100
    }
    Remove-Item $ready -Force
    return $p
}

# Commits everything in the throwaway game repo (its own identity, so nothing is attributed to a person).
function Save-SelftestCommit {
    param([string]$Message)
    $null = git -C $proj add -A 2>$null
    $null = git -C $proj -c user.name=selftest -c user.email=selftest@localhost commit -q -m $Message 2>$null
    if ($LASTEXITCODE -ne 0) { throw "git commit failed in games/$gameName" }
    return ([string](git -C $proj rev-parse --short HEAD)).Trim()
}

Write-Host "selftest: Godot environment check on games/$gameName (GUT vendored: $gutPresent)"

Invoke-Step 'godot-version' {
    $r = Invoke-Godot -GodotArgs @('--version') -TimeoutSec 60
    if ($r.Stdout -notmatch '4\.7') { throw "unexpected Godot version: $($r.Stdout.Trim())" }
    return ('Godot ' + $r.Stdout.Trim() + ' at ' + (Get-GodotBin))
}

Invoke-Step 'scaffold' {
    if (Test-Path $proj) { Remove-Item $proj -Recurse -Force }
    $null = & (Join-Path $PSScriptRoot 'new-game.ps1') -Name $gameName -Root $root
    if (-not (Test-Path (Join-Path $proj 'project.godot'))) { throw 'new-game.ps1 did not create project.godot' }
    return "games/$gameName created from the template"
}

Invoke-Step 'import' {
    $r = Invoke-Import -ProjectDir $proj -Force
    if (-not (Test-Path (Join-Path $proj '.godot\global_script_class_cache.cfg'))) { throw 'no .godot/global_script_class_cache.cfg after --import' }
    return ('import took ' + $r.Seconds + 's, exit ' + $r.ExitCode)
}

Invoke-Step 'unit-tests' {
    if (-not $gutPresent) { return 'SKIP: GUT not vendored (run ./tools/vendor-gut.ps1)' }
    & (Join-Path $PSScriptRoot 'test.ps1') -Game $gameName -Root $root -Quiet
    $code = $LASTEXITCODE
    $sum = @(Get-Content (Join-Path $proj '.reports\test-summary.txt'))
    if ($code -ne 0) { throw ("test.ps1 exit $code : " + ($sum -join ' | ')) }
    return $sum[0]
}

Invoke-Step 'unit-test-failure-detected' {
    if (-not $gutPresent) { return 'SKIP: GUT not vendored' }
    $f = Join-Path $proj 'test\unit\test_zz_selftest_fail.gd'
    $src = "extends GutTest`n`n`nfunc test_this_must_fail() -> void:`n`tassert_eq(1, 2, `"selftest: deliberate failure`")`n"
    [System.IO.File]::WriteAllText($f, $src)
    try {
        & (Join-Path $PSScriptRoot 'test.ps1') -Game $gameName -Root $root -File 'test/unit/test_zz_selftest_fail.gd' -Quiet
        $code = $LASTEXITCODE
        $sum = @(Get-Content (Join-Path $proj '.reports\test-summary.txt'))
        if ($code -ne 1) { throw ("expected exit 1 for a failing test, got $code : " + ($sum -join ' | ')) }
        $failLine = @($sum | Where-Object { $_ -like '*FAIL *' } | Select-Object -First 1)
        if ($failLine.Count -eq 0) { throw 'summary does not list the failing test' }
        return ('exit 1 and listed: ' + $failLine[0].Trim())
    } finally {
        Remove-Item $f -Force
        $uid = $f + '.uid'
        if (Test-Path $uid) { Remove-Item $uid -Force }
    }
}

Invoke-Step 'scenario-exit-code' {
    $sdir = Join-Path $proj 'test\scenarios'
    $json = '{"scene":"res://scenes/main.tscn","timeout_frames":600,"steps":[{"wait_frames":5},{"assert_prop":{"node":"Player","prop":"position:x","op":"==","value":-12345}}]}'
    [System.IO.File]::WriteAllText((Join-Path $sdir 'zz_fail.json'), $json)
    $out = New-ReportsDir $proj 'selftest\zz_fail'
    try { $res = Invoke-Scenario -ProjectDir $proj -ScenarioName 'zz_fail' -OutDir $out }
    finally { Remove-Item (Join-Path $sdir 'zz_fail.json') -Force }
    if ($null -eq $res.Result) { throw "no result.json (exit $($res.ExitCode)); see $out\godot.log" }
    if ($res.ExitCode -ne 10) { throw "expected process exit 10 from SceneTree.quit(10), got $($res.ExitCode) (harness code $($res.Result.code))" }
    return 'SceneTree.quit(10) arrived as process exit 10 through the console wrapper'
}

Invoke-Step 'smoke-boot-headless' {
    $out = New-ReportsDir $proj 'selftest\boot'
    $res = Invoke-Scenario -ProjectDir $proj -ScenarioName 'boot' -OutDir $out
    if (-not (Test-Path (Join-Path $out 'godot.log'))) { throw 'no godot.log written by --log-file' }
    if ($null -eq $res.Result) { throw "no result.json (exit $($res.ExitCode)); see $out\godot.log" }
    if (-not $res.Ok) { throw ('boot scenario failed: exit ' + $res.ExitCode + ' msg=' + $res.Result.message + ' errors=' + ($res.ErrorLines -join ' | ')) }
    $m = Test-Path (Join-Path $out 'metrics__boot.json')
    return ('ok in ' + $res.Seconds + 's, ' + $res.Result.frames + ' frames, metrics written=' + $m)
}

Invoke-Step 'error-capture' {
    $sdir = Join-Path $proj 'test\scenarios'
    $json = '{"scene":"res://scenes/main.tscn","timeout_frames":600,"steps":[{"wait_frames":5},{"inject_error":"selftest"},{"wait_frames":2},{"assert_no_errors":true}]}'
    [System.IO.File]::WriteAllText((Join-Path $sdir 'zz_error.json'), $json)
    $out = New-ReportsDir $proj 'selftest\zz_error'
    try { $res = Invoke-Scenario -ProjectDir $proj -ScenarioName 'zz_error' -OutDir $out }
    finally { Remove-Item (Join-Path $sdir 'zz_error.json') -Force }
    if ($null -eq $res.Result) { throw "no result.json (exit $($res.ExitCode))" }
    $loggerCaught = ($res.Result.code -eq 11)
    $scanCaught = ($res.ErrorLines.Count -gt 0)
    if (-not $loggerCaught -and -not $scanCaught) { throw "push_error was detected neither by the Logger (code $($res.Result.code)) nor by the log scan" }
    return ('Logger caught=' + $loggerCaught + ' log-scan caught=' + $scanCaught + ' exit=' + $res.ExitCode)
}

Invoke-Step 'headless-input' {
    $out = New-ReportsDir $proj 'selftest\move_right'
    $res = Invoke-Scenario -ProjectDir $proj -ScenarioName 'move_right' -OutDir $out
    if ($res.Ok) { return 'INFO: headless input works (parse_input_event moved the player), so input scenarios can run headless' }
    $detail = "exit $($res.ExitCode)"
    if ($res.Result) { $detail = $res.Result.message }
    return ('INFO: headless input FAILED (' + $detail + '); run input scenarios windowed (smoke.ps1 -Windowed)')
}

Invoke-Step 'windowed-shots-baseline' {
    if ($SkipWindowed) { return 'SKIP: -SkipWindowed' }
    & (Join-Path $PSScriptRoot 'shots.ps1') -Game $gameName -Root $root -SaveBaseline -Quiet
    $code = $LASTEXITCODE
    $sum = @(Get-Content (Join-Path $proj '.reports\shots-last.txt'))
    $art = @($sum | Where-Object { $_.StartsWith('artifacts: ') } | Select-Object -Last 1)
    if ($art.Count -eq 0) { throw ('no artifacts line: ' + ($sum -join ' | ')) }
    $runDir = $art[0].Substring(11).Trim()
    $png = Join-Path $runDir 'boot\boot.png'
    if (-not (Test-Path $png)) { throw ('no boot.png produced; summary: ' + ($sum -join ' | ')) }
    Add-Type -AssemblyName System.Drawing
    $bmp = [System.Drawing.Bitmap]::FromFile($png)
    $acc = 0.0
    $count = 0
    for ($y = 0; $y -lt $bmp.Height; $y += 16) {
        for ($x = 0; $x -lt $bmp.Width; $x += 16) {
            $c = $bmp.GetPixel($x, $y)
            $acc += ($c.R + $c.G + $c.B) / 3.0
            $count++
        }
    }
    $w = $bmp.Width
    $h = $bmp.Height
    $bmp.Dispose()
    $mean = [math]::Round($acc / $count, 1)
    if ($mean -le 1) { throw "boot.png is black (mean pixel $mean)" }
    $metrics = Test-Path (Join-Path $runDir 'boot\metrics__boot.json')
    if ($code -ne 0) { throw ("shots.ps1 exit $code : " + (@($sum | Where-Object { $_ -match 'FAIL|MISSING|CHANGED|ERROR' }) -join ' | ')) }
    $shotLines = @($sum | Where-Object { $_ -like '*SHOT *' }) | ForEach-Object { $_.Trim() }
    return ("boot.png ${w}x${h} mean=$mean metrics=$metrics; " + ($shotLines -join '; '))
}

Invoke-Step 'compare-same' {
    if ($SkipWindowed) { return 'SKIP: -SkipWindowed' }
    & (Join-Path $PSScriptRoot 'shots.ps1') -Game $gameName -Root $root -Scenario boot -Quiet
    $line = Get-ShotsLine '*SHOT boot__boot *'
    if ($line -notlike '*SAME*') { throw "expected SAME for boot__boot, got: $line" }
    return $line
}

Invoke-Step 'compare-changed' {
    if ($SkipWindowed) { return 'SKIP: -SkipWindowed' }
    $b = Join-Path $proj 'test\baselines'
    $src = Join-Path $b 'move_right__after_move.png'
    if (-not (Test-Path $src)) { throw 'no move_right__after_move.png baseline (did the move_right scenario capture a screenshot?)' }
    Copy-Item $src (Join-Path $b 'boot__boot.png') -Force
    & (Join-Path $PSScriptRoot 'shots.ps1') -Game $gameName -Root $root -Scenario boot -Quiet
    $line = Get-ShotsLine '*SHOT boot__boot *'
    if ($line -notlike '*CHANGED*') { throw "expected CHANGED after swapping the baseline, got: $line" }
    return ($line + ' (player moved 120 px: calibrate screens.rmse_threshold in design/budgets.json below this)')
}

Invoke-Step 'verify-auto-tier1' {
    & (Join-Path $PSScriptRoot 'verify.ps1') -Game $gameName -Root $root -Tier auto -MaxTier 1 -Quiet
    $code = $LASTEXITCODE
    $sum = @(Get-Content (Join-Path $proj '.reports\summary.txt'))
    if (-not $gutPresent) { return ('SKIP: GUT not vendored; ' + $sum[0]) }
    if ($code -ne 0) { throw ("verify.ps1 exit $code : " + ($sum -join ' | ')) }
    return $sum[0]
}

Invoke-Step 'scenario-rules' {
    $sdir = Join-Path $proj 'test\scenarios'
    $made = @{
        'zz_rule_plain' = '{"scene":"res://scenes/main.tscn","steps":[{"wait_frames":5}]}'
        'zz_rule_ms'    = '{"scene":"res://scenes/main.tscn","steps":[{"assert_prop":{"node":"Player","prop":"tick_p99_ms","op":"<=","value":3}}]}'
        'zz_rule_flag'  = '{"scene":"res://scenes/main.tscn","serial":true,"steps":[{"wait_frames":5}]}'
        'perf_zz_rule'  = '{"scene":"res://scenes/main.tscn","steps":[{"wait_frames":5}]}'
    }
    foreach ($k in $made.Keys) { [System.IO.File]::WriteAllText((Join-Path $sdir "$k.json"), $made[$k]) }
    try {
        # expected Windowed/Serial per scenario
        $expect = [ordered]@{ boot = 'True/True'; move_right = 'True/False'; zz_rule_plain = 'False/False'
            zz_rule_ms = 'False/False'; zz_rule_flag = 'False/True'; perf_zz_rule = 'False/True' }
        $bad = @()
        foreach ($k in $expect.Keys) {
            $info = Get-ScenarioInfo -ProjectDir $proj -Name $k
            $got = "$($info.Windowed)/$($info.Serial)"
            if ($got -ne $expect[$k]) { $bad += "$k windowed/serial=$got, expected $($expect[$k])" }
        }
        if ($bad.Count -gt 0) { throw ($bad -join '; ') }
    } finally {
        foreach ($k in $made.Keys) { Remove-Item (Join-Path $sdir "$k.json") -Force }
    }
    return 'windowed: screenshot or metrics step; alone: metrics step, perf_* name, "serial": true; a *_ms assert stays parallel'
}

Invoke-Step 'smoke-parallel' {
    $sdir = Join-Path $proj 'test\scenarios'
    $tdir = Join-Path $proj 'test'
    # zz_slow takes 50 ms a frame (hits the 8 s process timeout); zz_quit exits before the harness finishes (a crash,
    # as far as the tools can tell); zz_p_fail fails an assert. They run 3 at a time next to passing ones.
    # zz_cost fakes wall-clock asserts: cost_ms fails in the parallel batch and passes in the alone retry (its --out
    # folder ends in --alone); stuck_ms fails both times. zz_p_fail (position:x) must not be retried.
    $made = @{
        'zz_slow.gd'   = "extends Node`n`n`nfunc _process(_delta: float) -> void:`n`tOS.delay_msec(50)`n"
        'zz_quit.gd'   = "extends Node`n`n`nfunc _ready() -> void:`n`tget_tree().quit(3)`n"
        'zz_slow.tscn' = "[gd_scene format=3]`n`n[ext_resource type=`"Script`" path=`"res://test/zz_slow.gd`" id=`"1`"]`n`n[node name=`"Slow`" type=`"Node`"]`nscript = ExtResource(`"1`")`n"
        'zz_cost.gd'   = "extends Node`n`nvar cost_ms: float = 5.0`nvar stuck_ms: float = 5.0`n`n`nfunc _ready() -> void:`n`tfor a: String in OS.get_cmdline_user_args():`n`t`tif a.begins_with(`"--out=`") and a.ends_with(`"--alone`"):`n`t`t`tcost_ms = 0.5`n"
        'zz_cost.tscn' = "[gd_scene format=3]`n`n[ext_resource type=`"Script`" path=`"res://test/zz_cost.gd`" id=`"1`"]`n`n[node name=`"Cost`" type=`"Node`"]`nscript = ExtResource(`"1`")`n"
        'zz_quit.tscn' = "[gd_scene format=3]`n`n[ext_resource type=`"Script`" path=`"res://test/zz_quit.gd`" id=`"1`"]`n`n[node name=`"Quit`" type=`"Node`"]`nscript = ExtResource(`"1`")`n"
        'scenarios\zz_p_ok.json'   = '{"scene":"res://scenes/main.tscn","timeout_frames":600,"steps":[{"wait_frames":5},{"assert_no_errors":true}]}'
        'scenarios\zz_p_fail.json' = '{"scene":"res://scenes/main.tscn","timeout_frames":600,"steps":[{"wait_frames":5},{"assert_prop":{"node":"Player","prop":"position:x","op":"==","value":-12345}}]}'
        'scenarios\zz_p_slow.json' = '{"scene":"res://test/zz_slow.tscn","timeout_frames":7100,"steps":[{"wait_frames":7000}]}'
        'scenarios\zz_p_quit.json' = '{"scene":"res://test/zz_quit.tscn","timeout_frames":600,"steps":[{"wait_frames":30}]}'
        'scenarios\zz_p_cost.json' = '{"scene":"res://test/zz_cost.tscn","timeout_frames":600,"steps":[{"wait_frames":5},{"assert_prop":{"node":".","prop":"cost_ms","op":"<=","value":1.0}}]}'
        'scenarios\zz_p_stuck.json' = '{"scene":"res://test/zz_cost.tscn","timeout_frames":600,"steps":[{"wait_frames":5},{"assert_prop":{"node":".","prop":"stuck_ms","op":"<=","value":1.0}}]}'
    }
    foreach ($k in $made.Keys) { [System.IO.File]::WriteAllText((Join-Path $tdir $k), $made[$k]) }
    $order = @('zz_p_ok', 'zz_p_fail', 'zz_p_slow', 'boot', 'zz_p_quit', 'move_right', 'zz_p_cost', 'zz_p_stuck')
    $godotDir = Join-Path $proj '.godot'
    $started = Get-Date
    try {
        & (Join-Path $PSScriptRoot 'smoke.ps1') -Game $gameName -Root $root -Scenario ($order -join ',') -Jobs 3 -TimeoutSec 8 -Quiet
        $code = $LASTEXITCODE
    } finally {
        foreach ($k in $made.Keys) {
            foreach ($f in @((Join-Path $tdir $k), (Join-Path $tdir ($k + '.uid')))) { if (Test-Path $f) { Remove-Item $f -Force } }
        }
    }
    $sum = @(Get-Content (Join-Path $proj '.reports\smoke-last.txt'))
    $all = $sum -join ' | '
    if ($code -ne 1) { throw "expected exit 1, got $code : $all" }
    $smokeLines = @($sum | Where-Object { $_ -like 'SMOKE *' })
    $seen = @($smokeLines | ForEach-Object { ($_ -split ' ')[1] }) -join ','
    if ($seen -ne ($order -join ',')) { throw "summary order $seen, expected $($order -join ',')" }
    $want = [ordered]@{ zz_p_ok = '* PASS *'; zz_p_fail = '* FAIL *'; zz_p_slow = '* FAIL exit=124 *'; boot = '* PASS *'
        zz_p_quit = '* FAIL exit=3 *'; move_right = '* PASS *'; zz_p_cost = '* PASS *'; zz_p_stuck = '* FAIL exit=10 *' }
    foreach ($n in $want.Keys) {
        $l = @($smokeLines | Where-Object { $_ -like "SMOKE $n *" })[0]
        if ($l -notlike $want[$n]) { throw "SMOKE $n line '$l' does not match '$($want[$n])'" }
    }
    if ($all -notlike '*step 2 assert_prop: fail*') { throw "the failed assert step is not listed: $all" }
    if ($all -notlike '*did not finish (timeout=True)*') { throw "the timeout is not reported: $all" }
    $runLine = @($sum | Where-Object { $_ -like 'smoke: *' })
    if ($runLine.Count -eq 0 -or $runLine[0] -notlike '*7 headless 3 at a time (2 retried alone), then 1 alone (*): boot') { throw "unexpected run line: $all" }
    $retry = @($sum | Where-Object { $_ -like '  retried alone *' })
    if ($retry.Count -ne 2) { throw ('expected 2 retry lines (zz_p_cost, zz_p_stuck): ' + ($retry -join ' | ')) }
    if ($retry[0] -notlike '*parallel step 2 *cost_ms is 5*alone PASS*') { throw "zz_p_cost retry line: $($retry[0])" }
    if ($retry[1] -notlike '*parallel step 2 *stuck_ms is 5*alone step 2 *stuck_ms is 5*') { throw "zz_p_stuck retry line: $($retry[1])" }
    $art = @($sum | Where-Object { $_.StartsWith('artifacts: ') })[0].Substring(11).Trim()
    foreach ($n in $order) { if (-not (Test-Path (Join-Path $art "$n\godot.log"))) { throw "no own godot.log for $n" } }
    $touched = @(Get-ChildItem $godotDir -Recurse -File | Where-Object { $_.LastWriteTime -gt $started })
    if ($touched.Count -gt 0) { throw ('parallel runs wrote into .godot/: ' + (($touched | Select-Object -First 3 -ExpandProperty Name) -join ', ')) }
    return ($runLine[0] + '; order kept, timeout/crash/assert reported, wall-clock fails retried alone, one log per run, .godot untouched')
}

Invoke-Step 'window-lock-timeout' {
    # A private lock name, so a real windowed run elsewhere on the machine is never blocked by this test.
    $name = 'Global\GameStudio-selftest-' + $PID
    $holder = Start-LockHolder -Name $name -HoldSec 120 -ReadyTimeoutSec 60
    try {
        $env:GAMESTUDIO_WINDOW_LOCK = $name
        & (Join-Path $PSScriptRoot 'shots.ps1') -Game $gameName -Root $root -Scenario move_right -LockTimeoutSec 3 -Quiet 6>$null
        $code = $LASTEXITCODE
        $line = Get-ShotsLine 'SHOTS move_right *'
        if ($code -ne 1 -or $line -notlike '*FAIL window lock: gave up after 3 s*') { throw "expected a lock FAIL, got exit $code : $line" }
        Stop-Process -Id $holder.Id -Force
        $holder.WaitForExit()
        $lock = Enter-WindowLock -Name $name -TimeoutSec 10 -Label 'selftest'
        Exit-WindowLock $lock
        if (-not $lock.Acquired) { throw 'the lock was not free after its holder process died' }
    } finally {
        Remove-Item Env:GAMESTUDIO_WINDOW_LOCK -ErrorAction SilentlyContinue
        if (-not $holder.HasExited) { Stop-Process -Id $holder.Id -Force }
    }
    return ($line + '; free at once after the holder process was killed')
}

Invoke-Step 'window-lock-wait' {
    if ($SkipWindowed) { return 'SKIP: -SkipWindowed' }
    $holder = Start-LockHolder -Name (Get-WindowLockName) -HoldSec 4
    try {
        & (Join-Path $PSScriptRoot 'shots.ps1') -Game $gameName -Root $root -Scenario move_right -Quiet 6>$null
    } finally {
        if (-not $holder.HasExited) { Stop-Process -Id $holder.Id -Force }
    }
    $line = Get-ShotsLine '  waited * s for the window lock'
    if ($line -notmatch 'waited ([0-9.]+) s' -or [double]$Matches[1] -lt 2) { throw "expected a wait of about 4 s, got: $line" }
    $pass = Get-ShotsLine 'SHOTS move_right *'
    if ($pass -notlike '* PASS *') { throw "the run after the wait failed: $pass" }
    # shots.ps1 must have released the lock: another process gets it at once.
    $next = Start-LockHolder -Name (Get-WindowLockName) -HoldSec 0 -ReadyTimeoutSec 120
    $next.WaitForExit()
    return ($pass + '; ' + $line + '; released afterwards')
}

Invoke-Step 'verify-commit-record' {
    if (-not $gutPresent) { return 'SKIP: GUT not vendored' }
    $head = Save-SelftestCommit 'selftest: everything so far'
    & (Join-Path $PSScriptRoot 'verify.ps1') -Game $gameName -Root $root -Tier 1 -Quiet
    $first = @(Get-Content (Join-Path $proj '.reports\summary.txt') -TotalCount 1)[0]
    if ($first -notlike "* result=PASS *commit=$head *tree=clean*") { throw "header does not record a clean PASS of $head : $first" }
    & (Join-Path $PSScriptRoot 'verify.ps1') -Game $gameName -Root $root -Tier 1 -CheckFresh 6>$null
    if ($LASTEXITCODE -ne 0) { throw 'CheckFresh at tier 1 said STALE for the same commit' }
    & (Join-Path $PSScriptRoot 'verify.ps1') -Game $gameName -Root $root -Tier 2 -CheckFresh 6>$null
    if ($LASTEXITCODE -ne 1) { throw 'CheckFresh at tier 2 said FRESH for a tier 1 run' }
    $note = Join-Path $proj 'design\zz_selftest_note.md'
    [System.IO.File]::WriteAllText($note, 'uncommitted')
    try {
        & (Join-Path $PSScriptRoot 'verify.ps1') -Game $gameName -Root $root -Tier 1 -CheckFresh 6>$null
        $dirtyCode = $LASTEXITCODE
    } finally { Remove-Item $note -Force }
    if ($dirtyCode -ne 1) { throw 'CheckFresh said FRESH with an uncommitted file in the checkout' }
    return ($first + '; CheckFresh: tier 1 FRESH, tier 2 STALE, dirty STALE')
}

Invoke-Step 'verify-scoped' {
    if (-not $gutPresent) { return 'SKIP: GUT not vendored' }
    $full = Join-Path $proj '.reports\summary.txt'
    $before = [System.IO.File]::ReadAllText($full)
    & (Join-Path $PSScriptRoot 'verify.ps1') -Game $gameName -Root $root -Tier 2 -Scenario move_right -Quiet
    $code = $LASTEXITCODE
    $sum = @(Get-Content (Join-Path $proj '.reports\summary-scoped.txt'))
    if ($code -ne 0) { throw ("scoped verify exit $code : " + ($sum -join ' | ')) }
    if ($sum[0] -notlike 'VERIFY-SCOPED *scenarios=move_right *') { throw "unexpected header: $($sum[0])" }
    $smoke = @($sum | Where-Object { $_ -like 'SMOKE *' })
    if ($smoke.Count -ne 1 -or $smoke[0] -notlike 'SMOKE move_right PASS *') { throw ('expected only SMOKE move_right: ' + ($smoke -join ' | ')) }
    if ([System.IO.File]::ReadAllText($full) -ne $before) { throw 'the scoped run changed summary.txt' }
    return ($sum[0] + '; summary.txt unchanged')
}

Invoke-Step 'stop-gate' {
    if (-not $gutPresent) { return 'SKIP: GUT not vendored' }
    # A developer branch with one commit and a full-run PASS of it: the gate must not run, and must not touch it.
    $null = git -C $proj checkout -q -b selftest-gate 2>$null
    $okTest = Join-Path $proj 'test\unit\test_zz_gate_ok.gd'
    [System.IO.File]::WriteAllText($okTest, "extends GutTest`n`n`nfunc test_gate_ok() -> void:`n`tassert_eq(1, 1)`n")
    $null = Save-SelftestCommit 'selftest: branch commit'
    & (Join-Path $PSScriptRoot 'verify.ps1') -Game $gameName -Root $root -Tier 1 -Quiet
    $full = Join-Path $proj '.reports\summary.txt'
    $gateSum = Join-Path $proj '.reports\summary-gate.txt'
    $before = [System.IO.File]::ReadAllText($full)
    if (Test-Path $gateSum) { Remove-Item $gateSum -Force }
    $gate = Join-Path $PSScriptRoot 'hooks\gate.ps1'
    $hookInput = (@{ cwd = $proj; stop_hook_active = $false } | ConvertTo-Json -Compress)
    $out1 = (@($hookInput | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $gate) -join ' ').Trim()
    if ($out1) { throw "the gate blocked although summary.txt is a fresh PASS: $out1" }
    if (Test-Path $gateSum) { throw 'the gate ran although summary.txt is a fresh PASS of HEAD' }
    # Now an uncommitted failing test: the gate runs, blocks with the failing line, and leaves summary.txt alone.
    $failTest = Join-Path $proj 'test\unit\test_zz_gate_fail.gd'
    [System.IO.File]::WriteAllText($failTest, "extends GutTest`n`n`nfunc test_gate_fail() -> void:`n`tassert_eq(1, 2, `"selftest: gate must block`")`n")
    try {
        $out2 = (@($hookInput | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $gate) -join ' ').Trim()
    } finally {
        foreach ($f in @($failTest, ($failTest + '.uid'))) { if (Test-Path $f) { Remove-Item $f -Force } }
    }
    if ($out2 -notlike '*"decision":"block"*' -or $out2 -notlike '*test_gate_fail*') { throw "expected a block naming the failing test, got: $out2" }
    if (-not (Test-Path $gateSum)) { throw 'the gate run wrote no summary-gate.txt' }
    if ([System.IO.File]::ReadAllText($full) -ne $before) { throw 'the gate run overwrote summary.txt' }
    return 'skipped on a fresh PASS of HEAD; with a failing test it blocked with the failing line (summary-gate.txt) and left summary.txt alone'
}

Invoke-Step 'cleanup' {
    if ($Keep) { return "kept games/$gameName (-Keep)" }
    Remove-Item $proj -Recurse -Force
    return "removed games/$gameName"
}

$total.Stop()
$fails = @($results | Where-Object { $_.Status -eq 'FAIL' })
$pass = @($results | Where-Object { $_.Status -eq 'PASS' }).Count
$info = @($results | Where-Object { $_.Status -eq 'INFO' }).Count
$skip = @($results | Where-Object { $_.Status -eq 'SKIP' }).Count
Write-Host ''
Write-Host ("selftest finished in {0}s: PASS={1} INFO={2} SKIP={3} FAIL={4}" -f [math]::Round($total.Elapsed.TotalSeconds, 1), $pass, $info, $skip, $fails.Count)
if ($fails.Count -gt 0) { exit 1 } else { exit 0 }
