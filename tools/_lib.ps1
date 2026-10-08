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

# Runs Godot with a hard timeout. Returns ExitCode (124 on timeout), Stdout, Stderr, Seconds, Command.
function Invoke-Godot {
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
    $outTask = $p.StandardOutput.ReadToEndAsync()
    $errTask = $p.StandardError.ReadToEndAsync()
    $timedOut = $false
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        $timedOut = $true
        $null = Start-Process -FilePath 'taskkill.exe' -ArgumentList "/PID $($p.Id) /T /F" -NoNewWindow -Wait -PassThru
        $p.WaitForExit()
    }
    $stdout = $outTask.Result
    $stderr = $errTask.Result
    $code = $p.ExitCode
    if ($timedOut) { $code = 124 }
    $sw.Stop()
    return [pscustomobject]@{
        ExitCode = $code
        TimedOut = $timedOut
        Stdout   = $stdout
        Stderr   = $stderr
        Seconds  = [math]::Round($sw.Elapsed.TotalSeconds, 1)
        Command  = ('"' + $bin + '" ' + $psi.Arguments)
    }
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

# Runs one scenario (test/scenarios/<name>.json) through the DevHarness autoload.
function Invoke-Scenario {
    param(
        [string]$ProjectDir, [string]$ScenarioName, [string]$OutDir,
        [switch]$Windowed, [switch]$Screens, [int]$Seed = 1234, [int]$TimeoutSec = 0
    )
    $outFwd = ConvertTo-ForwardSlash $OutDir
    $log = $outFwd + '/godot.log'
    $gargs = @('--path', $ProjectDir)
    if ($Windowed) { $gargs += @('--resolution', '1280x720', '--position', '100,100', '--disable-vsync') }
    else { $gargs += '--headless' }
    $gargs += @('--fixed-fps', '60', '--quit-after', '7200', '--log-file', $log, '--',
        "--scenario=res://test/scenarios/$ScenarioName.json", "--out=$outFwd", "--seed=$Seed")
    if ($Screens) { $gargs += '--screens=1' }
    $r = Invoke-Godot -GodotArgs $gargs -TimeoutSec $TimeoutSec -WorkDir $ProjectDir
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
    }
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
