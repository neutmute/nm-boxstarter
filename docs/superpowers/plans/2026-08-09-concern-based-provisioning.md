# Concern-Based Provisioning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace env-var install profiles in `base-box.ps1` with an interactive, persisted concern system; make the script idempotent and re-runnable with visual feedback; remove Windows 10 dead code.

**Architecture:** A single self-contained `base-box.ps1` prompts the user for each concern at runtime, persists answers to `neutmute-boxstarter.json` in Documents, and gates each install block on the chosen concerns. A version-agnostic idempotency check (Chocolatey `lib` folder) skips already-installed packages. Windows 11 cleanup is absorbed inline.

**Tech Stack:** PowerShell 5.1, Boxstarter, Chocolatey, winget.

## Global Constraints

- Config file path: `[Environment]::GetFolderPath('MyDocuments')\neutmute-boxstarter.json` (exact filename `neutmute-boxstarter.json`).
- Prompt default is **N** (Enter = No); user types `y`/`yes` to opt in. Saved value is shown as a hint only, it does NOT change the default.
- Idempotency check must be Chocolatey-version-agnostic — check for `$ChocolateyInstall\lib\<package>` directory, NOT `choco list --local-only` (removed in choco 2.x).
- Visual Studio package id: `visualstudio2026community`.
- Script must remain a single self-contained file runnable by URL via `Install-BoxstarterPackage`.
- Verification for every task that touches a `.ps1` file: AST parse check must report no errors (see verification command in Task 1 Step 3).

---

### Task 1: Rewrite `base-box.ps1` with concern system

**Files:**
- Modify (full rewrite): `C:\CodeMine\nm-boxstarter\base-box.ps1`

**Interfaces:**
- Consumes: Boxstarter cmdlets (`Set-WindowsExplorerOptions`, `Enable-RemoteDesktop`, `Disable-BingSearch`, `Disable-GameBarTips`, `Move-LibraryDirectory`, `Write-BoxstarterMessage`, `Invoke-Reboot`, `Test-PendingReboot`, `Enable-MicrosoftUpdate`, `Install-WindowsUpdate`, `Set-BoxstarterTaskbarOptions`, `Set-CornerNavigationOptions`, `Update-ExecutionPolicy`), `choco`, `winget`, `tzutil`.
- Produces: `Get-Concerns` → `[hashtable]` keyed by concern (`core`, `baseSettings`, `regionalSettings`, `ddrive`, `home`, `htpc`, `dev`, `iis`, `visualStudio`) with `[bool]` values; `Test-ChocoInstalled([string]) → [bool]`; `Install-ChocoPackage([string])`; `Install-ChocoPackages([array])`.

- [ ] **Step 1: Replace the entire contents of `base-box.ps1` with the following**

