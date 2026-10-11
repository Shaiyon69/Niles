# Nyxplorer installer helper, run by Nyxplorer-Setup.exe.
#   -Stage Machine  (elevated)       trust the Nyxplorer signing certificate, install .NET Desktop Runtime if missing,
#                                    and prepare a package volume at -InstallPath unless it is on the system drive
#   -Stage User     (signed-in user) install Windows App Runtime / VCLibs packages, then the Nyxplorer bundle
# Payload layout next to this script:
#   Nyxplorer.cer, Nyxplorer.msixbundle, Dependencies\*.msix|*.appx, windowsdesktop-runtime-win-x64.exe
# Exit codes: 0 = success, 1 = failure, 2 = installed, but on the system drive instead of -InstallPath,
#             3 = installed, but in <drive>\WindowsApps because Windows refused a volume at -InstallPath

param(
    [Parameter(Mandatory)]
    [ValidateSet("Machine", "User")]
    [string]$Stage,

    # Folder for the Nyxplorer package volume, e.g. "D:\Apps\Nyxplorer" or "D:". Windows manages <folder>\WindowsApps itself.
    [ValidatePattern('^([A-Za-z]:(\\.*)?)?$')]
    [string]$InstallPath = "",

    [string]$LogPath = (Join-Path $env:TEMP "Nyxplorer-Setup-$Stage.log")
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$payload = $PSScriptRoot
Add-Type -AssemblyName System.IO.Compression.FileSystem

Start-Transcript -Path $LogPath -Force | Out-Null

# HRESULTs that mean "an equal or newer version is already installed"
$alreadyInstalled = @(0x80073D06, 0x80073CFB) | ForEach-Object { [int]$_ }

$systemDrive = $env:SystemDrive.ToUpperInvariant()
if (-not $InstallPath) { $InstallPath = $systemDrive }
$targetPath = $InstallPath.TrimEnd('\')
$targetDrive = $targetPath.Substring(0, 2).ToUpperInvariant()
$isDriveRoot = $targetPath.Length -eq 2
# Windows keeps one package store per drive, and the system drive's is always Program Files\WindowsApps
$useCustomVolume = $targetDrive -ne $systemDrive

function Get-PackageIdentity([string]$Path) {
    $zip = [IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $entry = $zip.Entries | Where-Object FullName -eq "AppxManifest.xml" | Select-Object -First 1
        if (-not $entry) { return $null }
        $reader = New-Object IO.StreamReader($entry.Open())
        try { [xml]$manifest = $reader.ReadToEnd() } finally { $reader.Close() }
        return $manifest.Package.Identity
    }
    finally { $zip.Dispose() }
}

function Test-AlreadyInstalledError($ErrorRecord) {
    # Add-AppxPackage reports a generic HResult on the exception; the deployment HRESULT is often only in the message
    for ($e = $ErrorRecord.Exception; $e; $e = $e.InnerException) {
        if ($alreadyInstalled -contains $e.HResult) { return $true }
    }
    return "$($ErrorRecord.Exception.Message)" -match '0x80073D06|0x80073CFB'
}

function Test-NewerInstalled([string]$Path) {
    $identity = Get-PackageIdentity $Path
    if (-not $identity) { return $false }
    $installed = Get-AppxPackage -Name $identity.Name |
        Where-Object { "$($_.Architecture)" -eq $identity.ProcessorArchitecture -and [version]$_.Version -ge [version]$identity.Version } |
        Select-Object -First 1
    if ($installed) {
        Write-Host "Already up to date: $(Split-Path $Path -Leaf) (installed $($installed.Version))"
        return $true
    }
    return $false
}

function Add-PackageQuietly([string]$Path, $Volume = $null) {
    if (Test-NewerInstalled $Path) { return }
    $arguments = @{ Path = $Path; ForceApplicationShutdown = $true }
    if ($Volume) { $arguments.Volume = $Volume }
    try {
        Add-AppxPackage @arguments
        Write-Host "Installed $(Split-Path $Path -Leaf)"
    }
    catch {
        # 0x80073CFB also covers a different build with the same version, which Windows keeps instead of this one
        if ("$($_.Exception.Message)" -match 'contents are different') {
            throw "A different build of $(Split-Path $Path -Leaf) with the same version is already installed. Uninstall it from Settings > Apps, then run Setup again."
        }
        if (Test-AlreadyInstalledError $_) {
            Write-Host "Already up to date: $(Split-Path $Path -Leaf)"
        }
        else { throw }
    }
}

# The package volume inside a folder ("D:\Apps\Nyxplorer\WindowsApps") or on a drive ("D:\WindowsApps")
function Get-PackageVolume([string]$Folder) {
    $prefix = "$($Folder.TrimEnd('\'))\"
    Get-AppxVolume |
        Where-Object { "$($_.PackageStorePath)\".StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) } |
        Select-Object -First 1
}

function Add-PackageVolume([string]$Folder) {
    $volume = Get-PackageVolume $Folder
    if (-not $volume) {
        # Windows versions differ on whether -Path takes the parent folder or the WindowsApps folder itself
        try { Add-AppxVolume -Path "$Folder\" | Out-Null }
        catch { Add-AppxVolume -Path "$Folder\WindowsApps" | Out-Null }
        $volume = Get-PackageVolume $Folder
    }
    if ($volume -and $volume.IsOffline) { Mount-AppxVolume -Volume $volume }
    return $volume
}

# The volume Setup prepared: the chosen folder first, then the root of its drive (never the system drive)
function Find-TargetVolume {
    $volume = Get-PackageVolume $targetPath
    if ($volume) { return @{ Volume = $volume; ExitCode = 0 } }
    if (-not $isDriveRoot -and $targetDrive -ne $systemDrive) {
        $volume = Get-PackageVolume $targetDrive
        if ($volume) { return @{ Volume = $volume; ExitCode = 3 } }
    }
    return $null
}

try {
    if ($Stage -eq "Machine") {
        $cert = New-Object Security.Cryptography.X509Certificates.X509Certificate2(Join-Path $payload "Nyxplorer.cer")
        $store = New-Object Security.Cryptography.X509Certificates.X509Store("TrustedPeople", "LocalMachine")
        $store.Open("ReadWrite")
        if (-not ($store.Certificates | Where-Object Thumbprint -eq $cert.Thumbprint)) {
            $store.Add($cert)
            Write-Host "Trusted Nyxplorer certificate $($cert.Subject) ($($cert.Thumbprint))"
        }
        $store.Close()

        $desktopRuntimes = Join-Path $env:ProgramFiles "dotnet\shared\Microsoft.WindowsDesktop.App"
        $hasRuntime = (Test-Path $desktopRuntimes) -and (Get-ChildItem $desktopRuntimes -Directory -Filter "10.*")
        if ($hasRuntime) {
            Write-Host ".NET 10 Desktop Runtime already installed"
        }
        else {
            Write-Host "Installing .NET 10 Desktop Runtime..."
            $process = Start-Process (Join-Path $payload "windowsdesktop-runtime-win-x64.exe") `
                -ArgumentList "/install", "/quiet", "/norestart" -Wait -PassThru
            # 3010 = success, restart required
            if ($process.ExitCode -notin 0, 3010) { throw ".NET Desktop Runtime installer failed with exit code $($process.ExitCode)" }
        }

        # Adding a package volume needs admin rights, so it happens here rather than in the User stage
        if ($useCustomVolume) {
            $volume = $null
            try {
                if (-not $isDriveRoot) { New-Item -ItemType Directory -Path $targetPath -Force | Out-Null }
                $volume = Add-PackageVolume $targetPath
                if (-not $volume) { Write-Host "WARNING: Windows did not create a package volume in $targetPath" }
            }
            catch {
                Write-Host "WARNING: could not prepare $targetPath for apps: $($_.Exception.Message)"
            }

            # Some Windows versions only accept volumes at a drive root
            if (-not $volume -and -not $isDriveRoot -and $targetDrive -ne $systemDrive) {
                try {
                    $volume = Add-PackageVolume $targetDrive
                    if ($volume) { Write-Host "Falling back to the drive root of $targetDrive" }
                }
                catch {
                    Write-Host "WARNING: could not prepare $targetDrive for apps: $($_.Exception.Message)"
                }
            }

            # Without a volume the User stage falls back to the system drive and tells the user
            if ($volume) { Write-Host "Package volume ready: $($volume.PackageStorePath)" }
        }
    }
    else {
        # Framework packages before the packages that depend on them. They stay on the system drive.
        $order = { switch -Regex ($_.Name) { '^Microsoft\.VCLibs' { 0 } '^Microsoft\.WindowsAppRuntime\.\d' { 1 } default { 2 } } }
        Get-ChildItem (Join-Path $payload "Dependencies") -File -Include *.msix, *.appx -Recurse |
            Sort-Object $order, Name |
            ForEach-Object { Add-PackageQuietly $_.FullName }

        $bundle = Join-Path $payload "Nyxplorer.msixbundle"
        $exitCode = 0
        $target = if ($useCustomVolume) { Find-TargetVolume } else { $null }
        if ($useCustomVolume -and -not $target) {
            Write-Host "WARNING: no package volume in $targetPath, installing on $systemDrive instead"
            Add-PackageQuietly $bundle
            $exitCode = 2
        }
        elseif ($target) {
            try {
                Add-PackageQuietly $bundle $target.Volume
                $exitCode = $target.ExitCode
            }
            catch {
                Write-Host "WARNING: installing in $($target.Volume.PackageStorePath) failed ($($_.Exception.Message)), installing on $systemDrive instead"
                Add-PackageQuietly $bundle
                $exitCode = 2
            }
        }
        else {
            Add-PackageQuietly $bundle
        }
        Write-Host "Nyxplorer installed"
    }
    if (-not $exitCode) { $exitCode = 0 }
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    $exitCode = 1
}

Stop-Transcript | Out-Null
exit $exitCode
