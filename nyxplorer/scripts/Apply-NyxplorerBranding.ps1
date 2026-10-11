# Nyxplorer branding overlay for Files (MPL-2.0).
# Applies Nyxplorer identity, icons, updater and dark-mode default to a clean upstream checkout at build time,
# so upstream source files never carry Nyxplorer changes and upstream merges never conflict.
#
# Required patches throw when upstream code moved, so a release is never built with half-applied branding.
# Cosmetic patches only warn.

param(
    [Parameter(Mandatory)]
    [string]$SourceRoot,

    [Parameter(Mandatory)]
    [string]$Version,

    [string]$ConfigPath = (Join-Path $PSScriptRoot "..\nyxplorer.config.json")
)

$ErrorActionPreference = "Stop"

$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$SourceRoot = (Resolve-Path $SourceRoot).Path
$appDir = Join-Path $SourceRoot "src\Files.App"
$repoUrl = "https://github.com/$($config.repository)"
$appInstallerUrl = "$repoUrl/releases/latest/download/$($config.packageName).appinstaller"

$script:Warnings = @()

function Read-TextFile([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $text = [Text.Encoding]::UTF8.GetString($bytes, ($hasBom ? 3 : 0), $bytes.Length - ($hasBom ? 3 : 0))
    return @{ Text = $text; Bom = $hasBom }
}

function Write-TextFile([string]$Path, [string]$Text, [bool]$Bom) {
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($Bom)))
}

# Regex-replaces inside one file. $Replacement uses .NET syntax ($1, ${name}; $$ for a literal $).
function Update-File {
    param(
        [string]$Path,
        [string]$Pattern,
        [string]$Replacement,
        [string]$What,
        [switch]$Required
    )

    $fullPath = Join-Path $SourceRoot $Path
    $found = (Test-Path $fullPath) ? (Read-TextFile $fullPath) : $null
    $count = $found ? ([regex]::Matches($found.Text, $Pattern)).Count : 0

    if ($count -eq 0) {
        $message = "[$What] pattern not found in $Path. Upstream changed this code; update nyxplorer/scripts/Apply-NyxplorerBranding.ps1."
        if ($Required) { throw $message }
        Write-Warning $message
        $script:Warnings += $What
        return
    }

    Write-TextFile $fullPath ([regex]::Replace($found.Text, $Pattern, $Replacement)) $found.Bom
    Write-Host "  [$What] $count change(s) in $Path"
}

# Literal replace across a file tree. Returns the number of files changed.
function Update-Tree {
    param(
        [string[]]$Include,
        [string]$Find,
        [string]$Replace,
        [string]$What,
        [switch]$Required
    )

    $changed = 0
    Get-ChildItem (Join-Path $SourceRoot "src") -Recurse -File -Include $Include |
        Where-Object { $_.FullName -notmatch '\\(bin|obj)\\' } |
        ForEach-Object {
            $file = Read-TextFile $_.FullName
            if ($file.Text.Contains($Find)) {
                Write-TextFile $_.FullName $file.Text.Replace($Find, $Replace) $file.Bom
                $changed++
            }
        }

    if ($changed -eq 0) {
        $message = "[$What] '$Find' not found under src. Upstream changed this code; update nyxplorer/scripts/Apply-NyxplorerBranding.ps1."
        if ($Required) { throw $message }
        Write-Warning $message
        $script:Warnings += $What
        return
    }

    Write-Host "  [$What] $changed file(s) changed"
}

Write-Host "Applying $($config.name) branding to $SourceRoot (version $Version)"

# --- Distribution channel: SideloadStable, with Nyxplorer-owned protocol, alias and assets ---

Update-Tree -Include *.cs -Find "cd_app_env_placeholder" -Replace "SideloadStable" -What "app environment" -Required
Update-Tree -Include *.cs, *.cpp, *.h, *.appxmanifest -Find "files-dev" -Replace $config.protocol -What "protocol and alias" -Required
Update-Tree -Include *.csproj, *.appxmanifest, *.xaml -Find "Assets\AppTiles\Dev" -Replace "Assets\AppTiles\Release" -What "tile asset paths" -Required

# --- Secrets: Nyxplorer has no upstream service keys; empty values disable Sentry, Bing Maps and GitHub OAuth ---

