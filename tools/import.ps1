# Generates games/<g>/.godot (class cache, imported assets). Idempotent; -Force re-imports.
param(
    [Parameter(Mandatory = $true)][string]$Game,
    [switch]$Force,
    [string]$Root = ''
)
. "$PSScriptRoot/_lib.ps1"
$proj = Resolve-GamePath -Game $Game -Root $Root
$r = Invoke-Import -ProjectDir $proj -Force:$Force
if ($null -eq $r) {
    Write-Host "import: up to date ($proj\.godot)"
} else {
    Write-Host ("import: done in {0}s (exit {1})" -f $r.Seconds, $r.ExitCode)
}
exit 0