```powershell
<#
#OPTIONAL

    Run via Boxstarter:

    Set-ExecutionPolicy Unrestricted
    . { iwr -useb http://boxstarter.org/bootstrapper.ps1 } | iex; get-boxstarter -Force
    $cred=Get-Credential
    Install-BoxstarterPackage -PackageName https://raw.githubusercontent.com/neutmute/nm-boxstarter/master/base-box.ps1 -Credential $cred

    Install profiles ("concerns") are chosen interactively at runtime and
    persisted to neutmute-boxstarter.json in the user's Documents folder.
    The script is idempotent and safe to run multiple times.
#>
Import-Module Boxstarter.Chocolatey

# ---------------------------------------------------------------------------
# Concern configuration
# ---------------------------------------------------------------------------

$script:ConfigPath = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'neutmute-boxstarter.json'

$script:ConcernDefinitions = @(
    @{ Key = 'core';             Prompt = 'Install Core apps' },
    @{ Key = 'baseSettings';     Prompt = 'Configure base Windows settings' },
    @{ Key = 'regionalSettings'; Prompt = 'Apply regional settings (Australia)' },
    @{ Key = 'ddrive';           Prompt = 'Configure D: drive and relocate folders' },
    @{ Key = 'home';             Prompt = 'Install Home apps' },
    @{ Key = 'htpc';             Prompt = 'Install HTPC apps' },
    @{ Key = 'dev';              Prompt = 'Install Dev apps' },
    @{ Key = 'iis';              Prompt = 'Install IIS' },
    @{ Key = 'visualStudio';     Prompt = 'Install Visual Studio 2026 Community' }
)

# ---------------------------------------------------------------------------
# Application lists
# ---------------------------------------------------------------------------

$userSettingsApps = @(
    'taskbar-never-combine',
    'explorer-show-all-folders',
    'explorer-expand-to-current-folder'
)

$coreApps = @(
    'chocolatey',
    'bitwarden',
    'firefox',
    'googlechrome',
    'notepadplusplus.install',
    'paint.net',
    'irfanview',
    'irfanviewplugins',
    'fscapture',
    '7zip.install',
    'shutup10',                  # Windows privacy. Execute with OOSU10.exe
    'veracrypt',
    'powershellhere',
    'powershellhere-elevated',
    'windirstat',
    'wakemeonlan'
)

$homeApps = @(
    'syncbackfree',
    'spotify',
    'joplin',
    'calibre',
    'winamp',
    'audacity',
    'alldup',                    # find and remove duplicate files
    'beebeep',
    'sendtokindle',
    'signal'
)

$htpcApps = @(
    'steam',
    'syncbackfree',
    'kodi'
)

$Boxstarter.RebootOk = $true
$Boxstarter.NoPassword = $false
$Boxstarter.AutoLogin = $true

# ---------------------------------------------------------------------------
# Concern prompting / persistence
# ---------------------------------------------------------------------------

function Get-SavedConcerns()
{
    if (Test-Path $script:ConfigPath) {
        try {
            $json = Get-Content -Path $script:ConfigPath -Raw | ConvertFrom-Json
            return $json.concerns
        } catch {
            Write-Warning "Could not parse $script:ConfigPath, ignoring: $_"
        }
    }
    return $null
}

function Save-Concerns($concerns)
{
    $wrapper = [PSCustomObject]@{ concerns = [PSCustomObject]$concerns }
    $wrapper | ConvertTo-Json | Set-Content -Path $script:ConfigPath -Encoding UTF8
    Write-Host "Saved config to $script:ConfigPath"
}

function Get-Concerns()
{
    $saved = Get-SavedConcerns
    $concerns = @{}

    foreach ($def in $script:ConcernDefinitions) {
        $key = $def.Key

        $savedHint = ''
        if ($saved -and ($saved.PSObject.Properties.Name -contains $key)) {
            $savedText = if ([bool]$saved.$key) { 'Yes' } else { 'No' }
            $savedHint = " (saved: $savedText)"
        }

        $answer = Read-Host "$($def.Prompt)?$savedHint [y/N]"
        $concerns[$key] = ($answer -match '^(y|yes)$')
    }

    Save-Concerns $concerns

    Write-Host ""
    Write-Host "--- Selected concerns ---"
    foreach ($def in $script:ConcernDefinitions) {
        $mark = if ($concerns[$def.Key]) { '[X]' } else { '[ ]' }
        Write-Host ("  {0} {1}" -f $mark, $def.Key)
    }
    Write-Host ""

    return $concerns
}

# ---------------------------------------------------------------------------
# Idempotent Chocolatey install helpers
# ---------------------------------------------------------------------------

function Test-ChocoInstalled($packageName)
{
    $chocoInstall = if ($env:ChocolateyInstall) { $env:ChocolateyInstall } else { 'C:\ProgramData\chocolatey' }
    return Test-Path (Join-Path $chocoInstall (Join-Path 'lib' $packageName))
}

function Install-ChocoPackage($packageName)
{
    if (Test-ChocoInstalled $packageName) {
        Write-Host "  [SKIP] $packageName (already installed)"
        return
    }
    Write-Host "  [INSTALL] $packageName"
    choco install $packageName --limitoutput
}

function Install-ChocoPackages($packageArray)
{
    foreach ($package in $packageArray) {
        Install-ChocoPackage $package
    }
}

# ---------------------------------------------------------------------------
# Configuration functions
# ---------------------------------------------------------------------------

function ConfigureBaseSettings()
{
    Write-Host "--- [Base Settings] ---"
    Update-ExecutionPolicy -Policy Unrestricted

    Set-Volume -DriveLetter $env:SystemDrive[0] -NewFileSystemLabel "System"
    Set-CornerNavigationOptions -EnableUsePowerShellOnWinX
    Set-WindowsExplorerOptions -EnableShowHiddenFilesFoldersDrives -DisableShowProtectedOSFiles -EnableShowFileExtensions -EnableShowFullPathInTitleBar
    Set-BoxstarterTaskbarOptions -Combine Never
    Disable-BingSearch

    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device" -Name "DevicePasswordLessBuildVersion" -Value 0 # Run 'netplz' to then allow automatic logon

    Start-Process 'powercfg.exe' -Verb runAs -ArgumentList '/h off'     # Disable hibernate
}

function MoveLibrary {
    param(
        $libraryName,
        $newPath
    )

    if (-not (Test-Path $newPath)) {  # idempotent
        Move-LibraryDirectory -libraryName $libraryName -newPath $newPath
    }
}

function SetRegionalSettings()
{
    Write-Host "--- [Regional Settings] ---"
    # http://stackoverflow.com/questions/4235243/how-to-set-timezone-using-powershell
    &"$env:windir\system32\tzutil.exe" /s "AUS Eastern Standard Time"

    Set-ItemProperty -Path "HKCU:\Control Panel\International" -Name sShortDate     -Value dd-MMM-yy
    Set-ItemProperty -Path "HKCU:\Control Panel\International" -Name sCountry       -Value Australia
    Set-ItemProperty -Path "HKCU:\Control Panel\International" -Name sShortTime     -Value HH:mm
    Set-ItemProperty -Path "HKCU:\Control Panel\International" -Name sTimeFormat    -Value HH:mm:ss
    Set-ItemProperty -Path "HKCU:\Control Panel\International" -Name sLanguage      -Value ENA
}

function InstallWindowsUpdate()
{
    Write-BoxstarterMessage "Windows update..."

    Enable-MicrosoftUpdate
    Install-WindowsUpdate -AcceptEula
    if (Test-PendingReboot) { Invoke-Reboot }
}

function InstallGraphicsDrivers()
{
    $nvidiaGpu = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -like '*NVIDIA*' }
    if ($nvidiaGpu) {
        Write-BoxstarterMessage "NVIDIA GPU detected ($($nvidiaGpu.Name)), installing display driver..."
        Install-ChocoPackage 'nvidia-display-driver'
    }
    else {
        Write-BoxstarterMessage "NVIDIA GPU not found, not installing drivers"
    }
}

function InstallChocoDevApps()
{
    Write-Host "--- [Dev Apps] ---"

    $devApps = @(
        'autohotkey',
        'checksum',
        'diffmerge',
        'gitextensions',
        'sqlitebrowser',
        'nmap',
        'nuget.commandline',
        'openssl',
        'putty',
        'rdcman',                       # remote desktop connection manager
        'slack',
        'sql-server-management-studio',
        'vscode',
        'vswhere',
        'winscp',
        'wintail'
    )

    if (Test-ChocoInstalled 'git.install') {
        Write-Host "  [SKIP] git.install (already installed)"
    } else {
        Write-Host "  [INSTALL] git.install"
        choco install git.install --params "'/GitAndUnixToolsOnPath /WindowsTerminal'" --limitoutput
    }

    Install-ChocoPackages $devApps

    if (Test-ChocoInstalled 'sourcetree') {
        Write-Host "  [SKIP] sourcetree (already installed)"
    } else {
        Write-Host "  [INSTALL] sourcetree"
        choco install sourcetree --limitoutput   # do last since not silent
    }

    # AWS PowerShell tools
    Install-Module -Name AWS.Tools.Common -Force
    Install-Module -Name AWS.Tools.EC2 -Force
}

function InstallVisualStudio()
{
    Write-Host "--- [Visual Studio] ---"
    if (Test-ChocoInstalled 'visualstudio2026community') {
        Write-Host "  [SKIP] visualstudio2026community (already installed)"
        return
    }
    Write-Host "  [INSTALL] visualstudio2026community"
    choco install visualstudio2026community --package-parameters "--allWorkloads --includeRecommended --passive --locale en-US"
}

function InstallInternetInformationServices()
{
    Write-Host "--- [IIS] ---"
    $windowsFeatures = @(
        'Windows-Identity-Foundation',
        'Microsoft-Windows-Subsystem-Linux',
        'IIS-WebServerRole',
        'IIS-WebServer',
        'IIS-CommonHttpFeatures',
        'IIS-HttpErrors',
        'IIS-HttpRedirect',
        'IIS-ApplicationDevelopment',
        'IIS-NetFxExtensibility45',
        'IIS-HealthAndDiagnostics',
        'IIS-HttpLogging',
        'IIS-LoggingLibraries',
        'IIS-RequestMonitor',
        'IIS-HttpTracing',
        'IIS-Security',
        'IIS-URLAuthorization',
        'IIS-RequestFiltering',
        'IIS-Performance',
        'IIS-HttpCompressionDynamic',
        'IIS-WebServerManagementTools',
        'IIS-ManagementScriptingTools',
        'IIS-HostableWebCore',
        'IIS-StaticContent',
        'IIS-DefaultDocument',
        'IIS-WebSockets',
        'IIS-ASPNET',
        'IIS-ServerSideIncludes',
        'IIS-CustomLogging',
        'IIS-BasicAuthentication',
        'IIS-HttpCompressionStatic',
        'IIS-ManagementConsole',
        'IIS-ManagementService',
        'IIS-WMICompatibility',
        'IIS-CertProvider',
        'IIS-WindowsAuthentication',
        'IIS-DigestAuthentication'
    )

    foreach ($feature in $windowsFeatures) {
        Write-Host "  [FEATURE] $feature"
        &choco install $feature --source windowsfeatures --limitoutput
    }

    Install-ChocoPackage 'urlrewrite'   # Used for WASM / Blazor apps
}

function DownloadConfigFiles()
{
    Write-Host 'Configuring Notepad++'
    $notepadShortcutConfigRemote = 'https://raw.githubusercontent.com/neutmute/nm-boxstarter/master/files/notepad%2B%2B/shortcuts.xml'
    $notepadShortcutConfigLocal = "$($env:AppData)\Notepad++\shortcuts.xml"
    Invoke-WebRequest -Uri $notepadShortcutConfigRemote -OutFile $notepadShortcutConfigLocal
}

function CleanDesktopShortcuts()
{
    Write-Host "Cleaning desktop of shortcuts"
    $allUsersDesktop = "C:\Users\Public\Desktop"
    Get-ChildItem -Path $allUsersDesktop\*.lnk -Exclude *BoxStarter* | Remove-Item
}

function ConfigureDdrive()
{
    Write-BoxstarterMessage "Configuring D:\"

    Set-Volume -DriveLetter "D" -NewFileSystemLabel "Data"

    $userDataPath = "D:\Data\Documents"
    $mediaPath = "D:\Media"

    MoveLibrary -libraryName "My Pictures" -newPath (Join-Path $userDataPath "Pictures")
    MoveLibrary -libraryName "Personal"    -newPath (Join-Path $userDataPath "Documents")
    MoveLibrary -libraryName "Desktop"     -newPath (Join-Path $userDataPath "Desktop")
    MoveLibrary -libraryName "My Video"    -newPath (Join-Path $mediaPath "Videos")
    MoveLibrary -libraryName "My Music"    -newPath (Join-Path $mediaPath "Music")
    MoveLibrary -libraryName "Downloads"   -newPath "D:\Downloads"
}

function Invoke-Win11Tweaks()
{
    Write-Host "--- [Windows 11 Tweaks] ---"

    # Restore classic right-click context menu ("Show more options" always)
    reg add "HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" /ve /d "" /f

    # Remove "Edit in Notepad" context menu entry
    # https://www.elevenforum.com/t/add-or-remove-edit-in-notepad-context-menu-in-windows-11.20485/
    New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked" -Force | Out-Null
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked" -Name "{CA6CC9F1-867A-481E-951E-A28C5E4F01EA}" -Value "" -Type String

    # Remove OneDrive
    winget uninstall Microsoft.OneDrive --accept-source-agreements

    # Chris Titus Tech Windows Utility tweaks
    iwr -useb https://christitus.com/win | iex
}

# ===========================================================================
# Main
# ===========================================================================

$concerns = Get-Concerns

if ($concerns['regionalSettings']) { SetRegionalSettings }

# Windows update early ensures prerequisites are met
InstallWindowsUpdate

InstallGraphicsDrivers

# disable chocolatey default confirmation behaviour (no need for --yes)
choco feature enable --name=allowGlobalConfirmation

if ($concerns['baseSettings']) { ConfigureBaseSettings }

Write-BoxstarterMessage "Starting chocolatey installs"

Write-Host "--- [User Settings] ---"
Install-ChocoPackages $userSettingsApps

if ($concerns['core']) {
    Write-Host "--- [Core Apps] ---"
    Install-ChocoPackages $coreApps
}

if ($concerns['ddrive']) { ConfigureDdrive }

if ($concerns['home']) {
    Write-Host "--- [Home Apps] ---"
    Enable-RemoteDesktop
    Disable-BingSearch
    Disable-GameBarTips
    Install-ChocoPackages $homeApps
}

if ($concerns['htpc']) {
    Write-Host "--- [HTPC Apps] ---"
    Install-ChocoPackages $htpcApps
}

# Put dev-heavy installs later as the big ones tend to fail and kill Boxstarter
if ($concerns['dev']) {
    Write-BoxstarterMessage "Installing Dev Apps"
    InstallChocoDevApps
}

if ($concerns['iis']) { InstallInternetInformationServices }

if ($concerns['visualStudio']) { InstallVisualStudio }

CleanDesktopShortcuts

DownloadConfigFiles

Invoke-Win11Tweaks

Write-Host "Provisioning complete."
```

