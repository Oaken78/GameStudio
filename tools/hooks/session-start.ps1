# SessionStart hook: prints one line per environment problem and nothing when all is well (stdout enters the session).
$ErrorActionPreference = 'Continue'
try {
    $null = [Console]::In.ReadToEnd()
    $warn = @()
    $root = $env:CLAUDE_PROJECT_DIR
    if (-not $root) { $root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }
    $bin = $env:GODOT_BIN
    if (-not $bin -or -not (Test-Path $bin)) {
        $warn += "WARN: GODOT_BIN not found ($bin). Set env.GODOT_BIN in .claude/settings.local.json to the Godot *_console.exe."
    }
    if (-not (Get-Command gdformat -ErrorAction SilentlyContinue)) {
        $warn += 'WARN: gdformat not on PATH, so the format hook is a no-op (pip install "gdtoolkit==4.*").'
    }
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        $warn += 'WARN: gh not installed, so /merge-branch falls back to local merges (winget install GitHub.cli).'
    }
    if (-not (Test-Path (Join-Path $root 'templates\game-template\addons\gut\gut_cmdln.gd'))) {
        $warn += 'WARN: GUT not vendored, so unit tests cannot run until ./tools/vendor-gut.ps1 has been run.'
    }
    foreach ($w in $warn) { [Console]::Out.WriteLine($w) }
    exit 0
} catch {
    exit 0
}
