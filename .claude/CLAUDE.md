# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Nyxplorer

Nyxplorer is a rebranded distribution of Files (MPL-2.0 / MIT) by Shaiyon69. This repository holds **only the Nyxplorer overlay**. The Files source is never committed here: every build checks out upstream `files-community/Files` at a release tag and patches it at build time.

- `nyxplorer/nyxplorer.config.json`: name, publisher, package identity, protocol, repository, default theme, default background color and backdrop (OLED: `#FF000000` + `Solid`)
- `nyxplorer/scripts/Apply-NyxplorerBranding.ps1`: regex-patches a clean upstream checkout at build time (identity, icons, updater URL, OLED dark default, app name in the splash/window title/title bar, blanked Sentry/Bing/GitHub OAuth secrets). `Update-File -Required` throws when upstream moved the targeted code, and cosmetic patches only warn. When upstream changes break a patch, fix the pattern here.
- `nyxplorer/assets/Nyxplorer.svg`: the single logo source. Tiles, `Logo.ico`, splash and wizard art are rendered from it by `nyxplorer/tools/render-svg.mjs` (Node, `@resvg/resvg-js`) via `New-NyxplorerTileAssets.ps1` / `New-NyxplorerInstallerImages.ps1`.
- `nyxplorer/installer/`: `Nyxplorer.iss` (Inno Setup 6 wizard) plus `Install-Nyxplorer.ps1`, which it runs in two stages: `Machine` (elevated: trust cert, .NET 10 Desktop Runtime, add an AppX package volume at the chosen folder) and `User` (via `ExecAsOriginalUser`: framework packages, then `Nyxplorer.msixbundle`). Exit codes: 2 = installed, but fell back to the system drive; 3 = installed in `<drive>\WindowsApps` because Windows refused a volume in the chosen folder.
- `.github/workflows/nyxplorer-release.yml`: checks out upstream at a tag into `upstream/` (this repo into `nyxplorer-repo/`), applies branding, builds and signs the msixbundle, runs `New-NyxplorerReleaseFiles.ps1` (payload, `Nyxplorer.appinstaller` for in-app updates, license page), compiles Setup, publishes a GitHub Release. Version = Nyxplorer `Major.Minor` from `nyxplorer.config.json` + next patch number (tag `v1.0.0`, package `1.0.0.0`).
- `.github/workflows/nyxplorer-sync.yml`: daily dry-run of branding against upstream main (opens an issue on breakage), and releases new upstream stable tags.
- `README.md` and `nyxplorer/NOTICE.md` are Nyxplorer-owned. `LICENSE-MPL` / `LICENSE-MIT` are copies of upstream's licenses.

Nyxplorer is an MSIX package: Windows manages the folder (`<folder>\WindowsApps`). Setup picks the folder that becomes a package volume (`/INSTALLPATH=D:\Apps\Nyxplorer`, or `/DRIVE=D:` for silent installs). Uninstall goes through Settings > Apps (`Uninstallable=no`).

### Script constraints

- `Install-Nyxplorer.ps1` runs on end-user machines under Windows PowerShell 5.1 (`powershell.exe`). Avoid PowerShell 7-only syntax there (ternary, `??`, `&&`).
- Build-time scripts in `nyxplorer/scripts/` run under `pwsh` 7 in CI and may use it.
- Release signing uses the same self-signed certificate every time (secrets `NYXPLORER_CERT_PFX` / `NYXPLORER_CERT_PASSWORD`, created once by `New-NyxplorerCertificate.ps1`). A different cert breaks in-place updates. Never commit `*.pfx` or the password file.
- Keep comments concise. Keep changes scoped to the request.

### Local verification

Dry-run branding against a separate clean upstream clone (it rewrites files in place):

```powershell
git clone --depth 1 --branch v4.2.9 https://github.com/files-community/Files.git <scratch>\upstream
pwsh nyxplorer/scripts/Apply-NyxplorerBranding.ps1 -SourceRoot <scratch>\upstream -Version 1.0.0.0
```

Compile the Setup wizard (ISCC needs `/DAppVersion`, `/DPayloadDir`, `/DLicenseFile`, `/DIconFile`, `/DOutputDir`; run from PowerShell, because Git Bash mangles `/D` arguments):

```powershell
& "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe" /Q /DAppVersion=1.0.0.0 /DPayloadDir=<dir> /DLicenseFile=<txt> /DIconFile=<upstream>\src\Files.App\Assets\AppTiles\Release\Logo.ico /DOutputDir=<dir> nyxplorer\installer\Nyxplorer.iss
```

### Legal

- Keep the "not affiliated with or endorsed by the Files Community" notice, the MPL/MIT texts and the third-party notices (upstream `.github/NOTICE.md`, appended to the Setup license page) in releases.
- Don't use Files branding as Nyxplorer branding.
