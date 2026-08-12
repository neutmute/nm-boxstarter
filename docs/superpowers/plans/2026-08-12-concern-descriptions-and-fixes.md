# Concern Descriptions and Win11 Tweak Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a description and the real package list at each concern prompt, split auto-logon and the Windows 11 tweaks into their own concerns, and fix the Win11 tweaks running unconditionally.

**Architecture:** All changes are in the single script `base-box.ps1`, plus a `CLAUDE.md` documentation update. The package arrays move above `$script:ConcernDefinitions` so each concern definition can hold a live reference to its own array; the prompt renders from that reference so the displayed list can never drift from what installs. Two functions are split out (`Set-AutoLogonPolicy`, `Invoke-ChrisTitusUtility`) and three new concern keys added.

**Tech Stack:** Windows PowerShell 5.1, Boxstarter, Chocolatey.

## Global Constraints

- Target shell is Windows PowerShell 5.1. No `&&`/`||`, no ternary, no null-coalescing, no `-AsHashtable`.
- `base-box.ps1` runs Main at load. It can never be dot-sourced for testing; use the harness in Task 1.
- Concern prompts default to No. An answer is Yes only when it matches `^(y|yes)$`.
- New concern keys must default to `$false` when absent from an existing `neutmute-boxstarter.json`. `Get-Concerns` already does this — do not change that behaviour.
- Do not add migration logic for machines already relocated to `D:\Data\Documents`. Re-moving is accepted.
- Do not modify `win11-clean.ps1`, `server.ps1`, `ddrive.ps1`, or `bootstrap.ps1`.
- Keep the existing file's comment style and the `# ---` section banner style.

## File Structure

- `base-box.ps1` — modified throughout. Sole implementation file.
- `CLAUDE.md` — modified. Concerns list, key functions, D: drive conventions.
- `C:\Users\Ben\AppData\Local\Temp\claude\C--CodeMine-nm-boxstarter\62d56209-19e5-4ea7-8c95-56fbd485f213\scratchpad\Test-ConcernPrompt.ps1` — verification harness. Scratchpad only; **never** commit it.

---

### Task 1: Concern descriptions and package lists at the prompt

**Files:**
- Modify: `base-box.ps1` (lines 21-85 restructured, `Get-Concerns` at 122-155, `$devApps` lifted out of `InstallChocoDevApps` at 253-270)
- Test: `<scratchpad>\Test-ConcernPrompt.ps1` (create)

**Interfaces:**
- Produces: `Write-Wrapped($text, $firstPrefix, $contPrefix)` — writes `$text` to host, word-wrapped to console width, first line prefixed `$firstPrefix` and continuations `$contPrefix`. Both prefixes default to `'  '`.
- Produces: `$script:ConcernDefinitions` entries with keys `Key`, `Prompt`, `Description` (always present), `Packages` (present only on package-installing concerns; holds a reference to the live array).
- Produces: top-level `$devApps`, consumed by `InstallChocoDevApps()` in this task and referenced by the `dev` concern definition.

- [ ] **Step 1: Create the verification harness**

This is the only way to exercise the prompt code without running a provisioning
pass. It syntax-checks the whole script, then loads *only* the region above the
Chocolatey helpers (arrays, concern definitions, concern functions) into an
isolated scope, stubs `Read-Host` to always answer no, and prints the prompts.

Create `<scratchpad>\Test-ConcernPrompt.ps1`:

```powershell
$ErrorActionPreference = 'Stop'
$src = 'C:\CodeMine\nm-boxstarter\base-box.ps1'

# 1. Syntax-check the entire script
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile($src, [ref]$null, [ref]$errors) | Out-Null
if ($errors) {
    $errors | ForEach-Object { Write-Host "PARSE ERROR: $_" }
    exit 1
}
Write-Host "PARSE OK"

# 2. Load only the region above the choco helpers (definitions + concern funcs)
$lines = Get-Content $src
$marker = $lines | Select-String -SimpleMatch 'Idempotent Chocolatey install helpers' | Select-Object -First 1
if (-not $marker) { Write-Host "FAIL: region marker not found"; exit 1 }
$region = $lines[0..($marker.LineNumber - 3)] | Where-Object { $_ -notmatch '^\s*Import-Module' }

$Boxstarter = @{}
Invoke-Expression ($region -join "`n")

