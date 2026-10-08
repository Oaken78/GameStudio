# PostToolUse hook (Edit|Write): formats .gd files with gdformat when it is installed. Always exits 0, prints nothing on success.
$ErrorActionPreference = 'Continue'
try {
    $raw = [Console]::In.ReadToEnd()
    if (-not $raw) { exit 0 }
    $j = $raw | ConvertFrom-Json
    $p = $null
    if ($j.tool_input) { $p = $j.tool_input.file_path }
    if (-not $p) { exit 0 }
    $n = ($p -replace '\\', '/')
    if ($n -notmatch '\.gd$' -or $n -match '/addons/') { exit 0 }
    if (-not (Test-Path $p)) { exit 0 }
    . (Join-Path (Split-Path $PSScriptRoot -Parent) '_lib.ps1')
    $cmd = Get-GdTool 'gdformat'
    if (-not $cmd) { exit 0 }
    $out = & $cmd $p 2>&1
    if ($LASTEXITCODE -ne 0) {
        $tail = @($out | Select-Object -Last 3) -join ' | '
        [Console]::Error.WriteLine("gdformat could not format $p : $tail")
    }
    exit 0
} catch {
    exit 0
}
