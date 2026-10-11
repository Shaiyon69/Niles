# Renders nyxplorer/assets/Nyxplorer.svg to a square transparent PNG with resvg (Node), installing the tool on first use.

param(
    [Parameter(Mandatory)]
    [int]$Size,

    [Parameter(Mandatory)]
    [string]$Output,

    [string]$Svg = (Join-Path $PSScriptRoot "..\assets\Nyxplorer.svg")
)

$ErrorActionPreference = "Stop"

$tools = Join-Path $PSScriptRoot "..\tools"
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw "Node.js is required to render Nyxplorer.svg" }
if (-not (Test-Path (Join-Path $tools "node_modules\@resvg\resvg-js"))) {
    npm ci --prefix $tools --no-audit --no-fund --loglevel=error
    if ($LASTEXITCODE -ne 0) { throw "npm ci failed in $tools" }
}

node (Join-Path $tools "render-svg.mjs") $Svg $Output $Size
if ($LASTEXITCODE -ne 0) { throw "Rendering $Svg failed" }