# 3. Redirect the config file away from the real Documents folder
$script:ConfigPath = Join-Path $env:TEMP 'nm-boxstarter-test-config.json'
if (Test-Path $script:ConfigPath) { Remove-Item $script:ConfigPath -Force }

# 4. Stub Read-Host so every concern is answered No
function Read-Host { param($Prompt) Write-Host "${Prompt}: n"; return 'n' }

$concerns = Get-Concerns
Remove-Item $script:ConfigPath -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Concern keys: $(($concerns.Keys | Sort-Object) -join ', ')"
$yes = @($concerns.Keys | Where-Object { $concerns[$_] })
Write-Host "Answered yes: $($yes.Count) (expected 0)"
```

- [ ] **Step 2: Run the harness against the unmodified script**

Run: `powershell -NoProfile -File "<scratchpad>\Test-ConcernPrompt.ps1"`

Expected: `PARSE OK`, then nine bare prompts with no descriptions and no package
lists, then `Answered yes: 0`. This is the current behaviour and confirms the
harness works before you change anything.

- [ ] **Step 3: Move the package arrays above the concern definitions**

In `base-box.ps1`, cut the `# Application lists` block (`$userSettingsApps`,
`$coreApps`, `$homeApps`, `$htpcApps`) and paste it *above* the
`# Concern configuration` banner, so it sits directly after
`Import-Module Boxstarter.Chocolatey`.

Then cut the `$devApps = @(...)` array out of `InstallChocoDevApps()` and add it
to that same block, after `$htpcApps`:

```powershell
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
```

`InstallChocoDevApps()` keeps everything else unchanged — the special-cased
`git.install` install with `--params`, the `Install-ChocoPackages $devApps`
call, the trailing `sourcetree` install, and the two `Install-Module` calls.
Only the array declaration leaves the function.

Leave `$script:ConfigPath` where it is, and leave the `$Boxstarter.RebootOk` /
`NoPassword` / `AutoLogin` block where it is.

- [ ] **Step 4: Replace $script:ConcernDefinitions**

```powershell
$script:ConcernDefinitions = @(
    @{ Key         = 'core'
       Prompt      = 'Install Core apps'
       Description = 'Everyday utilities for any machine: browsers, password manager, image viewers and editors, archiver, disk usage and privacy tools.'
       Packages    = $coreApps },

    @{ Key         = 'baseSettings'
       Prompt      = 'Configure base Windows settings'
       Description = 'Explorer and taskbar tweaks (show hidden files and file extensions, full path in title bar, never combine taskbar buttons), PowerShell on the Win+X menu, disables Bing search in Start, labels the system drive "System", sets execution policy to Unrestricted and turns hibernation off.' },

    @{ Key         = 'autoLogon'
       Prompt      = 'Allow automatic logon'
       Description = 'Sets DevicePasswordLessBuildVersion to 0, which unhides the "Users must enter a user name and password to use this computer" checkbox in netplwiz. Run netplwiz afterwards and untick it to finish setting up automatic logon.' },

    @{ Key         = 'regionalSettings'
       Prompt      = 'Apply regional settings (Australia)'
       Description = 'Sets the timezone to AUS Eastern Standard Time, short date to dd-MMM-yy, short time to HH:mm, long time to HH:mm:ss, country to Australia and language to ENA.' },

    @{ Key         = 'ddrive'
       Prompt      = 'Configure D: drive and relocate folders'
       Description = 'Labels D: as "Data" and relocates the Windows known folders: Documents, Pictures and Desktop to D:\Data\User, Videos and Music to D:\Media, Downloads to D:\Downloads.' },

    @{ Key         = 'home'
       Prompt      = 'Install Home apps'
       Description = 'Enables Remote Desktop, disables Bing search and Game Bar tips, then installs backup, music, ebook and messaging apps.'
       Packages    = $homeApps },

    @{ Key         = 'htpc'
       Prompt      = 'Install HTPC apps'
       Description = 'Media centre and lounge room machine apps.'
       Packages    = $htpcApps },

    @{ Key         = 'dev'
       Prompt      = 'Install Dev apps'
       Description = 'Developer toolchain. Also installs git.install (Unix tools on PATH, Windows Terminal integration), sourcetree, and the AWS.Tools.Common and AWS.Tools.EC2 PowerShell modules.'
       Packages    = $devApps },

    @{ Key         = 'iis'
       Prompt      = 'Install IIS'
       Description = 'Enables the IIS Windows features (web server, ASP.NET, WebSockets, logging, management console, Windows/Basic/Digest authentication) plus Windows Identity Foundation and the Linux subsystem, then installs the URL Rewrite module.' },

    @{ Key         = 'visualStudio'
       Prompt      = 'Install Visual Studio 2026 Community'
       Description = 'Installs Visual Studio 2026 Community with all workloads and recommended components. Large download; runs last so a failure does not take the rest of the run with it.' },

    @{ Key         = 'win11Tweaks'
       Prompt      = 'Apply Windows 11 tweaks'
       Description = 'Restores the classic right-click context menu, blocks the "Edit in Notepad" shell extension, and uninstalls OneDrive via winget.' },

    @{ Key         = 'chrisTitus'
       Prompt      = 'Run the Chris Titus Windows Utility'
       Description = 'Runs the Chris Titus Tech Windows Utility from christitus.com/win. WARNING: this opens an interactive GUI and will stall an unattended run, including a Boxstarter reboot-resume.' }
)
```

