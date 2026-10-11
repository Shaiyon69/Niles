<p align="center"><img src="nyxplorer/assets/Nyxplorer.svg" width="128" alt="Nyxplorer logo"></p>

# Nyxplorer

Nyxplorer is a modern file manager for Windows by **Shaiyon69**, based on [Files](https://github.com/files-community/Files) by the Files Community. It starts in a true-black OLED dark theme, keeps itself up to date, and installs side by side with Files.

## Features

Nyxplorer keeps the full Files feature set and adds a night-first look:

- **True-black OLED theme** by default (`#000000` with a solid backdrop), so dark surfaces are actually dark. You can still switch theme and background in Settings.
- **Tabs and dual pane**: keep several folders open at once and work in two panes side by side.
- **Multiple layouts**: details, grid and columns views, with sorting and grouping.
- **File tags**: label files and folders with colored tags and find them again quickly.
- **Preview and info panes**: inspect a file without opening it.
- **Archives**: browse, extract and create compressed archives.
- **Git integration**: see repository status and branches in the folders you work in.
- **Cloud drives and network locations**: reach cloud-synced folders and FTP locations from the same window.
- **Integrated terminal**, bulk rename, and a customizable home page with widgets.

## Install

1. Open the [latest release](https://github.com/Shaiyon69/Nyxplorer/releases/latest) and download `Nyxplorer-Setup-<version>-x64.exe`.
2. Run it. If Windows shows *"Windows protected your PC"*, choose **More info → Run anyway**. Nyxplorer is signed with its own certificate rather than a paid one, so Windows doesn't recognise the publisher yet.
3. Approve the administrator prompt.
4. Pick the folder to install Nyxplorer in, or keep the Windows drive (for example `C:\`) for the default location. Nyxplorer is a Windows app package, so Windows keeps its files in a protected `WindowsApps` folder inside the folder you pick, the same way the Microsoft Store does. Any folder on an NTFS drive built into your PC works. If Windows won't use that folder, Setup falls back to `<drive>\WindowsApps`, then to the Windows drive, and tells you.
5. Setup trusts the Nyxplorer certificate, installs the .NET 10 Desktop Runtime and Windows App Runtime if they are missing (or keeps the newer versions you already have), and then installs Nyxplorer for your account.

Requires Windows 10 version 2004 (build 19041) or later, x64.

To uninstall, use **Settings → Apps → Installed apps → Nyxplorer → Uninstall**.

For unattended installs, run `Nyxplorer-Setup-<version>-x64.exe /VERYSILENT /INSTALLPATH=D:\Apps\Nyxplorer` (leave out `/INSTALLPATH` to use the default location; `/DRIVE=D:` also works and means `D:\`).

### If Setup fails

Setup saves a log named `Nyxplorer-Setup-Machine.log` or `Nyxplorer-Setup-User.log` to your desktop. Please [open an issue](https://github.com/Shaiyon69/Nyxplorer/issues) and attach it.

## Privacy

Nyxplorer has no telemetry. The crash reporting, map and sign-in service keys used by the upstream Files project are not included, so those features are turned off. Nyxplorer connects to GitHub to check for and download updates.

## Updates

Installed copies of Nyxplorer check this repository's releases and update themselves from inside the app.

Each day a GitHub Actions job checks for a new stable release of Files. When one appears, Nyxplorer is rebuilt from it with Nyxplorer branding and published here automatically.

## Credits and license

Nyxplorer is built from the source code of [Files](https://github.com/files-community/Files), Copyright (c) Files Community, under the [Mozilla Public License 2.0](LICENSE-MPL) and the [MIT License](LICENSE-MIT). Nyxplorer is not affiliated with or endorsed by the Files Community. Nyxplorer branding, installer and build tooling (everything in [`nyxplorer/`](nyxplorer) and `.github/workflows/nyxplorer-*.yml`) is by Shaiyon69. See [`nyxplorer/NOTICE.md`](nyxplorer/NOTICE.md). Nyxplorer also includes third-party components under their own licenses, listed in [Files' `.github/NOTICE.md`](https://github.com/files-community/Files/blob/main/.github/NOTICE.md) and on the Setup license page.

This repository holds only the Nyxplorer overlay. Each release is built from the unmodified Files release tag named in its release notes, plus the build-time patches in [`nyxplorer/scripts/Apply-NyxplorerBranding.ps1`](nyxplorer/scripts/Apply-NyxplorerBranding.ps1). Together they are the complete source of every release, including all files covered by the MPL 2.0.

---

## Maintainer guide

### How Nyxplorer stays update-safe

This repository doesn't contain the Files source. Every build checks out upstream Files at a release tag and applies the Nyxplorer overlay to it:

| Path | Purpose |
| --- | --- |
| `nyxplorer/nyxplorer.config.json` | Name, publisher, package identity, protocol, default theme and background |
| `nyxplorer/scripts/Apply-NyxplorerBranding.ps1` | Applies Nyxplorer identity, updater URL, OLED dark theme default, app name and UI strings to a clean upstream checkout at build time |
| `nyxplorer/assets/Nyxplorer.svg` | The Nyxplorer logo. Every app tile, taskbar/Start icon, `Logo.ico`, splash screen and the Setup wizard art are rendered from it during the build |
| `nyxplorer/installer/` | Setup wizard (Inno Setup) and its install script |
| `.github/workflows/nyxplorer-release.yml` | Builds a Nyxplorer release from an upstream tag |
| `.github/workflows/nyxplorer-sync.yml` | Daily: dry-runs the branding against upstream main, releases new upstream versions |

Because nothing upstream is forked into this repository, there is nothing to merge. Branding patches that matter (app name, OLED theme default, update source, package identity, crash reporting) fail the build loudly if upstream moves the code they target. A broken build is never published, and the daily dry-run opens an issue before that happens.

### One-time setup

1. Create the signing certificate and store it as repository secrets. The script needs the GitHub CLI to be logged in:
   ```powershell
   ./nyxplorer/scripts/New-NyxplorerCertificate.ps1
   ```
   This also writes a private backup to `Documents\Nyxplorer-signing`. Keep it safe and never commit it. Every release must use the same certificate, or installed copies can't update.
2. In the **Actions** tab, enable workflows.
3. Run **Nyxplorer Release** manually once (Actions → Nyxplorer Release → Run workflow) to publish the first installer.

### Building a specific upstream version

Actions → **Nyxplorer Release** → Run workflow → enter a Files tag such as `v4.2.9`. Turn off **publish** to get the installer as a build artifact without creating a release.

### Changing branding

Edit `nyxplorer/nyxplorer.config.json`, or replace `nyxplorer/assets/Nyxplorer.svg` with new artwork (square viewBox recommended). Changes apply on the next build.

### Testing branding locally

Clone upstream Files outside this repository and dry-run the overlay against it (it rewrites files in place):
```powershell
git clone --depth 1 --branch v4.2.9 https://github.com/files-community/Files.git ..\Files-upstream
pwsh nyxplorer/scripts/Apply-NyxplorerBranding.ps1 -SourceRoot ..\Files-upstream -Version 1.0.0.0
```
