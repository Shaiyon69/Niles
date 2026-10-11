# Renders Setup wizard artwork from Nyxplorer.svg at several DPI scales:
#   corner images  logo over a soft glow so the dark folder stays visible on the dark wizard header
#   side panel     lit dark backdrop with the logo and a "Nyxplorer / by Shaiyon69" wordmark
# Writes comma-separated path lists for Inno Setup to <OutDir>\small.txt and <OutDir>\large.txt.

param(
    [Parameter(Mandatory)]
    [string]$OutDir
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
New-Item -ItemType Directory -Force $OutDir | Out-Null

$config = Get-Content (Join-Path $PSScriptRoot "..\nyxplorer.config.json") -Raw | ConvertFrom-Json

$masterPath = Join-Path $OutDir "nyxplorer-master-1024.png"
& (Join-Path $PSScriptRoot "Export-NyxplorerSvg.ps1") -Size 1024 -Output $masterPath
$master = [Drawing.Image]::FromFile($masterPath)

function New-Graphics([Drawing.Bitmap]$Bitmap) {
    $graphics = [Drawing.Graphics]::FromImage($Bitmap)
    $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::HighQuality
    $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.TextRenderingHint = [Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    return $graphics
}

function Draw-Glow([Drawing.Graphics]$Graphics, [float]$CenterX, [float]$CenterY, [float]$Radius, [int]$Alpha) {
    $path = New-Object Drawing.Drawing2D.GraphicsPath
    $path.AddEllipse($CenterX - $Radius, $CenterY - $Radius, 2 * $Radius, 2 * $Radius)
    $brush = New-Object Drawing.Drawing2D.PathGradientBrush($path)
    $brush.CenterColor = [Drawing.Color]::FromArgb($Alpha, 255, 255, 255)
    $brush.SurroundColors = @([Drawing.Color]::FromArgb(0, 255, 255, 255))
    $Graphics.FillPath($brush, $path)
    $brush.Dispose(); $path.Dispose()
}

function Draw-CenteredText([Drawing.Graphics]$Graphics, [string]$Text, [string]$Family, [float]$Pixels,
                           [Drawing.FontStyle]$Style, [Drawing.Color]$Color, [int]$Width, [float]$Top) {
    $font = New-Object Drawing.Font($Family, $Pixels, $Style, [Drawing.GraphicsUnit]::Pixel)
    $brush = New-Object Drawing.SolidBrush($Color)
    $format = New-Object Drawing.StringFormat
    $format.Alignment = [Drawing.StringAlignment]::Center
    $area = New-Object Drawing.RectangleF(0, $Top, $Width, ($Pixels * 2))
    $Graphics.DrawString($Text, $font, $brush, $area, $format)
    $format.Dispose(); $brush.Dispose(); $font.Dispose()
}

function Save-Small([int]$Size, [string]$Path) {
    $bitmap = New-Object Drawing.Bitmap($Size, $Size, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = New-Graphics $bitmap
    $graphics.Clear([Drawing.Color]::Transparent)
    Draw-Glow $graphics ($Size / 2) ($Size / 2) ($Size / 2) 70
    $logo = [int]($Size * 0.86)
    $graphics.DrawImage($master, [int](($Size - $logo) / 2), [int](($Size - $logo) / 2), $logo, $logo)
    $graphics.Dispose()
    $bitmap.Save($Path, [Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose()
    return $Path
}

function Save-Large([int]$Width, [int]$Height, [string]$Path) {
    $bitmap = New-Object Drawing.Bitmap($Width, $Height, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = New-Graphics $bitmap
    $background = New-Object Drawing.Drawing2D.LinearGradientBrush(
        (New-Object Drawing.Point(0, 0)), (New-Object Drawing.Point(0, $Height)),
        [Drawing.Color]::FromArgb(255, 58, 58, 62), [Drawing.Color]::FromArgb(255, 24, 24, 26))
    $graphics.FillRectangle($background, 0, 0, $Width, $Height)
    $background.Dispose()

    $logo = [int]($Width * 0.72)
    $logoTop = [int]($Height * 0.24)
    Draw-Glow $graphics ($Width / 2) ($logoTop + $logo / 2) ($Width * 0.62) 60
    $graphics.DrawImage($master, [int](($Width - $logo) / 2), $logoTop, $logo, $logo)

    $scale = $Width / 164.0
    $titleTop = $logoTop + $logo + 6 * $scale
    Draw-CenteredText $graphics $config.name "Segoe UI Semibold" (26 * $scale) ([Drawing.FontStyle]::Regular) `
        ([Drawing.Color]::FromArgb(255, 245, 245, 245)) $Width $titleTop
    Draw-CenteredText $graphics "by $($config.publisherDisplayName)" "Segoe UI" (11 * $scale) ([Drawing.FontStyle]::Regular) `
        ([Drawing.Color]::FromArgb(255, 170, 170, 175)) $Width ($titleTop + 36 * $scale)

    $graphics.Dispose()
    $bitmap.Save($Path, [Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose()
    return $Path
}

# Inno Setup's documented sizes for 100%, 150%, 200% and 250% scaling
$small = foreach ($s in 55, 83, 110, 138) {
    Save-Small $s (Join-Path $OutDir "wizard-small-$s.png")
}
$large = foreach ($dims in @(164, 314), @(246, 459), @(328, 604), @(410, 797)) {
    Save-Large $dims[0] $dims[1] (Join-Path $OutDir "wizard-large-$($dims[0]).png")
}

$master.Dispose()
Set-Content (Join-Path $OutDir "small.txt") ($small -join ",") -NoNewline
Set-Content (Join-Path $OutDir "large.txt") ($large -join ",") -NoNewline
Write-Host "  [installer art] $($small.Count) corner and $($large.Count) panel images in $OutDir"