- [ ] **Step 2: Verify no forbidden legacy references remain**

Run (from repo root):
```bash
grep -nE "win10-clean|BoxStarterInstall|InstallSqlServer|hasDdrive|Start-Process https" base-box.ps1
```
Expected: no output (exit code 1). If any line prints, the rewrite is incomplete.

- [ ] **Step 3: Verify the script parses with no syntax errors**

Run:
```powershell
$errors = $null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\base-box.ps1).Path, [ref]$null, [ref]$errors); if ($errors) { $errors | Format-List; 'PARSE FAILED' } else { 'PARSE OK' }
```
Expected: `PARSE OK`

- [ ] **Step 4: Commit**

```bash
git add base-box.ps1
git commit -m "Replace env-var profiles with interactive concern system"
```

---

### Task 2: Delete `win10-clean.ps1`

**Files:**
- Delete: `C:\CodeMine\nm-boxstarter\win10-clean.ps1`

- [ ] **Step 1: Delete the file**

```bash
git rm win10-clean.ps1
```

- [ ] **Step 2: Verify no references remain in any script**

Run (from repo root):
```bash
grep -rn "win10-clean" --include=*.ps1 .
```
Expected: no output (exit code 1). (References in `docs/` and `CLAUDE.md` are handled in Task 3.)