- [ ] **Step 5: Add the Write-Wrapped helper**

Add directly above `function Get-SavedConcerns()`, under the
`# Concern prompting / persistence` banner:

```powershell
function Write-Wrapped($text, $firstPrefix = '  ', $contPrefix = '  ')
{
    $width = 78
    try {
        if ($Host.UI.RawUI.WindowSize.Width -gt 20) {
            $width = $Host.UI.RawUI.WindowSize.Width - 1
        }
    } catch { }

    $line = $firstPrefix
    $isEmpty = $true

    foreach ($word in ($text -split '\s+' | Where-Object { $_ })) {
        if ($isEmpty) {
            $line = $line + $word
            $isEmpty = $false
        }
        elseif (($line.Length + 1 + $word.Length) -gt $width) {
            Write-Host $line
            $line = $contPrefix + $word
        }
        else {
            $line = $line + ' ' + $word
        }
    }

    if (-not $isEmpty) { Write-Host $line }
}
```

- [ ] **Step 6: Render descriptions and packages in the prompt loop**

In `Get-Concerns`, replace the first-run prompt loop:

```powershell
    # First run (no saved config): prompt interactively, default No.
    $concerns = @{}
    foreach ($def in $script:ConcernDefinitions) {
        Write-Host ""
        Write-Host "$($def.Prompt)?"
        if ($def.Description) { Write-Wrapped $def.Description }
        if ($def.Packages) {
            Write-Wrapped ("Packages: " + ($def.Packages -join ', ')) '  ' '            '
        }
        $answer = Read-Host "  [y/N]"
        $concerns[$def.Key] = ($answer -match '^(y|yes)$')
    }
```

The 12-space continuation prefix aligns wrapped package names under the first
package, because `'  Packages: '` is 12 characters wide.

- [ ] **Step 7: Run the harness and check the output**

Run: `powershell -NoProfile -File "<scratchpad>\Test-ConcernPrompt.ps1"`

Expected:
- `PARSE OK`
- Twelve prompts, in this order: core, baseSettings, autoLogon,
  regionalSettings, ddrive, home, htpc, dev, iis, visualStudio, win11Tweaks,
  chrisTitus.
- Every prompt shows an indented description.
- `core`, `home`, `htpc` and `dev` each show a `Packages:` block; the `core`
  block lists all 16 packages from `chocolatey` through `wakemeonlan`, wrapped
  with continuation lines aligned under `chocolatey`.
