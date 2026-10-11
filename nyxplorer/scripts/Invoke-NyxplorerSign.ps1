# Signs files with the Nyxplorer certificate (PFX) using the newest signtool from the Windows SDK.

param(
    [Parameter(Mandatory)]
    [string[]]$Path,

    [Parameter(Mandatory)]
    [string]$PfxPath,

    [Parameter(Mandatory)]
    [string]$PfxPassword
)

$ErrorActionPreference = "Stop"

$signtool = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin" -Recurse -Filter signtool.exe -ErrorAction SilentlyContinue |
    Where-Object { $_.DirectoryName -match '\\x64$' } |
    Sort-Object { [version]($_.DirectoryName -replace '^.*\\bin\\([^\\]+)\\.*$', '$1') } -Descending |
    Select-Object -First 1
if (-not $signtool) { throw "signtool.exe not found in the Windows SDK" }

foreach ($file in $Path) {
    & $signtool.FullName sign /fd SHA256 /f $PfxPath /p $PfxPassword /tr "http://timestamp.digicert.com" /td SHA256 $file
    if ($LASTEXITCODE -ne 0) { throw "signtool failed for $file" }
    Write-Host "Signed $file"
}
