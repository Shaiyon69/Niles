# Renders the Nyxplorer master logo over every PNG tile in an upstream AppTiles folder, keeping each file's
# name and pixel size, and rebuilds Logo.ico. New tiles added upstream are covered automatically.

param(
    [Parameter(Mandatory)]
    [string]$Master,

    [Parameter(Mandatory)]
    [string]$TargetDir
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$masterImage = [Drawing.Image]::FromFile((Resolve-Path $Master).Path)

function New-Canvas([int]$Width, [int]$Height, [double]$LogoScale, [bool]$Monochrome) {
    $bitmap = New-Object Drawing.Bitmap($Width, $Height, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $graphics.Clear([Drawing.Color]::Transparent)
    $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::HighQuality
    $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality

    $size = [Math]::Max(1, [int][Math]::Round([Math]::Min($Width, $Height) * $LogoScale))
    $x = [int](($Width - $size) / 2)
    $y = [int](($Height - $size) / 2)
    $destination = New-Object Drawing.Rectangle($x, $y, $size, $size)

    if ($Monochrome) {
        # Badge logos must be white silhouettes: keep alpha, force RGB to white
        $matrix = New-Object Drawing.Imaging.ColorMatrix
        $matrix.Matrix00 = 0; $matrix.Matrix11 = 0; $matrix.Matrix22 = 0
        $matrix.Matrix40 = 1; $matrix.Matrix41 = 1; $matrix.Matrix42 = 1
        $attributes = New-Object Drawing.Imaging.ImageAttributes
        $attributes.SetColorMatrix($matrix)
        $graphics.DrawImage($masterImage, $destination, 0, 0, $masterImage.Width, $masterImage.Height, [Drawing.GraphicsUnit]::Pixel, $attributes)
    }
    else {
        $graphics.DrawImage($masterImage, $destination)
    }

    $graphics.Dispose()
    return $bitmap
}

function Get-LogoScale([string]$Name) {
    switch -Regex ($Name) {
        '^(Wide310x150Logo|SplashScreen)' { return 0.62 }
        '^(Square150x150Logo|Small71x71Logo|Large310x310Logo)' { return 0.66 }
        default { return 1.0 }
    }
}

$count = 0
Get-ChildItem $TargetDir -Filter *.png | ForEach-Object {
    $existing = [Drawing.Image]::FromFile($_.FullName)
    $width = $existing.Width
    $height = $existing.Height
    $existing.Dispose()

    $bitmap = New-Canvas $width $height (Get-LogoScale $_.Name) ($_.Name -like 'BadgeLogo*')
    $bitmap.Save($_.FullName, [Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose()
    $count++
}

# Logo.ico with PNG-compressed entries
$icoSizes = 16, 20, 24, 32, 40, 48, 64, 128, 256
$entries = foreach ($size in $icoSizes) {
    $bitmap = New-Canvas $size $size 1.0 $false
    $stream = New-Object IO.MemoryStream
    $bitmap.Save($stream, [Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose()
    [pscustomobject]@{ Size = $size; Bytes = $stream.ToArray() }
}

$ico = New-Object IO.MemoryStream
$writer = New-Object IO.BinaryWriter($ico)
$writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]$entries.Count)
$offset = 6 + 16 * $entries.Count
foreach ($entry in $entries) {
    $dimension = if ($entry.Size -ge 256) { 0 } else { $entry.Size }
    $writer.Write([byte]$dimension); $writer.Write([byte]$dimension)
    $writer.Write([byte]0); $writer.Write([byte]0)
    $writer.Write([uint16]1); $writer.Write([uint16]32)
    $writer.Write([uint32]$entry.Bytes.Length); $writer.Write([uint32]$offset)
    $offset += $entry.Bytes.Length
}
foreach ($entry in $entries) { $writer.Write($entry.Bytes) }
$writer.Flush()
[IO.File]::WriteAllBytes((Join-Path $TargetDir "Logo.ico"), $ico.ToArray())
$writer.Dispose()

$masterImage.Dispose()
Write-Host "  [icons] rendered $count tile(s) and Logo.ico into $TargetDir"
