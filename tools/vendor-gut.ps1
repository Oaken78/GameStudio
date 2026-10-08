# Downloads GUT (bitwes/Gut) at an exact tag and vendors addons/gut into the game template and into games that lack it.
# GUT 9.7.x is the line for Godot 4.7.x (branch godot_4_7). Never vendor from GUT's main branch (it targets 4.6).
# Network access: downloads https://github.com/bitwes/Gut/archive/refs/tags/v<Version>.zip (a few MB).
param(
    [string]$Version = '9.7.1',
    [string]$Root = ''
)
. "$PSScriptRoot/_lib.ps1"
$root = Get-RepoRoot $Root
$url = "https://github.com/bitwes/Gut/archive/refs/tags/v$Version.zip"
$work = Join-Path $env:TEMP ('gut-vendor-' + $Version)
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
$null = New-Item -ItemType Directory -Path $work
$zip = Join-Path $work 'gut.zip'
Write-Host "downloading $url"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
Write-Host ("downloaded {0:N1} MB" -f ((Get-Item $zip).Length / 1MB))
Expand-Archive -Path $zip -DestinationPath (Join-Path $work 'x') -Force
$src = Get-ChildItem (Join-Path $work 'x') -Recurse -Directory -Filter 'gut' | Where-Object { Test-Path (Join-Path $_.FullName 'gut_cmdln.gd') } | Select-Object -First 1
if (-not $src) { throw 'addons/gut (with gut_cmdln.gd) not found in the archive' }

$dest = Join-Path $root 'templates\game-template\addons\gut'
if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
$null = New-Item -ItemType Directory -Path (Split-Path $dest) -Force
Copy-Item $src.FullName $dest -Recurse
$note = @(
    '# Vendored add-ons',
    '',
    "- GUT $Version from $url (GUT's godot_4_7 line, for Godot 4.7.x).",
    '- Re-vendor with: ./tools/vendor-gut.ps1 -Version <x.y.z>. Never copy GUT from its main branch (targets Godot 4.6).',
    '- Do not edit files under addons/ by hand; the protect hook blocks it.'
)
[System.IO.File]::WriteAllLines((Join-Path $root 'templates\game-template\addons\VENDORED.md'), [string[]]$note)
Remove-Item $work -Recurse -Force
Write-Host "vendored GUT $Version into $dest"

$gamesDir = Join-Path $root 'games'
if (Test-Path $gamesDir) {
    foreach ($g in Get-ChildItem $gamesDir -Directory) {
        $gd = Join-Path $g.FullName 'addons\gut'
        if (-not (Test-Path (Join-Path $g.FullName 'project.godot'))) { continue }
        if (-not (Test-Path $gd)) {
            $null = New-Item -ItemType Directory -Path (Split-Path $gd) -Force
            Copy-Item $dest $gd -Recurse
            Copy-Item (Join-Path $root 'templates\game-template\addons\VENDORED.md') (Join-Path $g.FullName 'addons\VENDORED.md') -Force
            Write-Host "copied GUT into games/$($g.Name)"
        }
    }
}
exit 0
