# Runs GUT tests headless. Exit 0 pass, 1 fail, 2 GUT missing.
#   ./tools/test.ps1 -Game foo                               all tests (dirs from .gutconfig.json)
#   ./tools/test.ps1 -Game foo -File test/unit/test_x.gd     one file
#   ./tools/test.ps1 -Game foo -File ... -Test test_name      one test (substring match)
#   ./tools/test.ps1 -Game foo -Dirs res://test/unit          unit tests only
# Writes .reports/test-summary.txt, .reports/test-output.txt and .reports/junit.xml.
param(
    [Parameter(Mandatory = $true)][string]$Game,
    [string]$File = '',
    [string]$Test = '',
    [string[]]$Dirs = @(),
    [int]$TimeoutSec = 300,
    [string]$Root = '',
    [switch]$Quiet
)
. "$PSScriptRoot/_lib.ps1"
$proj = Resolve-GamePath -Game $Game -Root $Root
$reports = New-ReportsDir $proj
$summaryPath = Join-Path $reports 'test-summary.txt'
$lines = @()

if (-not (Test-Path (Join-Path $proj 'addons\gut\gut_cmdln.gd'))) {
    $lines += "TEST $Game result=FAIL reason=addons/gut missing. Run ./tools/vendor-gut.ps1 (downloads GUT 9.7.1 into the template and into games that lack it)."
    Write-Lines -Lines $lines -Path $summaryPath -Quiet:$Quiet
    exit 2
}

$null = Invoke-Import -ProjectDir $proj
$junit = Join-Path $reports 'junit.xml'
if (Test-Path $junit) { Remove-Item $junit -Force }

$gargs = @('--headless', '--path', $proj, '-s', 'res://addons/gut/gut_cmdln.gd', '-gexit', '-glog=1', '-gjunit_xml_file=res://.reports/junit.xml')
if ($File) {
    $f = ConvertTo-ForwardSlash $File
    if (-not $f.StartsWith('res://')) {
        $idx = $f.IndexOf('test/')
        if ($idx -ge 0) { $f = $f.Substring($idx) }
        $f = 'res://' + $f.TrimStart('.', '/')
    }
    $gargs += "-gtest=$f"
} elseif ($Dirs.Count -gt 0) {
    $gargs += ('-gdir=' + ($Dirs -join ','))
    $gargs += '-ginclude_subdirs'
}
if ($Test) { $gargs += "-gunit_test_name=$Test" }

$r = Invoke-Godot -GodotArgs $gargs -TimeoutSec $TimeoutSec -WorkDir $proj
$all = $r.Stdout + "`n" + $r.Stderr
if ($all -match 'class_names have not been imported') {
    $lines += 'note: GUT classes were not imported; re-imported and retried once'
    $null = Invoke-Import -ProjectDir $proj -Force
    $r = Invoke-Godot -GodotArgs $gargs -TimeoutSec $TimeoutSec -WorkDir $proj
    $all = $r.Stdout + "`n" + $r.Stderr
}
[System.IO.File]::WriteAllText((Join-Path $reports 'test-output.txt'), $all)

$tests = 0
$failures = 0
$failLines = @()
if (Test-Path $junit) {
    try {
        [xml]$x = Get-Content $junit -Raw
        foreach ($c in $x.SelectNodes('//testcase')) {
            $tests++
            $fnode = $c.SelectSingleNode('failure')
            if ($null -eq $fnode) { $fnode = $c.SelectSingleNode('error') }
            if ($null -ne $fnode) {
                $failures++
                $msg = ''
                if ($fnode.Attributes['message']) { $msg = $fnode.Attributes['message'].Value }
                if (-not $msg) { $msg = $fnode.InnerText }
                $first = @(($msg -split "`r?`n") | Where-Object { $_.Trim() -ne '' } | Select-Object -First 1)
                if ($first.Count -gt 0) { $msg = $first[0].Trim() }
                $failLines += ('  FAIL ' + $c.GetAttribute('classname') + '::' + $c.GetAttribute('name') + ': ' + $msg)
            }
        }
    } catch {
        $lines += "note: could not parse junit.xml: $($_.Exception.Message)"
    }
}

$pass = ($r.ExitCode -eq 0) -and ($failures -eq 0) -and (-not $r.TimedOut)
if (-not (Test-Path $junit)) { $pass = $false }
$status = 'FAIL'
if ($pass) { $status = 'PASS' }
$lines += "TEST $Game result=$status exit=$($r.ExitCode) tests=$tests failures=$failures seconds=$($r.Seconds)"
if ($pass -and $tests -eq 0) { $lines += '  note: no tests found' }
$lines += $failLines
if (-not $pass -and $failures -eq 0) {
    $lines += '  (no test failures recorded; last output lines follow)'
    $tail = @(($all -split "`r?`n") | Where-Object { $_.Trim() -ne '' } | Select-Object -Last 15)
    foreach ($t in $tail) { $lines += "  $t" }
}
$lines += "artifacts: $reports (junit.xml, test-output.txt)"
Write-Lines -Lines $lines -Path $summaryPath -Quiet:$Quiet
if ($pass) { exit 0 } else { exit 1 }