- [ ] **Step 3: Commit**

```bash
git commit -m "Remove win10-clean.ps1 (Windows 10 specific, obsolete)"
```

---

### Task 3: Update `CLAUDE.md` documentation

**Files:**
- Modify: `C:\CodeMine\nm-boxstarter\CLAUDE.md`

**Interfaces:**
- Consumes: the concern keys and behavior defined in Task 1.

- [ ] **Step 1: Update the `base-box.ps1` bullet in the "Main Scripts" section**

Find:
```markdown
- **base-box.ps1**: Main orchestration script that handles the complete machine setup
  - Entry point for most installations
  - Supports multiple install profiles via environment variables
  - Chains to win10-clean.ps1 via Boxstarter at the end, then opens both win10 and win11 clean scripts in the browser for manual reference
```
Replace with:
```markdown
- **base-box.ps1**: Main orchestration script that handles the complete machine setup
  - Entry point for most installations
  - Interactively prompts for "concerns" (install areas) at runtime and persists answers to `neutmute-boxstarter.json` in the user's Documents folder
  - Idempotent and safe to run multiple times; skips already-installed Chocolatey packages
  - Applies Windows 11 cleanup tweaks inline at the end (classic context menu, remove OneDrive, block "Edit in Notepad", Chris Titus tweaks)
```