Update-File "src\Files.App\Constants.cs" '"sentry\.secret"' '""' -What "disable upstream crash reporting" -Required
Update-File "src\Files.App\Constants.cs" '"bingmapskey\.secret"' '""' -What "bing maps key"
Update-File "src\Files.App\Constants.cs" '"githubclientid\.secret"' '""' -What "github oauth id"

# --- Links that should go to Nyxplorer rather than upstream ---

Update-File "src\Files.App\Constants.cs" '(GitHubRepoUrl\s*=\s*@")[^"]*(")' "`${1}$repoUrl`${2}" -What "repository link"
Update-File "src\Files.App\Constants.cs" '(BugReportUrl\s*=\s*@")[^"]*(")' "`${1}$repoUrl/issues/new`${2}" -What "bug report link"

# --- Updater: Nyxplorer installs update from Nyxplorer GitHub Releases, never from files.community ---

$updater = "src\Files.App\Services\App\AppUpdateSideloadService.cs"
Update-File $updater '(SIDELOAD_STABLE\s*=\s*")[^"]*(")' "`${1}$appInstallerUrl`${2}" -What "update source" -Required
Update-File $updater '\{\s*"Files"\s*,\s*SIDELOAD_STABLE\s*\}' "{ `"$($config.packageName)`", SIDELOAD_STABLE }" -What "update package name" -Required

# --- Theme: full-black OLED dark by default for new installs (users can still change it in Settings) ---

$appearance = "src\Files.App\Services\Settings\AppearanceSettingsService.cs"
Update-File $appearance `
    '(string\s+AppThemeMode\s*\{\s*get\s*=>\s*Get\(")Default("\))' `
    "`${1}$($config.defaultTheme)`${2}" -What "default theme" -Required
Update-File $appearance `
    '(String\s+AppThemeBackgroundColor\s*\{\s*get\s*=>\s*Get\(")#00000000("\))' `
    "`${1}$($config.defaultBackgroundColor)`${2}" -What "default background" -Required
# Mica and Acrylic tint the background, so OLED needs a solid backdrop
Update-File $appearance `
    '(BackdropMaterialType\s+AppThemeBackdropMaterial\s*\{\s*get\s*=>\s*Get\(BackdropMaterialType\.)\w+(\))' `
    "`${1}$($config.defaultBackdrop)`${2}" -What "default backdrop" -Required
foreach ($area in 'AddressBar', 'Toolbar', 'Sidebar', 'FileArea', 'FileAreaSecondary', 'InfoPane') {
    Update-File $appearance `
        "(String\s+AppTheme${area}BackgroundColor\s*\{\s*get\s*=>\s*Get\("")(""\))" `
        "`${1}$($config.defaultBackgroundColor)`${2}" -What "default $area background"
}

# --- Tray icon id must differ from Files so both apps can run side by side ---

Update-File "src\Files.App\Utils\Taskbar\SystemTrayIcon.cs" `
    '(AppEnvironment\.SideloadStable\s*=>\s*new Guid\(")[^"]*("\))' `
    "`${1}$($config.trayIconGuid)`${2}" -What "tray icon id"

# --- English UI strings that name the app ---

# Case-sensitive phrase pairs (a hashtable would merge "Open"/"open")
${n} = $config.name
$stringReplacements = @(
    , @('<value>Files</value>', "<value>${n}</value>")
    , @('Welcome to Files!', "Welcome to ${n}!")
    , @('>Files ran into', ">${n} ran into")
    , @('>Files cannot', ">${n} cannot")
    , @(">Files can't", ">${n} can't")
    , @('>Files is ', ">${n} is ")
    , @('Set Files as', "Set ${n} as")
    , @('Use Files as', "Use ${n} as")
    , @('opening Files from', "opening ${n} from")
    , @('Open Files on', "Open ${n} on")
    , @('open Files on', "open ${n} on")
    , @('>Update Files<', ">Update ${n}<")
    , @('Enjoying Files?', "Enjoying ${n}?")
    , @('running Files as', "running ${n} as")
    , @('using Files without', "using ${n} without")
    , @('Where did Files go?', "Where did ${n} go?")
    , @('Show Files icon', "Show ${n} icon")
    , @('the Files team', "the ${n} developers")
)
foreach ($lang in 'en-US', 'en-GB') {
    $resw = Join-Path $appDir "Strings\$lang\Resources.resw"
    if (-not (Test-Path $resw)) { continue }
    $file = Read-TextFile $resw
    $text = $file.Text
    foreach ($pair in $stringReplacements) { $text = $text.Replace($pair[0], $pair[1]) }
    Write-TextFile $resw $text $file.Bom
    Write-Host "  [ui strings] updated $lang"
}

# --- Hardcoded app name shown at launch (splash, window title, title bar while browsing) ---

Update-File "src\Files.App\Views\SplashScreenPage.xaml" `
    '(<Run\s+FontWeight="SemiBold"\s+Text=")Files("\s*/>)' "`${1}${n}`${2}" -What "splash screen name" -Required
