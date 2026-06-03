# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a Boxstarter-based Windows automated provisioning tool. Boxstarter is a PowerShell framework built on top of Chocolatey that automates Windows machine setup with reboot management.

## Script Architecture

### Main Scripts

- **base-box.ps1**: Main orchestration script that handles the complete machine setup
  - Entry point for most installations
  - Supports multiple install profiles via environment variables
  - Chains to win10-clean.ps1 via Boxstarter at the end, then opens both win10 and win11 clean scripts in the browser for manual reference

- **bootstrap.ps1**: Automated entry point for vagrant/unattended installations
  - Downloads and installs Boxstarter
  - Invokes base-box.ps1 with hardcoded credentials

- **win10-clean.ps1**: Boxstarter cleanup script for Windows 10
  - Removes bloatware apps, disables Cortana/telemetry, configures privacy/registry tweaks

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

## Install Profiles

base-box.ps1 supports multiple install profiles controlled by environment variables:

- **BoxStarterInstallDev**: Development machine with Visual Studio, SQL Server, IIS, dev tools
- **BoxStarterInstallHome**: Home machine with media apps, utilities
- **BoxStarterInstallHtpc**: HTPC profile with Kodi, Steam, media tools

Set these in both "Machine" and "Process" scopes before running to enable the profile.

## Application Organization

Apps are organized into logical arrays in base-box.ps1:

- **userSettingsApps**: Windows Explorer/taskbar tweaks (top-level array)
- **coreApps**: Essential utilities for all machines (browsers, Notepad++, 7zip, etc.) (top-level array)
- **homeApps**: Home-specific apps (Spotify, Joplin, Calibre, etc.) (top-level array)
- **htpcApps**: Media center apps (Kodi, Steam) (top-level array)
- **devApps**: Developer tools (Git, VS Code, SSMS, Slack, etc.) — defined *inside* `InstallChocoDevApps()`, not at top level

## Key Functions in base-box.ps1

- **ConfigureBaseSettings()**: Windows system settings, power options, Explorer options
- **InstallChocoApps($packageArray)**: Generic Chocolatey package installer
- **InstallSqlServer()**: SQL Server installation from ISO (2008/2012/2016) — defined but commented out in main flow
  - Uses custom MyGet package source: https://www.myget.org/F/nm-chocolatey-packs/api/v2
  - Pass ISO path via environment variable: `choco:sqlserver2016:isoImage`
- **InstallVisualStudio()**: VS 2022 Community install — defined but commented out in main flow
- **InstallInternetInformationServices()**: Extensive IIS feature installation
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
- D:\Data\Sql - SQL Server data directory (if installed)

## Important Notes

- Boxstarter handles automatic reboots during installation
- Chocolatey global confirmation is enabled (no need for --yes flag)
- Desktop shortcuts are automatically cleaned up at the end
- Notepad++ configuration is downloaded from this GitHub repo
- The scripts require Administrator/elevated privileges
- Windows Update is run early in the process to ensure SQL Server prerequisites are met