- [ ] **Step 2: Remove the `win10-clean.ps1` bullet from the "Main Scripts" section**

Find and delete these two lines:
```markdown
- **win10-clean.ps1**: Boxstarter cleanup script for Windows 10
  - Removes bloatware apps, disables Cortana/telemetry, configures privacy/registry tweaks
```

- [ ] **Step 3: Replace the "Install Profiles" section**

Find:
```markdown
## Install Profiles

base-box.ps1 supports multiple install profiles controlled by environment variables:

- **BoxStarterInstallDev**: Development machine with Visual Studio, SQL Server, IIS, dev tools
- **BoxStarterInstallHome**: Home machine with media apps, utilities
- **BoxStarterInstallHtpc**: HTPC profile with Kodi, Steam, media tools

Set these in both "Machine" and "Process" scopes before running to enable the profile.
```
Replace with:
```markdown
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
```

- [ ] **Step 4: Update the "Key Functions" section to remove SQL Server and fix VS/IIS notes**

Find:
```markdown
- **InstallSqlServer()**: SQL Server installation from ISO (2008/2012/2016) — defined but commented out in main flow
  - Uses custom MyGet package source: https://www.myget.org/F/nm-chocolatey-packs/api/v2
  - Pass ISO path via environment variable: `choco:sqlserver2016:isoImage`
- **InstallVisualStudio()**: VS 2022 Community install — defined but commented out in main flow
- **InstallInternetInformationServices()**: Extensive IIS feature installation
```
Replace with:
```markdown
- **InstallVisualStudio()**: VS 2026 Community install — gated by the `visualStudio` concern
- **InstallInternetInformationServices()**: Extensive IIS feature installation — gated by the `iis` concern
```