Update-File "src\Files.App\MainWindow.xaml.cs" '(\bTitle\s*=\s*")Files(";)' "`${1}${n}`${2}" -What "window title" -Required
Update-File "src\Files.App\Helpers\Navigation\NavigationHelpers.cs" `
    '(\{windowTitle\} - )Files(")' "`${1}${n}`${2}" -What "title bar suffix" -Required
Update-File "src\Files.App\Constants.cs" '(MissingRuntimeTitle\s*=\s*")Files( - )' "`${1}${n}`${2}" -What "startup error title"
Update-File "src\Files.App\Constants.cs" '(MissingRuntimeMessage\s*=\s*")[^"]*(")' `
    "`${1}${n} failed to start. A required Windows component could not be loaded. Try reinstalling ${n} from $repoUrl/releases`${2}" `
    -What "startup error message"

# --- Package manifest identity ---

$manifestPath = Join-Path $appDir "Package.appxmanifest"
[xml]$manifest = Get-Content $manifestPath -Raw
$ns = New-Object Xml.XmlNamespaceManager($manifest.NameTable)
$ns.AddNamespace("pkg", "http://schemas.microsoft.com/appx/manifest/foundation/windows10")
$ns.AddNamespace("uap", "http://schemas.microsoft.com/appx/manifest/uap/windows10")
$ns.AddNamespace("uap5", "http://schemas.microsoft.com/appx/manifest/uap/windows10/5")

$manifest.Package.Identity.Name = $config.packageName
$manifest.Package.Identity.Publisher = $config.publisher
$manifest.Package.Identity.Version = $Version
$manifest.Package.Properties.DisplayName = $config.name
$manifest.Package.Properties.PublisherDisplayName = $config.publisherDisplayName

$visual = $manifest.SelectSingleNode("/pkg:Package/pkg:Applications/pkg:Application/uap:VisualElements", $ns)
$visual.SetAttribute("DisplayName", $config.name)
$visual.SetAttribute("Description", $config.description)
$manifest.SelectSingleNode("//uap:DefaultTile", $ns).SetAttribute("ShortName", $config.name)

$startup = $manifest.SelectSingleNode("//uap5:StartupTask", $ns)
if ($startup) { $startup.SetAttribute("DisplayName", $config.name) }

$manifest.Save($manifestPath)
Write-Host "  [manifest] $($config.packageName) $Version by $($config.publisher)"

# --- Icons: render nyxplorer/assets/Nyxplorer.svg over every upstream Release tile, then drop Dev/Preview tiles ---

$masterPng = Join-Path ([IO.Path]::GetTempPath()) "nyxplorer-master-1024.png"
& (Join-Path $PSScriptRoot "Export-NyxplorerSvg.ps1") -Size 1024 -Output $masterPng

$tilesDir = Join-Path $appDir "Assets\AppTiles"
& (Join-Path $PSScriptRoot "New-NyxplorerTileAssets.ps1") `
    -Master $masterPng `
    -TargetDir (Join-Path $tilesDir "Release")

foreach ($folder in 'Dev', 'Preview') {
    $path = Join-Path $tilesDir $folder
    if (Test-Path $path) { Remove-Item $path -Recurse -Force }
}

if ($script:Warnings.Count -gt 0) {
    Write-Host "::warning::Nyxplorer branding finished with cosmetic warnings: $($script:Warnings -join ', ')"
}
Write-Host "Nyxplorer branding applied."
