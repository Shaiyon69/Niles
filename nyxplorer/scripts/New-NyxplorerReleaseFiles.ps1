# Collects the signed Nyxplorer bundle and its runtime dependencies into:
#   <OutDir>\payload   everything Nyxplorer-Setup.exe embeds
#   <OutDir>\release   flat files for the GitHub Release, including Nyxplorer.appinstaller for in-app updates

param(
    [Parameter(Mandatory)] [string]$SourceRoot,
    [Parameter(Mandatory)] [string]$AppxPackageDir,
    [Parameter(Mandatory)] [string]$PfxPath,
    [Parameter(Mandatory)] [string]$PfxPassword,
    [Parameter(Mandatory)] [string]$OutDir,
    [Parameter(Mandatory)] [string]$Version,
    [Parameter(Mandatory)] [string]$Tag,
    [Parameter(Mandatory)] [string]$Repository
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
Add-Type -AssemblyName System.IO.Compression.FileSystem

$payload = Join-Path $OutDir "payload"
$payloadDeps = Join-Path $payload "Dependencies"
$release = Join-Path $OutDir "release"
New-Item -ItemType Directory -Force $payloadDeps, $release | Out-Null

# --- App bundle ---

$bundle = Get-ChildItem $AppxPackageDir -Recurse -Filter *.msixbundle | Select-Object -First 1
if (-not $bundle) { throw "No .msixbundle found under $AppxPackageDir" }
$releaseBundleName = "Nyxplorer_${Version}_x64.msixbundle"
Copy-Item $bundle.FullName (Join-Path $payload "Nyxplorer.msixbundle")
Copy-Item $bundle.FullName (Join-Path $release $releaseBundleName)

# --- Public certificate users must trust to install a self-signed package ---

$cert = New-Object Security.Cryptography.X509Certificates.X509Certificate2($PfxPath, $PfxPassword)

# The package publisher must equal the certificate subject, and the certificate must still be valid, or installs and updates fail
[xml]$manifestCheck = Get-Content (Join-Path $SourceRoot "src\Files.App\Package.appxmanifest")
if ($manifestCheck.Package.Identity.Publisher -ne $cert.Subject) {
    throw "Package publisher '$($manifestCheck.Package.Identity.Publisher)' does not match signing certificate subject '$($cert.Subject)'"
}
if ($cert.NotAfter -lt (Get-Date)) { throw "Signing certificate expired on $($cert.NotAfter.ToString('yyyy-MM-dd'))" }
if ($cert.NotAfter -lt (Get-Date).AddDays(60)) { Write-Warning "Signing certificate expires on $($cert.NotAfter.ToString('yyyy-MM-dd')); renewing it breaks in-place updates" }

$certBytes = $cert.Export([Security.Cryptography.X509Certificates.X509ContentType]::Cert)
[IO.File]::WriteAllBytes((Join-Path $payload "Nyxplorer.cer"), $certBytes)
[IO.File]::WriteAllBytes((Join-Path $release "Nyxplorer.cer"), $certBytes)

# --- Dependencies: VCLibs etc. from the packaging output, Windows App Runtime from the restored NuGet package ---

$buildDeps = Join-Path $bundle.DirectoryName "Dependencies\x64"
if (Test-Path $buildDeps) { Copy-Item (Join-Path $buildDeps "*") $payloadDeps }

[xml]$packagesProps = Get-Content (Join-Path $SourceRoot "Directory.Packages.props")
$sdkVersion = ($packagesProps.Project.ItemGroup.PackageVersion | Where-Object Include -eq "Microsoft.WindowsAppSDK").Version
$nugetRoot = $env:NUGET_PACKAGES ? $env:NUGET_PACKAGES : (Join-Path $env:USERPROFILE ".nuget\packages")
$runtimeMsix = Join-Path $nugetRoot "microsoft.windowsappsdk.runtime\$sdkVersion\tools\MSIX\win10-x64"
if (-not (Test-Path $runtimeMsix)) { throw "Windows App Runtime packages not found at $runtimeMsix (WindowsAppSDK $sdkVersion)" }
Copy-Item (Join-Path $runtimeMsix "*.msix") $payloadDeps -Force

Write-Host "Dependencies bundled into Setup:"
Get-ChildItem $payloadDeps | ForEach-Object { Write-Host "  $($_.Name)" }

# --- .NET Desktop Runtime (installed by Setup only when missing) ---

$dotnetInstaller = Join-Path $payload "windowsdesktop-runtime-win-x64.exe"
foreach ($attempt in 1..3) {
    try {
        Invoke-WebRequest "https://aka.ms/dotnet/10.0/windowsdesktop-runtime-win-x64.exe" -OutFile $dotnetInstaller
        break
    }
    catch {
        if ($attempt -eq 3) { throw }
        Write-Warning "Downloading the .NET Desktop Runtime failed (attempt $attempt): $($_.Exception.Message)"
        Start-Sleep -Seconds (5 * $attempt)
    }
}
$dotnetSignature = Get-AuthenticodeSignature $dotnetInstaller
if ($dotnetSignature.Status -ne "Valid" -or $dotnetSignature.SignerCertificate.Subject -notmatch "Microsoft") {
    throw ".NET Desktop Runtime installer is not validly signed by Microsoft (status $($dotnetSignature.Status))"
}

Copy-Item (Join-Path $PSScriptRoot "..\installer\Install-Nyxplorer.ps1") $payload

# --- Nyxplorer.appinstaller: lets installed copies update themselves from GitHub Releases ---

$download = "https://github.com/$Repository/releases/download/$Tag"
$dependencyXml = ""
foreach ($dep in Get-ChildItem $payloadDeps -File -Include *.msix, *.appx -Recurse) {
    $zip = [IO.Compression.ZipFile]::OpenRead($dep.FullName)
    try {
        $entry = $zip.Entries | Where-Object FullName -eq "AppxManifest.xml" | Select-Object -First 1
        if (-not $entry) { throw "$($dep.Name) has no AppxManifest.xml" }
        $reader = New-Object IO.StreamReader($entry.Open())
        [xml]$depManifest = $reader.ReadToEnd()
        $reader.Close()
    }
    finally { $zip.Dispose() }

    # Only framework packages belong in the appinstaller dependency list
    if ($depManifest.Package.Properties.Framework -ne "true") { continue }

    Copy-Item $dep.FullName (Join-Path $release $dep.Name)
    $id = $depManifest.Package.Identity
    $dependencyXml += @"

    <Package Name="$($id.Name)" Publisher="$($id.Publisher)" ProcessorArchitecture="$($id.ProcessorArchitecture)" Version="$($id.Version)" Uri="$download/$($dep.Name)" />
"@
}

[xml]$manifest = Get-Content (Join-Path $SourceRoot "src\Files.App\Package.appxmanifest")
$identity = $manifest.Package.Identity

@"
<?xml version="1.0" encoding="utf-8"?>
<AppInstaller Uri="https://github.com/$Repository/releases/latest/download/Nyxplorer.appinstaller" Version="$Version" xmlns="http://schemas.microsoft.com/appx/appinstaller/2018">
  <MainBundle Name="$($identity.Name)" Publisher="$($identity.Publisher)" Version="$Version" Uri="$download/$releaseBundleName" />
  <Dependencies>$dependencyXml
  </Dependencies>
</AppInstaller>
"@ | Set-Content (Join-Path $release "Nyxplorer.appinstaller") -Encoding utf8

# --- License page for Setup: Nyxplorer notice + upstream licenses + third-party notices (7-Zip etc. require them in binary redistributions) ---

$licenseText = (Get-Content (Join-Path $PSScriptRoot "..\NOTICE.md") -Raw)
foreach ($license in "LICENSE-MPL", "LICENSE-MIT", ".github\NOTICE.md") {
    $licensePath = Join-Path $SourceRoot $license
    if (Test-Path $licensePath) {
        $licenseText += "`r`n==================== $license ====================`r`n`r`n" + (Get-Content $licensePath -Raw)
    }
}
Set-Content (Join-Path $OutDir "license.txt") $licenseText -Encoding utf8

Write-Host "Release files:"
Get-ChildItem $release | ForEach-Object { Write-Host ("  {0} ({1:N1} MB)" -f $_.Name, ($_.Length / 1MB)) }
