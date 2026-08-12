# Concern Descriptions, Auto-Logon Split, and Win11 Tweak Fixes

Date: 2026-08-12
Status: Approved

## Problem

Five issues in `base-box.ps1`:

1. Concern prompts show only a short label. The user cannot tell what a concern
   will do to the machine, or which Chocolatey packages it installs, without
   reading the script.
2. Setting `DevicePasswordLessBuildVersion = 0` (which unhides the "users must
   enter a user name and password" checkbox in `netplwiz`, enabling auto-logon)
   is buried inside `ConfigureBaseSettings()`. It cannot be chosen independently.
3. `Invoke-Win11Tweaks` is called unconditionally at the end of Main. There is no
   `win11Tweaks` concern, so the tweaks run regardless of what the user answered.
4. `Invoke-Win11Tweaks` also invokes the Chris Titus utility, which opens an
   interactive GUI and stalls an unattended reboot-resume run.
5. `$userDataPath` in `ConfigureDdrive()` is `D:\Data\Documents`; it should be
   `D:\Data\User`.

## Design

### 1. Concern definitions gain `Description` and `Packages`

`$script:ConcernDefinitions` entries take two new optional keys:

```powershell
@{ Key         = 'core'
   Prompt      = 'Install Core apps'
   Description = 'Browsers, password manager, image tools, archiver, disk utilities.'
   Packages    = $coreApps }
```

- `Description` — prose describing what the concern does to the machine. Present
  on every concern.
- `Packages` — a reference to the live package array. Present only on
  package-installing concerns. Because it references the same array the
  installer iterates, the prompt can never drift from what is actually
  installed.

**Ordering requirement.** The package arrays are currently declared *below*
`$script:ConcernDefinitions`, and `$devApps` is declared *inside*
`InstallChocoDevApps()`. Both must move:

- All package arrays move above `$script:ConcernDefinitions`.
- `$devApps` is lifted to top level. `InstallChocoDevApps()` keeps its
  special-cased `git.install` (custom `--params`) and `sourcetree` (installed
  last, not silent) calls; those two package names are mentioned in the `dev`
  Description prose since they are not members of `$devApps`.

### 2. Prompt rendering

`Get-Concerns` prints, per concern:

```
Install Core apps?
  Browsers, password manager, image tools, archiver, disk utilities.
  Packages: chocolatey, bitwarden, firefox, googlechrome, notepadplusplus.install,
            paint.net, irfanview, irfanviewplugins, fscapture, 7zip.install,
            shutup10, veracrypt, powershellhere, powershellhere-elevated,
            windirstat, wakemeonlan
  [y/N]:
```

A `Write-PackageList` helper word-wraps the comma-separated package names to the
console width, indenting continuation lines under the first package. The
`Packages:` block is omitted entirely for concerns without a `Packages` key.

`Show-ConcernSummary` is unchanged — it keeps the compact `[X] key` form.
Descriptions there would make the summary unreadable.

### 3. New `autoLogon` concern

The `DevicePasswordLessBuildVersion` registry write moves out of
`ConfigureBaseSettings()` into a new function:

```powershell
function Set-AutoLogonPolicy()
{
    Write-Host "--- [Auto Logon] ---"
    Set-ItemProperty `
        -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device" `
        -Name "DevicePasswordLessBuildVersion" -Value 0
}
```

Concern key `autoLogon`, ordered immediately after `baseSettings`. Description
states that it unhides the password checkbox in `netplwiz` and that the user
must still run `netplwiz` to complete auto-logon setup.

### 4. Win11 tweaks split into two concerns

`Invoke-Win11Tweaks()` splits into two functions:

- `Invoke-Win11Tweaks()` — classic right-click context menu, block the
  "Edit in Notepad" shell extension, `winget uninstall Microsoft.OneDrive`.
  Gated by concern `win11Tweaks`.
- `Invoke-ChrisTitusUtility()` — `iwr -useb https://christitus.com/win | iex`.
  Gated by concern `chrisTitus`. Its Description warns that the utility opens an
  interactive GUI and will stall an unattended reboot-resume run.

Both defaults are No, like every other concern.

In Main, the unconditional `Invoke-Win11Tweaks` call becomes:

```powershell
if ($concerns['win11Tweaks']) { Invoke-Win11Tweaks }
if ($concerns['chrisTitus'])  { Invoke-ChrisTitusUtility }
```

This is the fix for issue 3.

### 5. D: drive user data path

In `ConfigureDdrive()`, `$userDataPath` changes from `D:\Data\Documents` to
`D:\Data\User`. `$mediaPath` stays `D:\Media`; Downloads stays `D:\Downloads`.

**Accepted consequence.** `MoveLibrary` is idempotent on the *target* path. On a
machine already relocated to `D:\Data\Documents`, the new target does not exist,
so Documents, Pictures and Desktop are moved a second time into
`D:\Data\User\`. `Move-LibraryDirectory` carries the content across; the empty
`D:\Data\Documents` tree is left behind for the user to delete manually. No
migration logic is built.

## Config file compatibility

Three new keys appear in `neutmute-boxstarter.json`: `autoLogon`, `win11Tweaks`,
`chrisTitus`. `Get-Concerns` already defaults any key missing from a saved
config to `$false`, so existing config files keep loading without error.

Consequence for existing machines re-running the script: they stop receiving the
Win11 tweaks and stop receiving the `DevicePasswordLessBuildVersion` write, until
the config file is deleted and the concerns re-answered. This is the correct
behaviour but is a silent behaviour change on re-run.

## Concern list after this change

| Key | Packages | Notes |
|---|---|---|
| `core` | `$coreApps` | |
| `baseSettings` | — | no longer writes `DevicePasswordLessBuildVersion` |
| `autoLogon` | — | new |
| `regionalSettings` | — | |
| `ddrive` | — | user data now `D:\Data\User` |
| `home` | `$homeApps` | also Remote Desktop, Bing search, Game Bar tips |
| `htpc` | `$htpcApps` | |
| `dev` | `$devApps` | plus `git.install`, `sourcetree` |
| `iis` | — | Windows features + `urlrewrite` |
| `visualStudio` | — | `visualstudio2026community` |
| `win11Tweaks` | — | new; was previously unconditional |
| `chrisTitus` | — | new; interactive, breaks unattended runs |

`$userSettingsApps` remains ungated — it always installs.

## Out of scope

- Migrating content out of an existing `D:\Data\Documents` tree.
- Reworking `Show-ConcernSummary`.
- Any change to `win11-clean.ps1`, `server.ps1`, `ddrive.ps1`, or `bootstrap.ps1`.

`CLAUDE.md` is updated as part of the implementation — its Concerns section, key
functions list, and D: drive conventions all change.

## Testing

Provisioning is destructive; verification is limited to:

1. `Get-Concerns` prompt output rendered on a machine with no config file —
   confirm every concern shows a Description and that package-bearing concerns
   list their full array.
2. Answering No to `win11Tweaks` and confirming the tweak functions do not run.
3. Loading an existing `neutmute-boxstarter.json` and confirming the three new
   keys default to No without a parse error.
4. Full run on a VM snapshot.
