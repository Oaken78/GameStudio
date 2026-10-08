# Scaffolds games/<Name> from templates/game-template as its own git repo (branch main, nothing committed yet).
# Name: lowercase letters, digits, hyphens; '--' is reserved for branch checkouts (tools/game-worktree.ps1).
param(
    [Parameter(Mandatory = $true)][string]$Name,
    [string]$Root = '',
    [switch]$Force
)
. "$PSScriptRoot/_lib.ps1"
if ($Name -notmatch '^[a-z][a-z0-9-]*$' -or $Name.Contains('--')) { throw "Game name must be lowercase letters, digits and single hyphens, starting with a letter: '$Name'" }
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
if (-not (Test-Path (Join-Path $dst '.git'))) {
    Push-Location $dst
    try { $null = git init -q -b main } finally { Pop-Location }
    if ($LASTEXITCODE -ne 0) { throw "git init failed in games/$Name" }
}
Write-Host "created games/$Name from the template (own git repo, branch main, nothing committed yet)"
exit 0