- The other eight prompts show no `Packages:` block.
- `Answered yes: 0 (expected 0)`

If any package name is missing or the wrapping is ragged, fix and re-run before
committing.

- [ ] **Step 8: Commit**

```bash
git add base-box.ps1
git commit -m "Show description and package list at each concern prompt"
```

---

### Task 2: Split out autoLogon, win11Tweaks and chrisTitus concerns

**Files:**
- Modify: `base-box.ps1` — `ConfigureBaseSettings()`, `Invoke-Win11Tweaks()`, Main
- Test: `<scratchpad>\Test-ConcernPrompt.ps1` (already exists from Task 1)

**Interfaces:**
- Consumes: concern keys `autoLogon`, `win11Tweaks`, `chrisTitus` from Task 1's `$script:ConcernDefinitions`.
- Produces: `Set-AutoLogonPolicy()`, `Invoke-ChrisTitusUtility()`. `Invoke-Win11Tweaks()` keeps its name but loses the Chris Titus call.

- [ ] **Step 1: Move the passwordless registry write out of ConfigureBaseSettings**

Delete this line from `ConfigureBaseSettings()`:

```powershell
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device" -Name "DevicePasswordLessBuildVersion" -Value 0 # Run 'netplz' to then allow automatic logon
```

Add a new function directly after `ConfigureBaseSettings()`:

```powershell
function Set-AutoLogonPolicy()
{
    Write-Host "--- [Auto Logon] ---"
    # Unhides the "Users must enter a user name and password" checkbox in netplwiz
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device" -Name "DevicePasswordLessBuildVersion" -Value 0
}
```

- [ ] **Step 2: Split the Chris Titus call out of Invoke-Win11Tweaks**

Delete these two lines from the end of `Invoke-Win11Tweaks()`:

```powershell
    # Chris Titus Tech Windows Utility tweaks
    iwr -useb https://christitus.com/win | iex
```

Add a new function directly after `Invoke-Win11Tweaks()`:

```powershell
function Invoke-ChrisTitusUtility()
{
    Write-Host "--- [Chris Titus Windows Utility] ---"
    # Interactive GUI - will block an unattended run
    iwr -useb https://christitus.com/win | iex
}
```

- [ ] **Step 3: Gate the three functions in Main**

In Main, add the auto-logon call directly after the `baseSettings` line:

```powershell
if ($concerns['baseSettings']) { ConfigureBaseSettings }
if ($concerns['autoLogon'])    { Set-AutoLogonPolicy }
```

At the bottom of Main, replace the unconditional call:

```powershell
Invoke-Win11Tweaks
```

with:

```powershell
if ($concerns['win11Tweaks']) { Invoke-Win11Tweaks }
if ($concerns['chrisTitus'])  { Invoke-ChrisTitusUtility }
```

This is the bug fix — the tweaks previously ran no matter what was answered.

- [ ] **Step 4: Verify the gating is real**

Run: `powershell -NoProfile -File "<scratchpad>\Test-ConcernPrompt.ps1"`

Expected: `PARSE OK` and the same twelve prompts as Task 1.

Then confirm by inspection that there is no remaining unconditional call site.
Run: `git diff base-box.ps1` and check that every one of `ConfigureBaseSettings`,
`Set-AutoLogonPolicy`, `Invoke-Win11Tweaks` and `Invoke-ChrisTitusUtility` is
called only from inside an `if ($concerns[...])`.

Cross-check with: `powershell -NoProfile -Command "Select-String -Path C:\CodeMine\nm-boxstarter\base-box.ps1 -Pattern 'Invoke-Win11Tweaks|Invoke-ChrisTitusUtility|Set-AutoLogonPolicy|ConfigureBaseSettings'"`

Expected: exactly two hits per name — one `function` declaration and one
`if ($concerns[...]) { ... }` call.

- [ ] **Step 5: Commit**

```bash
git add base-box.ps1
git commit -m "Gate win11 tweaks and auto logon behind their own concerns"
```

---

