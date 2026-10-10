# Ad-hoc Godot runner with the repo's timeout and binary resolution.
#   ./tools/godot.ps1 -Check                      prints the resolved binary and version
#   ./tools/godot.ps1 -- --path games/foo --headless --quit-after 10
# The first "--" is eaten by PowerShell; everything after it is passed to Godot unchanged.
# A command without --headless opens a window, so it first waits for the machine-wide window lock (Invoke-Godot).
param(
    [switch]$Check,
    [int]$TimeoutSec = 0,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest = @()
)
. "$PSScriptRoot/_lib.ps1"

if ($Check) {
    $bin = Get-GodotBin
    $r = Invoke-Godot -GodotArgs @('--version') -TimeoutSec 60
    Write-Host ("{0} => {1}" -f $bin, $r.Stdout.Trim())
    exit $r.ExitCode
}
if ($Rest.Count -eq 0) {
    Write-Host 'usage: ./tools/godot.ps1 -Check | ./tools/godot.ps1 -- <godot args>'
    exit 2
}
$r = Invoke-Godot -GodotArgs $Rest -TimeoutSec $TimeoutSec
if ($r.Stdout) { Write-Host $r.Stdout }
if ($r.Stderr) { Write-Host $r.Stderr }
if ($r.TimedOut) { Write-Host "godot: timed out after the configured limit (exit 124)" }
if ($r.LockFailed) { Write-Host "godot: not started, the window lock timed out (exit 125)" }
exit $r.ExitCode
