# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a Boxstarter-based Windows automated provisioning tool. Boxstarter is a PowerShell framework built on top of Chocolatey that automates Windows machine setup with reboot management.

## Script Architecture

### Main Scripts

- **base-box.ps1**: Main orchestration script that handles the complete machine setup
  - Entry point for most installations
  - Self-bootstraps Boxstarter via `Install-Boxstarter()` if `Boxstarter.Chocolatey` is not already installed
  - Interactively prompts for "concerns" (install areas) at runtime and persists answers to `neutmute-boxstarter.json` in the user's Documents folder
  - Idempotent and safe to run multiple times; skips already-installed Chocolatey packages
  - Applies Windows 11 cleanup tweaks at the end when the `win11Tweaks` concern is selected

- **bootstrap.ps1**: Thin entry point — clones this repo and stops
  - Installs git via winget if it is missing
  - Clones (or `git pull`s) `https://github.com/neutmute/nm-boxstarter.git` into `nm-boxstarter` under the current directory
  - Prints instructions to run `base-box.ps1`; it does not invoke it

- **server.ps1**: Minimal profile for server installations
  - Fully standalone — self-bootstraps Chocolatey, no Boxstarter required
  - Installs only essential server tools (Chrome, Notepad++, wintail, taskbar tweaks)

- **Set-LockScreen.ps1**: Standalone utility to unpin and set the lock screen image
  - Not wired into `base-box.ps1` or any concern — run it directly
  - Clears the image-pinning values from `HKLM\SOFTWARE\Policies\Microsoft\Windows\Personalization`
    (`LockScreenImage`, `NoChangingLockScreen`, `LockScreenOverlaysDisabled`,
    `NoLockScreenSlideshow`), which is what MDM/Autopilot typically stamps in.
    `NoLockScreenCamera` is deliberately left alone — it is a security control, not cosmetic
  - Backs up all touched keys to timestamped JSON under `%ProgramData%\LockScreenTool\backups`;
    `-Restore` replays the most recent snapshot
  - `-Mode Default|Blank|Spotlight|Image`, `-ImagePath`, `-BlankColor`, `-UnlockOnly`,
    `-Persist`/`-RemovePersist` (logon task, opt-in — only needed if policy is re-pushed)
  - Prefers the per-user WinRT `LockScreen.SetImageFileAsync` API so Settings stays editable;
    falls back to device-wide `PersonalizationCSP` keys, which re-grey the UI
  - Disables Windows Spotlight first, since it overrides any fixed image
  - Self-elevates. Requires Administrator

### Config Files (`files/`)