### Task 3: D: drive user data path and documentation

**Files:**
- Modify: `base-box.ps1` — `ConfigureDdrive()`
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: nothing from earlier tasks beyond the concern list they produced.

- [ ] **Step 1: Change $userDataPath**

In `ConfigureDdrive()`, change:

```powershell
    $userDataPath = "D:\Data\Documents"
```

to:

```powershell
    $userDataPath = "D:\Data\User"
```

Change nothing else in that function. `$mediaPath` stays `"D:\Media"` and the
Downloads target stays `"D:\Downloads"`.

- [ ] **Step 2: Verify**

Run: `powershell -NoProfile -File "<scratchpad>\Test-ConcernPrompt.ps1"`

Expected: `PARSE OK`. The `ddrive` prompt description already says
`D:\Data\User` from Task 1 — confirm it matches the code you just changed.

- [ ] **Step 3: Update CLAUDE.md**

Six edits:

1. In the **Concerns** section's "Available concerns" list, insert after
   `baseSettings`:
   ```markdown
   - **autoLogon**: Unhides the netplwiz password checkbox so automatic logon can be configured
   ```
   and append at the end of the list:
   ```markdown
   - **win11Tweaks**: Classic context menu, block "Edit in Notepad", remove OneDrive
   - **chrisTitus**: Chris Titus Tech Windows Utility (interactive GUI, blocks unattended runs)
   ```

2. In that same section, add after the paragraph describing the prompt flow:
   ```markdown
   Each prompt shows a description of what the concern does, and for concerns that
   install Chocolatey packages, the full package list.
   ```

3. In **Application Organization**, change the `devApps` bullet — it is now a
   top-level array, not defined inside `InstallChocoDevApps()`:
   ```markdown
   - **devApps**: Developer tools (Git, VS Code, SSMS, Slack, etc.) (top-level array, `dev` concern)
   ```

4. In **Key Functions in base-box.ps1**, add:
   ```markdown
   - **Write-Wrapped($text, $firstPrefix, $contPrefix)**: Word-wraps prompt descriptions and package lists to the console width
   - **Set-AutoLogonPolicy()**: Sets `DevicePasswordLessBuildVersion` — gated by the `autoLogon` concern
   - **Invoke-Win11Tweaks() / Invoke-ChrisTitusUtility()**: Windows 11 tweaks and the Chris Titus utility — gated by the `win11Tweaks` and `chrisTitus` concerns respectively
   ```

5. In **D: Drive Conventions**, change `D:\Data\Documents\ - User documents,
   pictures, desktop` to:
   ```markdown
   - D:\Data\User\ - User documents, pictures, desktop
   ```

6. In **Important Notes**, the bullet stating base-box.ps1 "Applies Windows 11
   cleanup tweaks inline at the end" (in the Main Scripts section) must change —
   they are now gated by the `win11Tweaks` concern. Reword to:
   ```markdown
   - Applies Windows 11 cleanup tweaks at the end when the `win11Tweaks` concern is selected
   ```

- [ ] **Step 4: Check for stale references**

Run: `powershell -NoProfile -Command "Select-String -Path C:\CodeMine\nm-boxstarter\CLAUDE.md -Pattern 'Data.Documents|inline at the end|inside .InstallChocoDevApps'"`

Expected: no matches. If anything is found, it is a stale reference — fix it.

- [ ] **Step 5: Commit**

```bash
git add base-box.ps1 CLAUDE.md
git commit -m "Relocate user data to D:\Data\User and update docs"
```

---

### Task 4: Push

- [ ] **Step 1: Confirm the working tree is clean and the harness was not committed**

Run: `git status --short`
Expected: no output. If `Test-ConcernPrompt.ps1` appears, it was written into
the repo by mistake — delete it, it belongs in the scratchpad.

- [ ] **Step 2: Review the full diff**

Run: `git log --oneline master@{u}..HEAD` then `git diff master@{u}..HEAD`

Expected: three commits, changes confined to `base-box.ps1` and `CLAUDE.md`.

- [ ] **Step 3: Push**

```bash
git push
```
