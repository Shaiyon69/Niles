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

$timestampServers = "http://timestamp.digicert.com", "http://timestamp.sectigo.com", "http://timestamp.globalsign.com/tsa/r6advanced1"

foreach ($file in $Path) {
    if (-not (Test-Path $file)) { throw "Cannot sign missing file $file" }
    $signed = $false
    # Timestamp servers are flaky: try each one, twice
    foreach ($attempt in 1..2) {
        foreach ($server in $timestampServers) {
            & $signtool.FullName sign /fd SHA256 /f $PfxPath /p $PfxPassword /tr $server /td SHA256 $file
            if ($LASTEXITCODE -eq 0) { $signed = $true; break }
            Write-Warning "signtool failed for $file using $server (exit $LASTEXITCODE)"
        }
        if ($signed) { break }
        Start-Sleep -Seconds 5
    }
    if (-not $signed) { throw "signtool failed for $file" }
    Write-Host "Signed $file"
}