- **files/notepad++/shortcuts.xml**: Downloaded during setup by `DownloadConfigFiles()` to `%AppData%\Notepad++\`

## Command Line

`base-box.ps1` takes options via a `ValueFromRemainingArguments` param, so each
is accepted in `-x`, `--x` and `/x` form:

- `--list` — list every concern with its description and packages, marking those selected in the saved config, then exit
- `--reset` — delete the saved config so the questions are asked again, then continue with a normal run
- `--help` (also `-h`, `/?`) — show usage and exit
- `base-box.ps1 dev win11Tweaks` — run only the named concerns

Concern names match case-insensitively. Unknown arguments print a warning plus
usage and exit 1. `--help` and `--list` exit before Boxstarter is installed, so
they work on a bare machine.

A **targeted run** (concern names given) sets `$isFullRun = $false`, which skips
the always-on housekeeping — Windows Update, graphics drivers,
`userSettingsApps`, `CleanDesktopShortcuts`, `DownloadConfigFiles` — so only what
was named runs. It also neither reads nor writes the concern selection in the
saved config, though it does read `settings` for values like `hostName`.

Note that `-?` is intercepted by PowerShell itself and never reaches the script;
it renders the comment-based help block at the top of the file instead, which is
why that block duplicates the options list.

## Concerns

On the first run (when no `neutmute-boxstarter.json` exists), base-box.ps1 prompts interactively for each "concern" (install area); the prompt default is No, type `y` to opt in. Answers are saved to `neutmute-boxstarter.json` in the user's Documents folder. On every subsequent run — including Boxstarter reboot-resume cycles — the saved config is applied automatically with no prompting (fully unattended). Delete `neutmute-boxstarter.json` to reconfigure.

Each prompt shows a description of what the concern does, and for concerns that
install Chocolatey packages, the full package list.

**All questions are asked up front.** `Get-Concerns()` runs first and is the
only place in the script that calls `Read-Host`; `Initialize-UnattendedSession()`
then pre-answers everything that would otherwise prompt mid-run (choco global
confirmation, the NuGet provider bootstrap, PSGallery trust, winget source
agreements, `$ConfirmPreference`). Nothing after that point may prompt — new
questions belong in `Get-Concerns()` (as a concern or a `ValueKey`), and new
non-interactive flags belong in `Initialize-UnattendedSession()`.

Two steps still open a GUI because their installers cannot be silenced
(`chrisTitus`, and `sourcetree` within `dev`). These cannot be front-loaded, so
`Show-InteractiveWarning()` names them before any work starts, and
`Invoke-ChrisTitusUtility()` is ordered dead last.

A concern definition may carry `ValueKey`/`ValuePrompt`. When such a concern is
selected, the prompt asks for that value and stores it in a `settings` block in
`neutmute-boxstarter.json` (alongside `concerns`), so later runs stay
unattended. `renameHost` is the only user of this today (`hostName`).

Available concerns:

- **core**: Essential utilities for all machines (browsers, Notepad++, 7zip, etc.)
- **baseSettings**: Windows Explorer/taskbar tweaks, power options, execution policy
- **autoLogon**: Unhides the netplwiz password checkbox so automatic logon can be configured
- **regionalSettings**: Australian timezone and date/time formats
- **ddrive**: D: drive setup and Windows known-folder relocation
- **home**: Home-specific apps (Spotify, Joplin, Calibre, etc.) plus Remote Desktop
- **htpc**: Media center apps (Kodi, Steam)
- **dev**: Developer tools (Git, VS Code, SSMS, Slack, etc.)
- **iis**: IIS Windows features and URL Rewrite (independent of dev)
- **visualStudio**: Visual Studio 2026 Community
- **renameHost**: Renames the computer; prompts once for the name and saves it, no reboot triggered
- **win11Tweaks**: Classic context menu, block "Edit in Notepad", remove OneDrive
- **chrisTitus**: Chris Titus Tech Windows Utility (interactive GUI, blocks unattended runs)

## Application Organization

Apps are organized into logical arrays in base-box.ps1:

- **userSettingsApps**: Windows Explorer/taskbar tweaks (top-level array, always installed)
- **coreApps**: Essential utilities (browsers, Notepad++, 7zip, etc.) (top-level array, `core` concern)
- **homeApps**: Home-specific apps (Spotify, Joplin, Calibre, etc.) (top-level array, `home` concern)
- **htpcApps**: Media center apps (Kodi, Steam) (top-level array, `htpc` concern)
- **devApps**: Developer tools (Git, VS Code, SSMS, Slack, etc.) (top-level array, `dev` concern)

All Chocolatey installs go through `Install-ChocoPackage`, which skips packages already present in `$ChocolateyInstall\lib` for idempotency.

## Key Functions in base-box.ps1

- **Install-Boxstarter()**: Installs Boxstarter from boxstarter.org if the `Boxstarter.Chocolatey` module is not already available
- **Get-CommandLineOptions($arguments)**: Parses `-x`/`--x`/`/x` switches and concern names into a `@{ Help; List; Reset; Targets; Unknown }` hashtable
- **Show-Usage() / Show-ConcernList()**: `--help` and `--list` output; both run before Boxstarter is installed
- **Reset-SavedConfig()**: Deletes `neutmute-boxstarter.json` for `--reset`
- **Get-TargetedConcerns($targets)**: Builds a concern hashtable with only the named concerns enabled, prompting up front for any missing `ValueKey` value
- **Initialize-UnattendedSession()**: Preflight that pre-answers every mid-run prompt source (choco `allowGlobalConfirmation`, NuGet provider bootstrap, PSGallery trust, winget source agreements, `$ConfirmPreference`)
- **Show-InteractiveWarning($concerns)**: Names the selected concerns that still open a GUI, before any work starts
- **Get-Concerns()**: Prompts for each concern, persists/loads `neutmute-boxstarter.json`, populates `$script:Settings`, returns the concern hashtable
- **Rename-Host()**: Renames the computer to `$script:Settings['hostName']` without `-Restart`, so the change lands at the next reboot — gated by the `renameHost` concern and run last so a pending rename cannot land mid Boxstarter reboot cycle
- **ConfigureBaseSettings()**: Windows system settings, power options, Explorer options
- **Install-ChocoPackage($packageName) / Install-ChocoPackages($packageArray)**: Idempotent Chocolatey installer; skips packages already present in `$ChocolateyInstall\lib`
- **InstallVisualStudio()**: VS 2026 Community install — gated by the `visualStudio` concern
- **InstallInternetInformationServices()**: Extensive IIS feature installation — gated by the `iis` concern
- **ConfigureDdrive()**: D: drive setup and Windows folder relocation
- **SetRegionalSettings()**: Hardcoded to Australia timezone and date formats
- **Write-Wrapped($text, $firstPrefix, $contPrefix)**: Word-wraps prompt descriptions and package lists to the console width
- **Set-AutoLogonPolicy()**: Sets `DevicePasswordLessBuildVersion` — gated by the `autoLogon` concern
- **Invoke-Win11Tweaks() / Invoke-ChrisTitusUtility()**: Windows 11 tweaks and the Chris Titus utility — gated by the `win11Tweaks` and `chrisTitus` concerns respectively

## Testing Changes

Since this is a provisioning tool, testing locally is destructive. Recommended approaches:

1. Use a VM snapshot before testing
2. Test individual functions in isolation
3. Use a VM: run bootstrap.ps1 to clone, then base-box.ps1
4. Review changes carefully before running as scripts modify registry and install software

## Regional Settings

The tool hardcodes Australian settings:
- Timezone: "AUS Eastern Standard Time"
- Date format: dd-MMM-yy
- Time format: HH:mm:ss

Modify `SetRegionalSettings()` function if different locale is needed.

## D: Drive Conventions

When D: drive exists and is not a CD-ROM:
- D:\Data\User\ - User documents, pictures, desktop
- D:\Media\ - Videos and music
- D:\Downloads - Downloads folder

## Important Notes

- Boxstarter handles automatic reboots during installation
- Install choices ("concerns") are prompted on the first run and persisted to `neutmute-boxstarter.json` in Documents; subsequent runs (including Boxstarter reboot-resume) apply the saved config unattended with no prompts. Delete the file to reconfigure. The script is idempotent across re-runs.
- Chocolatey global confirmation is enabled (no need for --yes flag)
- Desktop shortcuts are automatically cleaned up at the end
- Notepad++ configuration is downloaded from this GitHub repo
- The scripts require Administrator/elevated privileges
- Windows Update is run early in the process to ensure prerequisites are met