- [ ] **Step 5: Update the "Application Organization" section**

Find:
```markdown
- **userSettingsApps**: Windows Explorer/taskbar tweaks (top-level array)
- **coreApps**: Essential utilities for all machines (browsers, Notepad++, 7zip, etc.) (top-level array)
- **homeApps**: Home-specific apps (Spotify, Joplin, Calibre, etc.) (top-level array)
- **htpcApps**: Media center apps (Kodi, Steam) (top-level array)
- **devApps**: Developer tools (Git, VS Code, SSMS, Slack, etc.) — defined *inside* `InstallChocoDevApps()`, not at top level
```
Replace with:
```markdown
- **userSettingsApps**: Windows Explorer/taskbar tweaks (top-level array, always installed)
- **coreApps**: Essential utilities (browsers, Notepad++, 7zip, etc.) (top-level array, `core` concern)
- **homeApps**: Home-specific apps (Spotify, Joplin, Calibre, etc.) (top-level array, `home` concern)
- **htpcApps**: Media center apps (Kodi, Steam) (top-level array, `htpc` concern)
- **devApps**: Developer tools (Git, VS Code, SSMS, Slack, etc.) — defined *inside* `InstallChocoDevApps()`, not at top level (`dev` concern)

All Chocolatey installs go through `Install-ChocoPackage`, which skips packages already present in `$ChocolateyInstall\lib` for idempotency.
```

- [ ] **Step 6: Update the "Testing Changes" list item that references bootstrap/win10**

Find:
```markdown
## Important Notes

- Boxstarter handles automatic reboots during installation
```
Add immediately after the `- Boxstarter handles automatic reboots during installation` line a note (leave existing lines intact):
```markdown
- Install choices ("concerns") are prompted once and persisted to `neutmute-boxstarter.json` in Documents; the script is idempotent across re-runs
```

- [ ] **Step 7: Verify no stale references remain in CLAUDE.md**

Run (from repo root):
```bash
grep -nE "win10-clean|BoxStarterInstall|InstallSqlServer|environment variables|VS 2022" CLAUDE.md
```
Expected: no output (exit code 1).

- [ ] **Step 8: Commit**

```bash
git add CLAUDE.md
git commit -m "Update CLAUDE.md for concern-based provisioning"
```

---

## Self-Review

**Spec coverage:**
- 9 concerns, all user-selectable → `$ConcernDefinitions` + main gating (Task 1). ✓
- Config file path/shape → `Get-SavedConcerns`/`Save-Concerns` (Task 1). ✓
- Prompt flow, default N, saved hint → `Get-Concerns` (Task 1). ✓
- Execution order (spec §Execution Order) → Main block matches order exactly (Task 1). ✓
- Win11 tweaks inline, always runs → `Invoke-Win11Tweaks` called unconditionally (Task 1). ✓
- Idempotency (choco lib check, MoveLibrary Test-Path, winget safe) → `Test-ChocoInstalled` (Task 1). ✓
- Visual feedback (banners, [SKIP]/[INSTALL], IIS per-feature, concern summary) → present (Task 1). ✓
- Removals (win10-clean, InstallSqlServer, boxstarter-call, browser Start-Process, hasDdrive, env vars) → Task 1 rewrite omits all; Task 2 deletes file; Task 1 Step 2 greps to prove. ✓
- VS 2022 → 2026 → `InstallVisualStudio` + package id (Task 1). ✓
- home concern includes Remote Desktop + Game Bar → main block (Task 1). ✓

**Placeholder scan:** No TBD/TODO; all code is complete and literal. ✓

**Type consistency:** `Get-Concerns` returns hashtable keyed by the 9 concern keys; main block reads `$concerns['<key>']` using those exact keys; `Install-ChocoPackages`/`Install-ChocoPackage`/`Test-ChocoInstalled` names consistent across all call sites. ✓
