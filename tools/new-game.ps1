# Scaffolds games/<Name> from templates/game-template. Name: lowercase letters, digits, hyphens.
param(
    [Parameter(Mandatory = $true)][string]$Name,
    [string]$Root = '',
    [switch]$Force
)
. "$PSScriptRoot/_lib.ps1"
if ($Name -notmatch '^[a-z][a-z0-9-]*$') { throw "Game name must be lowercase letters, digits and hyphens, starting with a letter: '$Name'" }
$root = Get-RepoRoot $Root
$src = Join-Path $root 'templates\game-template'
$dst = Join-Path $root (Join-Path 'games' $Name)
if (-not (Test-Path (Join-Path $src 'project.godot'))) { throw "template missing: $src" }
if ((Test-Path $dst) -and -not $Force) { throw "games/$Name already exists (use -Force to overwrite)" }
if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
$null = New-Item -ItemType Directory -Path $dst -Force
$null = & robocopy.exe $src $dst /E /XD .godot .reports /XF *.tmp /NFL /NDL /NJH /NJS /NC /NS /NP
if ($LASTEXITCODE -ge 8) { throw "robocopy failed with code $LASTEXITCODE" }

$pg = Join-Path $dst 'project.godot'
$text = [System.IO.File]::ReadAllText($pg)
$text = $text -replace 'config/name="[^"]*"', ('config/name="' + $Name + '"')
[System.IO.File]::WriteAllText($pg, $text)

foreach ($d in @('test\baselines', '.reports')) {
    $dir = Join-Path $dst $d
    if (-not (Test-Path $dir)) { $null = New-Item -ItemType Directory -Path $dir }
    $gi = Join-Path $dir '.gdignore'
    if (-not (Test-Path $gi)) { $null = New-Item -ItemType File -Path $gi }
}
foreach ($doc in @('design\gdd.md', 'design\plan.md')) {
    $p = Join-Path $dst $doc
    if (Test-Path $p) {
        $d = [System.IO.File]::ReadAllText($p)
        $d = $d.Replace('<Game name>', $Name)
        [System.IO.File]::WriteAllText($p, $d)
    }
}
if (-not (Test-Path (Join-Path $dst 'addons\gut\gut_cmdln.gd'))) {
    Write-Host "note: GUT is not vendored yet; unit tests will fail until ./tools/vendor-gut.ps1 has run."
}
Write-Host "created games/$Name from the template"
exit 0
