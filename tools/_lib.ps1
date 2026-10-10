# Shared helpers for tools/*.ps1. Dot-source from a script:  . "$PSScriptRoot/_lib.ps1"
# PowerShell 5.1 compatible: no &&, no ternary, no ??. ASCII only.

$script:ToolsDir = $PSScriptRoot
$script:RepoRootDefault = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Get-RepoRoot {
    param([string]$Root = '')
    if ($Root) { return (Resolve-Path $Root).Path }
    return (Get-MainCheckout $script:RepoRootDefault)
}

# Games are separate git repos under games/ and exist only in the main checkout of the root repo.
# From a linked root worktree (.git is a file: "gitdir: <main>/.git/worktrees/<name>") return the main checkout.
function Get-MainCheckout {
    param([string]$Dir)
    $dotgit = Join-Path $Dir '.git'
    if (Test-Path $dotgit -PathType Leaf) {
        $line = (Get-Content $dotgit -TotalCount 1) -replace '^gitdir:\s*', ''
        $norm = ConvertTo-ForwardSlash $line.Trim()
        $i = $norm.ToLower().LastIndexOf('/.git/worktrees/')
        if ($i -gt 0) {
            $main = $norm.Substring(0, $i)
            if (Test-Path (Join-Path $main 'tools')) { return (Resolve-Path $main).Path }
        }
    }
    return $Dir
}

function ConvertTo-ForwardSlash {
    param([string]$Path)
    return ($Path -replace '\\', '/')
}

function Get-GodotBin {
    $candidates = @()
    if ($env:GODOT_BIN) { $candidates += $env:GODOT_BIN }
    $candidates += 'C:\Tools\Godot\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe'
    if (Test-Path 'C:\Tools\Godot') {
        $found = Get-ChildItem 'C:\Tools\Godot' -Recurse -Filter '*console.exe' -ErrorAction SilentlyContinue
        foreach ($f in $found) { $candidates += $f.FullName }
    }
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) { return (Resolve-Path $c).Path }
    }
    foreach ($name in @('godot_console', 'godot')) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    throw 'Godot binary not found. Set GODOT_BIN to the *_console.exe (env block of .claude/settings.json or .claude/settings.local.json).'
}

