# End-to-end proof that the environment works, on a throwaway game (games/selftest-tmp).
# Run after changing tools/ or templates/. Prints a table and timings. Exit 0 when no step FAILed.
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
