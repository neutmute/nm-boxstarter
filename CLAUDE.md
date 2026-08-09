# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a Boxstarter-based Windows automated provisioning tool. Boxstarter is a PowerShell framework built on top of Chocolatey that automates Windows machine setup with reboot management.

## Script Architecture

### Main Scripts

- **base-box.ps1**: Main orchestration script that handles the complete machine setup
  - Entry point for most installations
  - Interactively prompts for "concerns" (install areas) at runtime and persists answers to `neutmute-boxstarter.json` in the user's Documents folder
  - Idempotent and safe to run multiple times; skips already-installed Chocolatey packages
  - Applies Windows 11 cleanup tweaks inline at the end (classic context menu, remove OneDrive, block "Edit in Notepad", Chris Titus tweaks)

- **bootstrap.ps1**: Automated entry point for vagrant/unattended installations
  - Downloads and installs Boxstarter
  - Invokes base-box.ps1 with hardcoded credentials

- **win11-clean.ps1**: Raw PowerShell cleanup for Windows 11 (no Boxstarter dependency)
  - Uses `reg`, `winget`, and direct registry edits; runs Christitus tweaks via `iwr`
  - Restores classic right-click menu, removes OneDrive, blocks "Edit in Notepad" context entry

- **server.ps1**: Minimal profile for server installations
  - Fully standalone — self-bootstraps Chocolatey, no Boxstarter required
  - Installs only essential server tools (Chrome, Notepad++, wintail, taskbar tweaks)

- **ddrive.ps1**: Standalone D: drive configuration
  - Alternative to the D: drive logic in base-box.ps1
  - Uses Set-KnownFolderPath.ps1 to relocate Windows folders

### Utility Functions

- **Set-KnownFolderPath.ps1**: Reusable function for relocating Windows known folders
  - Uses Win32 SHSetKnownFolderPath API via P/Invoke
  - Supports all standard Windows known folders (Documents, Downloads, Desktop, etc.)

### Config Files (`files/`)

- **files/notepad++/shortcuts.xml**: Downloaded during setup by `DownloadConfigFiles()` to `%AppData%\Notepad++\`
- **files/documents/WindowsPowerShell/Microsoft.PowerShell_profile.ps1**: PowerShell profile

## Concerns

base-box.ps1 prompts interactively for each "concern" (install area) at runtime. Answers are saved to `neutmute-boxstarter.json` in the user's Documents folder and shown as hints on subsequent runs. The prompt default is No; type `y` to opt in.

Available concerns:

- **core**: Essential utilities for all machines (browsers, Notepad++, 7zip, etc.)
- **baseSettings**: Windows Explorer/taskbar tweaks, power options, execution policy
- **regionalSettings**: Australian timezone and date/time formats
- **ddrive**: D: drive setup and Windows known-folder relocation
- **home**: Home-specific apps (Spotify, Joplin, Calibre, etc.) plus Remote Desktop
- **htpc**: Media center apps (Kodi, Steam)
- **dev**: Developer tools (Git, VS Code, SSMS, Slack, etc.)
- **iis**: IIS Windows features and URL Rewrite (independent of dev)
- **visualStudio**: Visual Studio 2026 Community

## Application Organization

Apps are organized into logical arrays in base-box.ps1:

- **userSettingsApps**: Windows Explorer/taskbar tweaks (top-level array, always installed)
- **coreApps**: Essential utilities (browsers, Notepad++, 7zip, etc.) (top-level array, `core` concern)
- **homeApps**: Home-specific apps (Spotify, Joplin, Calibre, etc.) (top-level array, `home` concern)
- **htpcApps**: Media center apps (Kodi, Steam) (top-level array, `htpc` concern)
- **devApps**: Developer tools (Git, VS Code, SSMS, Slack, etc.) — defined *inside* `InstallChocoDevApps()`, not at top level (`dev` concern)

All Chocolatey installs go through `Install-ChocoPackage`, which skips packages already present in `$ChocolateyInstall\lib` for idempotency.

## Key Functions in base-box.ps1

- **Get-Concerns()**: Prompts for each concern, persists/loads `neutmute-boxstarter.json`, returns the concern hashtable
- **ConfigureBaseSettings()**: Windows system settings, power options, Explorer options
- **Install-ChocoPackage($packageName) / Install-ChocoPackages($packageArray)**: Idempotent Chocolatey installer; skips packages already present in `$ChocolateyInstall\lib`
- **InstallVisualStudio()**: VS 2026 Community install — gated by the `visualStudio` concern
- **InstallInternetInformationServices()**: Extensive IIS feature installation — gated by the `iis` concern
- **ConfigureDdrive()**: D: drive setup and Windows folder relocation
- **SetRegionalSettings()**: Hardcoded to Australia timezone and date formats

## Testing Changes

Since this is a provisioning tool, testing locally is destructive. Recommended approaches:

1. Use a VM snapshot before testing
2. Test individual functions in isolation
3. Use Vagrant with bootstrap.ps1 for automated testing
4. Review changes carefully before running as scripts modify registry and install software

## Regional Settings

The tool hardcodes Australian settings:
- Timezone: "AUS Eastern Standard Time"
- Date format: dd-MMM-yy
- Time format: HH:mm:ss

Modify `SetRegionalSettings()` function if different locale is needed.

## D: Drive Conventions

When D: drive exists and is not a CD-ROM:
- D:\Data\Documents\ - User documents, pictures, desktop
- D:\Media\ - Videos and music
- D:\Downloads - Downloads folder

## Important Notes

- Boxstarter handles automatic reboots during installation
- Install choices ("concerns") are prompted once and persisted to `neutmute-boxstarter.json` in Documents; the script is idempotent across re-runs
- Chocolatey global confirmation is enabled (no need for --yes flag)
- Desktop shortcuts are automatically cleaned up at the end
- Notepad++ configuration is downloaded from this GitHub repo
- The scripts require Administrator/elevated privileges
- Windows Update is run early in the process to ensure prerequisites are met