# Finds a gdtoolkit executable (gdformat, gdlint): PATH first, then $env:GDTOOLKIT_BIN, then pip --user script dirs.
function Get-GdTool {
    param([string]$Tool = 'gdformat')
    $cmd = Get-Command $Tool -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $dirs = @()
    if ($env:GDTOOLKIT_BIN) { $dirs += $env:GDTOOLKIT_BIN }
    if ($env:APPDATA) { $dirs += @(Get-ChildItem (Join-Path $env:APPDATA 'Python') -Directory -Filter 'Python3*' -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.FullName 'Scripts' }) }
    if ($env:LOCALAPPDATA) { $dirs += @(Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Programs\Python') -Directory -Filter 'Python3*' -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.FullName 'Scripts' }) }
    foreach ($d in $dirs) {
        $exe = Join-Path $d ($Tool + '.exe')
        if (Test-Path $exe) { return $exe }
    }
    return $null
}

function Format-GodotArg {
    param([string]$Value)
    if ($Value -eq '') { return '""' }
    if ($Value -match '[\s"]') { return '"' + ($Value -replace '"', '\"') + '"' }
    return $Value
}

# Starts Godot and returns at once; Complete-Godot waits for it. Takes no window lock, so call it directly only
# for headless runs (parallel smoke); everything else goes through Invoke-Godot.
function Start-Godot {
    param(
        [Parameter(Mandatory = $true)][string[]]$GodotArgs,
        [int]$TimeoutSec = 0,
        [string]$WorkDir = ''
    )
    if ($TimeoutSec -le 0) {
        $TimeoutSec = 180
        if ($env:GODOT_RUN_TIMEOUT_SEC) { $TimeoutSec = [int]$env:GODOT_RUN_TIMEOUT_SEC }
    }
    $bin = Get-GodotBin
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $bin
    $quoted = @()
    foreach ($a in $GodotArgs) { $quoted += (Format-GodotArg $a) }
    $psi.Arguments = ($quoted -join ' ')
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    if ($WorkDir) { $psi.WorkingDirectory = $WorkDir }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $p = [System.Diagnostics.Process]::Start($psi)
    return [pscustomobject]@{
        Process    = $p
        OutTask    = $p.StandardOutput.ReadToEndAsync()
        ErrTask    = $p.StandardError.ReadToEndAsync()
        Watch      = $sw
        TimeoutSec = $TimeoutSec
        Command    = ('"' + $bin + '" ' + $psi.Arguments)
    }
}

# True once a run from Start-Godot has exited or used up its time (Complete-Godot then stops it).
function Test-GodotDone {
    param($Run)
    if ($Run.Process.HasExited) { return $true }
    return ($Run.Watch.Elapsed.TotalSeconds -ge $Run.TimeoutSec)
}

# Waits for a run from Start-Godot, killing the process tree at its timeout.
# Returns ExitCode (124 on timeout), TimedOut, Stdout, Stderr, Seconds, Command, LockWaitedSec, LockFailed.
function Complete-Godot {
    param($Run)
    $p = $Run.Process
    $leftMs = [int][math]::Max(0, [math]::Ceiling(($Run.TimeoutSec - $Run.Watch.Elapsed.TotalSeconds) * 1000))
    $timedOut = $false
    if (-not $p.WaitForExit($leftMs)) {
        $timedOut = $true
        $null = Start-Process -FilePath 'taskkill.exe' -ArgumentList "/PID $($p.Id) /T /F" -NoNewWindow -Wait -PassThru
        $p.WaitForExit()
    }
    $stdout = $Run.OutTask.Result
    $stderr = $Run.ErrTask.Result
    $code = $p.ExitCode
    if ($timedOut) { $code = 124 }
    $Run.Watch.Stop()
    return [pscustomobject]@{
        ExitCode      = $code
        TimedOut      = $timedOut
        Stdout        = $stdout
        Stderr        = $stderr
        Seconds       = [math]::Round($Run.Watch.Elapsed.TotalSeconds, 1)
        Command       = $Run.Command
        LockWaitedSec = 0
        LockFailed    = $false
    }
}

# Does this Godot command open a window? Everything does except --headless (or the headless display driver)
# and the quick info flags.
function Test-WindowedArgs {
    param([string[]]$GodotArgs = @())
    foreach ($a in $GodotArgs) {
        if (@('--headless', '--version', '--help', '-h') -contains $a) { return $false }
    }
    $joined = ' ' + ($GodotArgs -join ' ') + ' '
    if ($joined -match '\s--display-driver[\s=]+headless\s') { return $false }
    return $true
}

# One windowed Godot at a time on this machine: windowed runs share the real mouse, keyboard focus and screen, and
# break each other otherwise (a click lands in the wrong window). The lock is a named mutex, machine-wide, and
# Windows releases it when the holding process dies. GAMESTUDIO_WINDOW_LOCK renames it (tools/selftest.ps1 only).
function Get-WindowLockName {
    if ($env:GAMESTUDIO_WINDOW_LOCK) { return $env:GAMESTUDIO_WINDOW_LOCK }
    return 'Global\GameStudio-GodotWindow'
}

# Text file in %TEMP% that names the lock's current holder, so a waiting run can say whom it waits for.
function Get-WindowLockNote {
    param([string]$Name)
    $safe = ($Name -replace '[^A-Za-z0-9_-]', '_')
    return (Join-Path ([System.IO.Path]::GetTempPath()) ($safe + '.txt'))
}

# Waits up to TimeoutSec for the window lock. Returns Mutex (null when not acquired), Acquired, WaitedSec, Holder
# (who held it when the wait began), Abandoned (the previous holder died holding it). Release with Exit-WindowLock.
function Enter-WindowLock {
    param([string]$Label = '', [int]$TimeoutSec = 1800, [string]$Name = '')
    if (-not $Name) { $Name = Get-WindowLockName }
    $note = Get-WindowLockNote $Name
    $mutex = New-Object System.Threading.Mutex($false, $Name)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $got = $false
    $abandoned = $false
    $holder = ''
    try { $got = $mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $got = $true; $abandoned = $true }
    if (-not $got) {
        if (Test-Path $note) { $holder = ([string](Get-Content $note -Raw -ErrorAction SilentlyContinue)).Trim() }
        if (-not $holder) { $holder = 'another windowed Godot run' }
        Write-Host "window lock: held by $holder; waiting up to $TimeoutSec s"
        try { $got = $mutex.WaitOne($TimeoutSec * 1000) } catch [System.Threading.AbandonedMutexException] { $got = $true; $abandoned = $true }
    }
    $sw.Stop()
    $waited = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    if ($got) {
        try { [System.IO.File]::WriteAllText($note, "$Label (pid $PID, since $(Get-Date -Format 'HH:mm:ss'))") } catch { }
        if ($waited -ge 1) { Write-Host "waited $waited s for the window lock" }
    } else {
        $mutex.Dispose()
        $mutex = $null
    }
    return [pscustomobject]@{ Mutex = $mutex; Acquired = $got; WaitedSec = $waited; Holder = $holder; Abandoned = $abandoned }
}

function Exit-WindowLock {
    param($Lock)
    if ($null -eq $Lock -or $null -eq $Lock.Mutex) { return }
    try { $Lock.Mutex.ReleaseMutex() } catch { }
    $Lock.Mutex.Dispose()
}

# Runs Godot with a hard timeout and waits for it. A windowed run first takes the window lock and gives up after
# LockTimeoutSec (exit 125, LockFailed). Returns ExitCode (124 on timeout), TimedOut, Stdout, Stderr, Seconds,
# Command, LockWaitedSec, LockFailed.
function Invoke-Godot {
    param(
        [Parameter(Mandatory = $true)][string[]]$GodotArgs,
        [int]$TimeoutSec = 0,
        [string]$WorkDir = '',
        [int]$LockTimeoutSec = 1800,
        [string]$LockLabel = ''
    )
    $lock = $null
    if (Test-WindowedArgs $GodotArgs) {
        if (-not $LockLabel) { $LockLabel = 'godot ' + (@($GodotArgs | Select-Object -First 3) -join ' ') }
        $lock = Enter-WindowLock -Label $LockLabel -TimeoutSec $LockTimeoutSec
        if (-not $lock.Acquired) {
            return [pscustomobject]@{
                ExitCode = 125; TimedOut = $false; Stdout = ''; Seconds = 0; Command = ''
                Stderr = "window lock: gave up after $LockTimeoutSec s; $($lock.Holder) still holds it"
                LockWaitedSec = $lock.WaitedSec; LockFailed = $true
            }
        }
    }
    try {
        $run = Start-Godot -GodotArgs $GodotArgs -TimeoutSec $TimeoutSec -WorkDir $WorkDir
        $r = Complete-Godot $run
    } finally {
        Exit-WindowLock $lock
    }
    if ($lock) { $r.LockWaitedSec = $lock.WaitedSec }
    return $r
}

function Resolve-GamePath {
    param([Parameter(Mandatory = $true)][string]$Game, [string]$Root = '')
    $r = Get-RepoRoot $Root
    $tries = @((Join-Path $r (Join-Path 'games' $Game)), (Join-Path $r $Game), $Game)
    foreach ($t in $tries) {
        if (Test-Path (Join-Path $t 'project.godot')) { return (Resolve-Path $t).Path }
    }
    throw "No Godot project found for '$Game' (looked for games/$Game/project.godot under $r)."
}

function Get-GameRel {
    param([string]$Root, [string]$ProjectDir)
    $rel = $ProjectDir.Substring($Root.Length).TrimStart('\', '/')
    return (ConvertTo-ForwardSlash $rel)
}

function Test-Imported {
    param([string]$ProjectDir)
    $a = Join-Path $ProjectDir '.godot\global_script_class_cache.cfg'
    $b = Join-Path $ProjectDir '.godot\uid_cache.bin'
    return ((Test-Path $a) -or (Test-Path $b))
}

# Generates .godot/ (class cache, imported assets). Needed once per fresh clone or worktree.
function Invoke-Import {
    param([string]$ProjectDir, [switch]$Force)
    if (-not $Force -and (Test-Imported $ProjectDir)) { return $null }
    $r = Invoke-Godot -GodotArgs @('--headless', '--path', $ProjectDir, '--import') -TimeoutSec 600
    if (-not (Test-Imported $ProjectDir)) {
        throw ("import failed for $ProjectDir (exit $($r.ExitCode)). Output:`n" + $r.Stdout + "`n" + $r.Stderr)
    }
    return $r
}

# .reports/ is gitignored scratch output. The .gdignore keeps Godot from importing PNGs written there.
function New-ReportsDir {
    param([string]$ProjectDir, [string]$Sub = '')
    $r = Join-Path $ProjectDir '.reports'
    if (-not (Test-Path $r)) { $null = New-Item -ItemType Directory -Path $r }
    $gi = Join-Path $r '.gdignore'
    if (-not (Test-Path $gi)) { $null = New-Item -ItemType File -Path $gi }
    if ($Sub) {
        $d = Join-Path $r $Sub
        if (-not (Test-Path $d)) { $null = New-Item -ItemType Directory -Path $d }
        return (Resolve-Path $d).Path
    }
    return (Resolve-Path $r).Path
}

function Get-LogAllowlist {
    param([string]$ProjectDir)
    $f = Join-Path $ProjectDir 'test\log_allowlist.txt'
    $list = @()
    if (Test-Path $f) {
        foreach ($line in Get-Content $f) {
            $t = $line.Trim()
            if ($t -ne '' -and -not $t.StartsWith('#')) { $list += $t }
        }
    }
    return $list
}

function Get-ErrorLines {
    param([string[]]$Lines = @(), [string[]]$Allow = @())
    $hits = @()
    foreach ($l in $Lines) {
        if ($null -eq $l) { continue }
        if ($l -match '^(ERROR|SCRIPT ERROR|SHADER ERROR):') {
            $skip = $false
            foreach ($a in $Allow) { if ($a -and $l.Contains($a)) { $skip = $true; break } }
            if (-not $skip) { $hits += $l }
        }
    }
    return $hits
}

# Godot arguments for one scenario run through the DevHarness autoload; the log goes into the run's own folder.
function Get-ScenarioArgs {
    param([string]$ProjectDir, [string]$ScenarioName, [string]$OutDir, [switch]$Windowed, [switch]$Screens, [int]$Seed = 1234)
    $outFwd = ConvertTo-ForwardSlash $OutDir
    $log = $outFwd + '/godot.log'
    $gargs = @('--path', $ProjectDir)
    if ($Windowed) { $gargs += @('--resolution', '1280x720', '--position', '100,100', '--disable-vsync') }
    else { $gargs += '--headless' }
    $gargs += @('--fixed-fps', '60', '--quit-after', '7200', '--log-file', $log, '--',
        "--scenario=res://test/scenarios/$ScenarioName.json", "--out=$outFwd", "--seed=$Seed")
    if ($Screens) { $gargs += '--screens=1' }
    return $gargs
}

# Runs one scenario (test/scenarios/<name>.json) and waits for it. A windowed run takes the window lock first.
function Invoke-Scenario {
    param(
        [string]$ProjectDir, [string]$ScenarioName, [string]$OutDir,
        [switch]$Windowed, [switch]$Screens, [int]$Seed = 1234, [int]$TimeoutSec = 0, [int]$LockTimeoutSec = 1800
    )
    $gargs = @(Get-ScenarioArgs -ProjectDir $ProjectDir -ScenarioName $ScenarioName -OutDir $OutDir -Windowed:$Windowed -Screens:$Screens -Seed $Seed)
    $label = (Split-Path $ProjectDir -Leaf) + ' ' + $ScenarioName
    $r = Invoke-Godot -GodotArgs $gargs -TimeoutSec $TimeoutSec -WorkDir $ProjectDir -LockTimeoutSec $LockTimeoutSec -LockLabel $label
    return (Read-ScenarioResult -ProjectDir $ProjectDir -ScenarioName $ScenarioName -OutDir $OutDir -GodotResult $r)
}

# Starts one headless scenario without waiting (parallel smoke). Each run has its own folder and log, and the
# harness writes only there. Finish it with Complete-Scenario once Test-GodotDone says so.
function Start-Scenario {
    param([string]$ProjectDir, [string]$ScenarioName, [string]$OutDir, [int]$Seed = 1234, [int]$TimeoutSec = 0)
    $gargs = @(Get-ScenarioArgs -ProjectDir $ProjectDir -ScenarioName $ScenarioName -OutDir $OutDir -Seed $Seed)
    $run = Start-Godot -GodotArgs $gargs -TimeoutSec $TimeoutSec -WorkDir $ProjectDir
    return [pscustomobject]@{ Run = $run; ProjectDir = $ProjectDir; ScenarioName = $ScenarioName; OutDir = $OutDir }
}

function Complete-Scenario {
    param($Job)
    $r = Complete-Godot $Job.Run
    return (Read-ScenarioResult -ProjectDir $Job.ProjectDir -ScenarioName $Job.ScenarioName -OutDir $Job.OutDir -GodotResult $r)
}

# Reads what a finished scenario run left in its folder (result.json, godot.log) plus its console output.
# Ok = exit 0 AND result.json ok AND zero error lines.
function Read-ScenarioResult {
    param([string]$ProjectDir, [string]$ScenarioName, [string]$OutDir, $GodotResult)
    $r = $GodotResult
    $result = $null
    $rf = Join-Path $OutDir 'result.json'
    if (Test-Path $rf) {
        try { $result = Get-Content $rf -Raw | ConvertFrom-Json } catch { $result = $null }
    }
    $lines = @()
    $logPath = Join-Path $OutDir 'godot.log'
    if (Test-Path $logPath) { $lines += @(Get-Content $logPath) }
    if ($r.Stderr) { $lines += @($r.Stderr -split "`r?`n") }
    if ($r.Stdout) { $lines += @($r.Stdout -split "`r?`n") }
    $errs = @(Get-ErrorLines -Lines $lines -Allow (Get-LogAllowlist $ProjectDir) | Select-Object -Unique)
    $ok = ($r.ExitCode -eq 0) -and ($null -ne $result) -and ($result.ok -eq $true) -and ($errs.Count -eq 0)
    return [pscustomobject]@{
        Scenario = $ScenarioName; Ok = $ok; ExitCode = $r.ExitCode; TimedOut = $r.TimedOut; Seconds = $r.Seconds
        Result = $result; ErrorLines = $errs; OutDir = $OutDir; Stdout = $r.Stdout; Stderr = $r.Stderr; Command = $r.Command
        LockWaitedSec = $r.LockWaitedSec; LockFailed = $r.LockFailed
    }
}

# Scenario names for a -Scenario value: 'all' (every test/scenarios/*.json, in folder order as before) or the given
# names, which may also come as one comma-separated string ("a,b"). Duplicates are dropped.
function Get-ScenarioNames {
    param([string]$ProjectDir, [string[]]$Scenario = @('all'))
    $list = @()
    foreach ($s in $Scenario) {
        foreach ($part in ([string]$s -split ',')) {
            $t = $part.Trim()
            if ($t -and -not ($list -contains $t)) { $list += $t }
        }
    }
    if ($list.Count -eq 0 -or ($list.Count -eq 1 -and $list[0] -eq 'all')) {
        $sdir = Join-Path $ProjectDir 'test\scenarios'
        if (-not (Test-Path $sdir)) { return @() }
        return @(Get-ChildItem $sdir -Filter '*.json' | Select-Object -ExpandProperty BaseName)
    }
    return $list
}

# What a scenario needs from the runners, read from its JSON:
#   Windowed: it has a "screenshot" or "metrics" step, so a windowed run adds something. shots.ps1 without
#     -Scenario (a full tier 3 run) runs only these; every scenario still runs headless in smoke.
#   Serial: its numbers depend on wall-clock speed, so smoke runs it alone after the parallel batch. Rule:
#     a "metrics" step; an assert_prop on a property named *_ms, *_usec or *_frames, or containing fps or
#     per_frame; a name perf_*, world_stream* or frame_cold; or "serial": true at the top of the JSON.
#     (*_s values and tick counts are game time under --fixed-fps 60, so CPU load does not move them.)
#   SerialWhy names the rule that matched. An unreadable JSON counts as both; the harness then reports the error.
function Get-ScenarioInfo {
    param([string]$ProjectDir, [string]$Name)
    $windowed = $false
    $why = ''
    if ($Name -like 'perf_*' -or $Name -like 'world_stream*' -or $Name -eq 'frame_cold') { $why = 'name' }
    $json = $null
    $f = Join-Path $ProjectDir ('test\scenarios\' + $Name + '.json')
    try { $json = Get-Content $f -Raw -ErrorAction Stop | ConvertFrom-Json } catch { $json = $null }
    if ($null -eq $json) {
        return [pscustomobject]@{ Name = $Name; Windowed = $true; Serial = $true; SerialWhy = 'unreadable JSON' }
    }
    if (-not $why -and $json.serial -eq $true) { $why = '"serial": true' }
    foreach ($step in @($json.steps)) {
        if ($null -eq $step) { continue }
        $keys = @($step.PSObject.Properties.Name)
        if ($keys -contains 'screenshot') { $windowed = $true }
        if ($keys -contains 'metrics') {
            $windowed = $true
            if (-not $why) { $why = 'metrics step' }
        }
        if (-not $why -and ($keys -contains 'assert_prop')) {
            $prop = [string]$step.assert_prop.prop
            if ($prop -match '(_ms|_usec|_frames)$' -or $prop -match 'fps|per_frame') { $why = "asserts $prop" }
        }
    }
    return [pscustomobject]@{ Name = $Name; Windowed = $windowed; Serial = ($why -ne ''); SerialWhy = $why }
}

# Compares metrics__*.json in a run folder against design/budgets.json. Returns BUDGET FAIL lines.
function Test-Budgets {
    param([string]$ProjectDir, [string]$OutDir)
    $fails = @()
    $bf = Join-Path $ProjectDir 'design\budgets.json'
    if (-not (Test-Path $bf)) { return $fails }
    $b = Get-Content $bf -Raw | ConvertFrom-Json
    foreach ($mf in Get-ChildItem $OutDir -Filter 'metrics__*.json' -ErrorAction SilentlyContinue) {
        $m = Get-Content $mf.FullName -Raw | ConvertFrom-Json
        $n = $m.name
        if ($m.headless -ne $true) {
            if ($b.frame_ms_p95 -and $m.frame_ms.p95 -gt $b.frame_ms_p95) { $fails += "BUDGET FAIL $n frame_ms p95 $($m.frame_ms.p95) > $($b.frame_ms_p95)" }
            if ($b.frame_ms_max -and $m.frame_ms.max -gt $b.frame_ms_max) { $fails += "BUDGET FAIL $n frame_ms max $($m.frame_ms.max) > $($b.frame_ms_max)" }
            if ($b.draw_calls_max -and $m.draw_calls.max -gt $b.draw_calls_max) { $fails += "BUDGET FAIL $n draw_calls max $($m.draw_calls.max) > $($b.draw_calls_max)" }
        }
        if ($null -ne $b.orphan_nodes_max -and $m.orphan_nodes.max -gt $b.orphan_nodes_max) { $fails += "BUDGET FAIL $n orphan_nodes max $($m.orphan_nodes.max) > $($b.orphan_nodes_max)" }
        if ($b.static_mem_mb_max -and $m.static_mem_mb.max -gt $b.static_mem_mb_max) { $fails += "BUDGET FAIL $n static_mem_mb max $($m.static_mem_mb.max) > $($b.static_mem_mb_max)" }
    }
    return $fails
}

# Root-relative (forward slash) files under games/<g> that are uncommitted, untracked, or committed on this branch
# but not on main. Each game is its own git repo (or a worktree of one); falls back to the root repo otherwise.
function Get-ChangedFiles {
    param([string]$Root, [string]$GameRel)
    $set = New-Object 'System.Collections.Generic.HashSet[string]'
    $dir = Join-Path $Root $GameRel
    $own = Test-Path (Join-Path $dir '.git')
    $prefix = ''
    $spec = $GameRel
    $gitDir = $Root
    if ($own) { $prefix = $GameRel + '/'; $spec = '.'; $gitDir = $dir }
    Push-Location $gitDir
    try {
        $st = @(git status --porcelain --untracked-files=all -- $spec)
        foreach ($line in $st) {
            if ($null -eq $line -or $line.Length -le 3) { continue }
            $p = $line.Substring(3).Trim()
            if ($p.Contains(' -> ')) { $p = ($p -split ' -> ')[-1] }
            $p = $p.Trim('"')
            $null = $set.Add($prefix + (ConvertTo-ForwardSlash $p))
        }
        $head = git rev-parse --verify -q HEAD
        $main = git rev-parse --verify -q main
        if ($head -and $main -and ($head -ne $main)) {
            $base = git merge-base main HEAD
            if ($base) {
                foreach ($f in @(git diff --name-only $base HEAD -- $spec)) { if ($f) { $null = $set.Add($prefix + $f) } }
            }
        }
    } finally { Pop-Location }
    $arr = @($set)
    return $arr
}

# Tier 0 docs only; 1 one script; 2 several scripts, scenes, project.godot, autoloads, scenarios; 3 anything visual.
function Get-AutoTier {
    param([string[]]$Files = @(), [string]$GameRel)
    $tier = 0
    $scripts = @()
    foreach ($f in $Files) {
        $rel = $f
        if ($rel.StartsWith($GameRel)) { $rel = $rel.Substring($GameRel.Length).TrimStart('/') }
        if ($rel -match '\.(md|txt)$' -or $rel.StartsWith('design/')) { continue }
        if ($rel -match '\.(import|uid)$' -or $rel -eq '.gitignore' -or $rel -eq '.gdignore') { continue }
        if ($rel -match '\.(gdshader|gdshaderinc|png|jpg|jpeg|svg|webp|ogg|wav|mp3|ttf|otf)$' -or $rel -match '^(ui|shaders|assets|art|audio|vfx)/' -or $rel -match 'theme') {
            $tier = [math]::Max($tier, 3); continue
        }
        if ($rel -match '\.(tscn|tres)$' -or $rel -eq 'project.godot' -or $rel.StartsWith('autoload/') -or $rel.StartsWith('test/scenarios/')) {
            $tier = [math]::Max($tier, 2); continue
        }
        if ($rel -match '\.gd$') {
            if (-not $rel.StartsWith('test/')) { $scripts += $rel }
            $tier = [math]::Max($tier, 1); continue
        }
        $tier = [math]::Max($tier, 1)
    }
    if ($scripts.Count -gt 1) { $tier = [math]::Max($tier, 2) }
    return $tier
}

function Get-ChangedScripts {
    param([string[]]$Files = @(), [string]$GameRel)
    $out = @()
    foreach ($f in $Files) {
        $rel = $f
        if ($rel.StartsWith($GameRel)) { $rel = $rel.Substring($GameRel.Length).TrimStart('/') }
        if ($rel -match '\.gd$' -and -not $rel.StartsWith('addons/')) { $out += $rel }
    }
    return $out
}

# Writes lines as UTF-8 without BOM and echoes them unless -Quiet.
function Write-Lines {
    param([string[]]$Lines = @(), [string]$Path, [switch]$Quiet)
    $clean = @()
    foreach ($l in $Lines) { if ($null -ne $l) { $clean += [string]$l } }
    [System.IO.File]::WriteAllLines($Path, [string[]]$clean)
    if (-not $Quiet) { foreach ($l in $clean) { Write-Host $l } }
}

function Format-Invariant {
    param([double]$Value, [int]$Digits = 4)
    return [math]::Round($Value, $Digits).ToString([System.Globalization.CultureInfo]::InvariantCulture)
}

# The game checkout's state: Commit (short hash), Content (short hash of HEAD's tree, unchanged by a message-only
# amend), Tree = clean | dirty (git status --porcelain with untracked files, .reports/ ignored) | unknown (the
# folder is not its own git repo or checkout). Text = "commit=<c> content=<t> tree=<state>".
function Get-CheckoutState {
    param([string]$ProjectDir)
    $commit = 'none'
    $content = 'none'
    $tree = 'unknown'
    $top = @(git -C $ProjectDir rev-parse --show-toplevel 2>$null)
    $isRepo = $false
    if ($LASTEXITCODE -eq 0 -and $top.Count -gt 0) {
        $a = (ConvertTo-ForwardSlash ([string]$top[0])).TrimEnd('/').ToLower()
        $b = (ConvertTo-ForwardSlash $ProjectDir).TrimEnd('/').ToLower()
        $isRepo = ($a -eq $b)
    }
    if ($isRepo) {
        $c = @(git -C $ProjectDir rev-parse --short HEAD 2>$null)
        if ($LASTEXITCODE -eq 0 -and $c.Count -gt 0) { $commit = ([string]$c[0]).Trim() }
        $t = @(git -C $ProjectDir rev-parse --short 'HEAD^{tree}' 2>$null)
        if ($LASTEXITCODE -eq 0 -and $t.Count -gt 0) { $content = ([string]$t[0]).Trim() }
        $st = @(git -C $ProjectDir status --porcelain --untracked-files=all 2>$null)
        if ($LASTEXITCODE -eq 0) {
            $dirty = @($st | Where-Object { $_ -and $_.Length -gt 3 -and -not $_.Substring(3).Trim('"').StartsWith('.reports/') })
            if ($dirty.Count -eq 0) { $tree = 'clean' } else { $tree = 'dirty' }
        }
    }
    return [pscustomobject]@{ Commit = $commit; Content = $content; Tree = $tree; Text = "commit=$commit content=$content tree=$tree" }
}

# Fields of a verify summary's first line: Kind (VERIFY or VERIFY-SCOPED), tier, result, commit, content, tree.
# $null when the file is missing or is not a verify summary.
function Read-VerifyHeader {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    $first = @(Get-Content $Path -TotalCount 1)
    if ($first.Count -eq 0 -or $first[0] -notmatch '^(VERIFY|VERIFY-SCOPED) ') { return $null }
    $h = [string]$first[0]
    $f = @{ Line = $h; Kind = $Matches[1] }
    foreach ($key in @('tier', 'result', 'commit', 'content', 'tree')) {
        $f[$key] = ''
        if ($h -match (' ' + $key + '=(\S+)')) { $f[$key] = $Matches[1] }
    }
    return [pscustomobject]$f
}

# Can .reports/summary.txt stand in for a new full run at tier MinTier? Yes when it is a full-run PASS at that tier
# or higher, of the content HEAD has now (the same commit, or a message-only amend of it), on a tree that was clean
# during the run and is clean now. Returns Fresh and Reason (one line).
function Test-SummaryFresh {
    param([string]$ProjectDir, [int]$MinTier = 1)
    $h = Read-VerifyHeader (Join-Path $ProjectDir '.reports\summary.txt')
    $why = ''
    if ($null -eq $h -or $h.Kind -ne 'VERIFY') { $why = 'no full-run summary.txt' }
    elseif (-not $h.commit) { $why = 'summary.txt records no commit (written before verify.ps1 recorded one)' }
    elseif ($h.result -ne 'PASS') { $why = "summary.txt is a tier $($h.tier) FAIL (commit $($h.commit))" }
    elseif ([int]$h.tier -lt $MinTier) { $why = "summary.txt is tier $($h.tier), below tier $MinTier" }
    elseif ($h.tree -ne 'clean') { $why = "summary.txt ran on a $($h.tree) tree (commit $($h.commit))" }
    if ($why) { return [pscustomobject]@{ Fresh = $false; Reason = $why } }
    $now = Get-CheckoutState $ProjectDir
    if ($now.Content -ne $h.content) { $why = "summary.txt is for commit $($h.commit); HEAD $($now.Commit) has other content" }
    elseif ($now.Tree -ne 'clean') { $why = "the checkout has uncommitted changes now (summary.txt is for commit $($h.commit))" }
    if ($why) { return [pscustomobject]@{ Fresh = $false; Reason = $why } }
    return [pscustomobject]@{ Fresh = $true; Reason = "summary.txt is a tier $($h.tier) PASS of commit $($h.commit) (HEAD $($now.Commit), same content) on a clean tree" }
}
