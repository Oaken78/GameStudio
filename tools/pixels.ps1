# Reads pixel colors from screenshots, so contrast and readability checks use numbers instead of throwaway scripts.
# Prints one line per point: file, label, (x,y), #RRGGBB and luma (Rec. 709 weights on 0..1 sRGB values).
#   ./tools/pixels.ps1 -Image <png> sky=640:5 wall=60:300 120:400      a point is label=x:y or x:y
#   ./tools/pixels.ps1 -Image <png> -Column 800 -Rows 0,40,80          a vertical sweep (-Row y -Columns a,b for horizontal)
#   ./tools/pixels.ps1 -Image a.png,b.png sky=640:5                    the same points in every image (before/after)
# Exit 0 when every point was read, 2 on a bad argument, a missing image or a point outside the image.
[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Mandatory = $true)][string[]]$Image,
    [int]$Column = -1,
    [string[]]$Rows = @(),
    [int]$Row = -1,
    [string[]]$Columns = @(),
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Points = @()
)
. "$PSScriptRoot/_lib.ps1"
Add-Type -AssemblyName System.Drawing
# powershell -File passes "a,b" as one string; split so both call styles work.
$Image = @($Image | ForEach-Object { $_ -split ',' })
[int[]]$rowList = @($Rows | ForEach-Object { $_ -split ',' })
[int[]]$columnList = @($Columns | ForEach-Object { $_ -split ',' })

$targets = New-Object System.Collections.ArrayList
foreach ($p in $Points) {
    if ($p -notmatch '^(?:([^=]+)=)?(\d+):(\d+)$') {
        Write-Output "pixels: bad point '$p' (use label=x:y or x:y)"
        exit 2
    }
    $label = $Matches[1]
    if (-not $label) { $label = "$($Matches[2]):$($Matches[3])" }
    $null = $targets.Add([pscustomobject]@{ Label = $label; X = [int]$Matches[2]; Y = [int]$Matches[3] })
}
if ($Column -ge 0) { foreach ($y in $rowList) { $null = $targets.Add([pscustomobject]@{ Label = "x$Column"; X = $Column; Y = $y }) } }
if ($Row -ge 0) { foreach ($x in $columnList) { $null = $targets.Add([pscustomobject]@{ Label = "y$Row"; X = $x; Y = $Row }) } }
if ($targets.Count -eq 0) {
    Write-Output 'pixels: no points given (label=x:y, -Column x -Rows a,b or -Row y -Columns a,b)'
    exit 2
}

$bad = 0
foreach ($img in $Image) {
    if (-not (Test-Path -LiteralPath $img -PathType Leaf)) {
        Write-Output "pixels: no such image $img"
        exit 2
    }
    $path = (Resolve-Path -LiteralPath $img).ProviderPath
    $name = Split-Path $path -Leaf
    $bmp = [System.Drawing.Bitmap]::FromFile($path)
    try {
        foreach ($t in $targets) {
            if ($t.X -ge $bmp.Width -or $t.Y -ge $bmp.Height) {
                Write-Output ('{0} {1} ({2},{3}) outside the {4}x{5} image' -f $name, $t.Label, $t.X, $t.Y, $bmp.Width, $bmp.Height)
                $bad++
                continue
            }
            $c = $bmp.GetPixel($t.X, $t.Y)
            $luma = Format-Invariant ((0.2126 * $c.R + 0.7152 * $c.G + 0.0722 * $c.B) / 255) 3
            Write-Output ('{0} {1} ({2},{3}) #{4:X2}{5:X2}{6:X2} luma={7}' -f $name, $t.Label, $t.X, $t.Y, $c.R, $c.G, $c.B, $luma)
        }
    } finally {
        $bmp.Dispose()
    }
}
if ($bad -gt 0) { exit 2 }
exit 0
