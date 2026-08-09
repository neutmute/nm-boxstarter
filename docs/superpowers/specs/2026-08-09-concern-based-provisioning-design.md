# Concern-Based Provisioning Design

**Date:** 2026-08-09  
**Status:** Approved

## Overview

Replace environment-variable-based install profiles in `base-box.ps1` with an interactive concern system. Each concern maps to a discrete area of machine setup. The user is prompted at run-time; answers are persisted to `neutmute-boxstarter.json` in the user's Documents folder and reloaded on subsequent runs (including Boxstarter reboot-resume cycles).

Remove all Windows 10 specific scripts and dead code. Absorb Windows 11 cleanup inline.

## Concerns

Nine concerns, all user-selectable:

| Concern key | What it installs / configures |
|---|---|
| `core` | Bitwarden, Firefox, Chrome, Notepad++, Paint.NET, IrfanView, 7zip, ShutUp10, VeraCrypt, WinDirStat, WakeOnLan |
| `baseSettings` | Explorer options, execution policy, power (hibernate off), taskbar combine, Bing search off, passwordless logon registry key |
| `regionalSettings` | AU Eastern timezone, dd-MMM-yy date format, HH:mm:ss time format |
| `ddrive` | Label D: as "Data", relocate Documents, Pictures, Desktop, Videos, Music, Downloads to D: |
| `home` | Enable Remote Desktop, disable Game Bar tips, Syncback, Spotify, Joplin, Calibre, Winamp, Audacity, AllDup, BeeBEEP, SendToKindle, Signal |
| `dev` | Git, VS Code, Slack, SSMS, Putty, RDCMan, WinSCP, DiffMerge, GitExtensions, Nmap, OpenSSL, SQLiteBrowser, Checksum, AutoHotKey, Wintail, NuGet CLI, SourceTree, AWS PowerShell tools |
| `iis` | IIS Windows features (full set), URL Rewrite module |
| `visualStudio` | Visual Studio 2026 Community (all workloads, recommended, passive) |
| `htpc` | Steam, Syncback, Kodi |

## Config File

**Path:** `[Environment]::GetFolderPath('MyDocuments')\neutmute-boxstarter.json`

```json
{
  "concerns": {
    "core": true,
    "baseSettings": true,
    "regionalSettings": true,
    "ddrive": false,
    "home": true,
    "dev": false,
    "iis": false,
    "visualStudio": false,
    "htpc": false
  }
}
```

## Interactive Prompt Flow (`Get-Concerns`)

Runs at the very top of `base-box.ps1` before any installation work:

1. Check for `neutmute-boxstarter.json` in Documents.
2. **If the config file exists** (subsequent runs, including Boxstarter reboot-resume): load it and apply the saved concerns with NO prompting — fully unattended. Missing keys default to No. Print the selected-concern summary and return.
3. **If the config file does not exist** (first run): prompt for each concern (fixed order) with `Install Core apps? [y/N]:`. Default is N (Enter = No); the user types `y` to opt in. Save `$concerns` to JSON, print the summary, and return.

To reconfigure after the first run, delete `neutmute-boxstarter.json` and run again.

## Execution Order

```
1.  Get-Concerns                       always — prompts/loads JSON, saves result
2.  SetRegionalSettings                if concerns.regionalSettings
3.  InstallWindowsUpdate               always
4.  InstallGraphicsDrivers             always (auto-detects NVIDIA)
5.  choco allowGlobalConfirmation      always
6.  ConfigureBaseSettings              if concerns.baseSettings
7.  InstallChocoApps $userSettingsApps always (lightweight taskbar/Explorer tweaks)
8.  InstallChocoApps $coreApps        if concerns.core
9.  ConfigureDdrive                    if concerns.ddrive
10. InstallChocoApps $homeApps         if concerns.home
11. InstallChocoApps $htpcApps         if concerns.htpc
12. InstallChocoDevApps                if concerns.dev
13. InstallInternetInformationServices if concerns.iis
14. InstallVisualStudio                if concerns.visualStudio
15. CleanDesktopShortcuts              always
16. DownloadConfigFiles                always
17. Win11 tweaks (inline)              always
```

## Win11 Tweaks (Inline, Always Runs)

Absorbed from `win11-clean.ps1` into `base-box.ps1`:

- Restore classic right-click context menu (registry)
- Block "Edit in Notepad" shell extension (registry)
- `winget uninstall Microsoft.OneDrive`
- Christitus tweaks: `iwr -useb https://christitus.com/win | iex`

`win11-clean.ps1` is kept as a standalone script for manual use but is no longer called from `base-box.ps1`.

## Removals

- **`win10-clean.ps1`** — deleted from repo (Windows 10 specific, irrelevant for Win11)
- **`InstallSqlServer()`** — removed (dead code; MyGet package source stale)
- **`Install-BoxstarterPackage` call to win10-clean.ps1** — removed from bottom of `base-box.ps1`
- **`Start-Process` calls** opening win10/win11 scripts in browser — removed
- **`$hasDdrive` auto-detect** — replaced by `ddrive` concern
- **Env var checks** (`BoxStarterInstallDev`, `BoxStarterInstallHome`, `BoxStarterInstallHtpc`) — removed

## Idempotency

The script must be safe to run multiple times on the same machine.

**Chocolatey packages:** `InstallChocoApps` is replaced with `Install-ChocoPackage`, a wrapper that calls `choco list --local-only` to check if a package is already installed before invoking `choco install`. Already-installed packages are skipped.

**Registry/config operations:** Most Boxstarter cmdlets (`Set-WindowsExplorerOptions`, `Set-BoxstarterTaskbarOptions`, etc.) and `Set-ItemProperty` calls are already idempotent by nature. No special handling needed.

**`ConfigureDdrive`:** The existing `MoveLibrary` helper already guards with `Test-Path` — already idempotent.

**Win11 tweaks:** Registry `reg add` and `New-Item -Force` calls are idempotent. `winget uninstall` is safe to run when the package is absent (exits non-zero but script continues). Christitus tweaks script is re-runnable.

## Visual Feedback

Every concern block and package install emits progress output so the user can see what is happening:

- `Write-Host` banner before each concern block: e.g. `"--- [Core Apps] ---"`
- `Install-ChocoPackage` prints one line per package indicating whether it is installing or already installed:
  - `"  [SKIP] notepadplusplus.install (already installed)"`
  - `"  [INSTALL] googlechrome"`
- IIS features loop emits per-feature status in the same style
- `Get-Concerns` prints a summary table of selected concerns before proceeding

## Visual Studio

Updated from `visualstudio2022community` to `visualstudio2026community`.
