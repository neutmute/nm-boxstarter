<#
.SYNOPSIS
Provisions a Windows machine with Boxstarter and Chocolatey.

.DESCRIPTION
Run from an elevated PowerShell:

    Set-ExecutionPolicy Unrestricted -Force
    .\base-box.ps1

Boxstarter is installed automatically if it is not already present.

Install areas ("concerns") are chosen interactively on the first run and
persisted to neutmute-boxstarter.json in the user's Documents folder. Every
later run applies that saved config unattended. All questions are asked up
front, so the run never stops to ask once it starts. The script is idempotent
and safe to run multiple times.

Options (all accept -x, --x or /x form):

    --list          List every concern, with the saved selection marked
    --reset         Discard the saved config and ask the questions again
    --help          Show this usage

Naming one or more concerns runs only those, ignoring the saved config:

    .\base-box.ps1 dev win11Tweaks

.EXAMPLE
.\base-box.ps1
Normal run. Prompts on the first run, unattended after that.

.EXAMPLE
.\base-box.ps1 --list
Lists every available concern and which ones are currently selected.

.EXAMPLE
.\base-box.ps1 --reset
Deletes the saved config and asks all the questions again.

.EXAMPLE
.\base-box.ps1 dev
Runs only the dev concern, leaving the saved config untouched.
#>
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $Arguments
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

# ---------------------------------------------------------------------------
# Concern configuration
# ---------------------------------------------------------------------------

$script:ConfigPath = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'neutmute-boxstarter.json'

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

    @{ Key          = 'ddrive'
       Prompt       = 'Configure D: drive and relocate folders'
       Description  = 'Labels D: as "Data" and relocates the Windows known folders: Documents, Pictures and Desktop to D:\Data\User, Videos and Music to D:\Media, Downloads to D:\Downloads.'
       Precondition = { Test-DataDrive }
       SkipNote     = 'this machine has no D: drive' },

    @{ Key         = 'home'
       Prompt      = 'Install Home apps'
       Description = 'Enables Remote Desktop, then installs backup, music, ebook and messaging apps.'
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
       Description = 'Enables the IIS Windows features (web server, ASP.NET, WebSockets, logging, management console, Windows/Basic/Digest authentication) plus Windows Identity Foundation and the Linux subsystem, then installs the URL Rewrite module.'
       DependsOn   = 'dev' },

    @{ Key         = 'visualStudio'
       Prompt      = 'Install Visual Studio 2026 Community'
       Description = 'Installs Visual Studio 2026 Community with all workloads and recommended components. Large download; runs last so a failure does not take the rest of the run with it.'
       DependsOn   = 'dev' },

    @{ Key         = 'renameHost'
       Prompt      = 'Rename this computer'
       Description = 'Renames the computer. You are asked for the new name once and it is saved to the config file. No reboot is triggered - the new name takes effect at the next reboot.'
       ValueKey    = 'hostName'
       ValuePrompt = 'New computer name' },

    @{ Key         = 'win11Tweaks'
       Prompt      = 'Apply Windows 11 tweaks'
       Description = 'Restores the classic right-click context menu, blocks the "Edit in Notepad" shell extension, uninstalls OneDrive via winget, and disables Bing search in Start and Game Bar tips.' },

    @{ Key         = 'chrisTitus'
       Prompt      = 'Run the Chris Titus Windows Utility'
       Description = 'Runs the Chris Titus Tech Windows Utility from christitus.com/win. WARNING: this opens an interactive GUI and will stall an unattended run, including a Boxstarter reboot-resume.' }
)

# ---------------------------------------------------------------------------
# Command line
# ---------------------------------------------------------------------------

function Test-DataDrive()
{
    # A real D: drive, not a CD-ROM (DriveType 5) and not absent
    $drive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='D:'" -ErrorAction SilentlyContinue
    return [bool]($drive -and $drive.DriveType -ne 5)
}

function Install-Boxstarter()
{
    if (Get-Module -ListAvailable -Name Boxstarter.Chocolatey) { return }
    Write-Host "Installing Boxstarter..."
    . { Invoke-WebRequest -useb https://boxstarter.org/bootstrapper.ps1 } | Invoke-Expression
    Get-Boxstarter -Force
}

function Show-Usage()
{
    Write-Host ""
    Write-Host "base-box.ps1 - provisions a Windows machine"
    Write-Host ""
    Write-Host "USAGE"
    Write-Host "  .\base-box.ps1 [options] [concern ...]"
    Write-Host ""
    Write-Host "OPTIONS  (each accepts -x, --x or /x form)"
    Write-Host "  --list      List every concern, marking the ones currently selected"
    Write-Host "  --reset     Discard the saved config and ask the questions again"
    Write-Host "  --help      Show this usage"
    Write-Host ""
    Write-Host "CONCERNS"
    Write-Wrapped ("Naming one or more concerns runs only those and leaves the saved " +
                   "config untouched. Run --list to see the names.") '  ' '  '
    Write-Host ""
    Write-Host "EXAMPLES"
    Write-Host "  .\base-box.ps1                  Normal run (prompts on first run only)"
    Write-Host "  .\base-box.ps1 --list           Show all concerns and what is selected"
    Write-Host "  .\base-box.ps1 --reset          Ask all the questions again"
    Write-Host "  .\base-box.ps1 dev win11Tweaks  Run just those two concerns"
    Write-Host ""
    Write-Host "Config file: $script:ConfigPath"
    Write-Host ""
}

function Show-ConcernList()
{
    $config = Get-SavedConfig
    $saved = if ($config) { $config.concerns } else { $null }

    Write-Host ""
    if ($saved) {
        Write-Host "Concerns ([X] = selected in $script:ConfigPath)"
    } else {
        Write-Host "Concerns (no saved config yet, so nothing is selected)"
    }
    Write-Host ""

    foreach ($def in $script:ConcernDefinitions) {
        $key = $def.Key
        $isSet = $saved -and ($saved.PSObject.Properties.Name -contains $key) -and [bool]$saved.$key
        $mark = if ($isSet) { '[X]' } else { '[ ]' }
        Write-Host ("  {0} {1}" -f $mark, $def.Key)
        if ($def.Description) { Write-Wrapped $def.Description '        ' '        ' }
        if ($def.Packages) {
            Write-Wrapped ("Packages: " + ($def.Packages -join ', ')) '        ' '                  '
        }
        Write-Host ""
    }

    Write-Host "Run a single concern with:  .\base-box.ps1 <name>"
    Write-Host ""
}

function Get-CommandLineOptions($arguments)
{
    $options = @{ Help = $false; List = $false; Reset = $false; Targets = @(); Unknown = @() }
    $validKeys = $script:ConcernDefinitions | ForEach-Object { $_.Key }

    foreach ($argument in $arguments) {
        if (-not $argument) { continue }

        # Accept -x, --x and /x for each switch
        $bare = $argument -replace '^(--|-|/)', ''

        switch -Regex ($bare) {
            '^(help|h|\?)$' { $options.Help = $true; continue }
            '^list$'        { $options.List = $true; continue }
            '^reset$'       { $options.Reset = $true; continue }
            default {
                # Match a concern name case insensitively, but keep the real casing
                $match = $validKeys | Where-Object { $_ -eq $bare } | Select-Object -First 1
                if ($match) { $options.Targets += $match }
                else        { $options.Unknown += $argument }
            }
        }
    }

    return $options
}

function Reset-SavedConfig()
{
    if (Test-Path $script:ConfigPath) {
        Remove-Item -Path $script:ConfigPath -Force
        Write-Host "Removed $script:ConfigPath - the questions will be asked again."
    } else {
        Write-Host "No saved config at $script:ConfigPath - the questions will be asked anyway."
    }
}

function Get-TargetedConcerns($targets)
{
    # Only the named concerns run. The saved config is neither read nor written,
    # so a targeted run cannot quietly change what a normal run would do.
    $concerns = @{}
    foreach ($def in $script:ConcernDefinitions) { $concerns[$def.Key] = $false }

    $script:Settings = @{}
    $config = Get-SavedConfig
    if ($config -and $config.settings) {
        foreach ($property in $config.settings.PSObject.Properties) {
            $script:Settings[$property.Name] = $property.Value
        }
    }

    foreach ($target in $targets) {
        $concerns[$target] = $true

        # A targeted concern still needs its value, so ask now rather than mid-run
        $def = $script:ConcernDefinitions | Where-Object { $_.Key -eq $target } | Select-Object -First 1
        if ($def.ValueKey -and -not $script:Settings[$def.ValueKey]) {
            $value = ''
            while (-not $value) {
                $value = (Read-Host "  $($def.ValuePrompt)").Trim()
            }
            $script:Settings[$def.ValueKey] = $value
        }
    }

    Write-Host ""
    Write-Host ("Targeted run: " + ($targets -join ', '))
    Write-Host "The saved config is not read or changed by this run."
    Write-Host ""
    return $concerns
}

# ---------------------------------------------------------------------------
# Concern prompting / persistence
# ---------------------------------------------------------------------------

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

function Get-SavedConfig()
{
    if (Test-Path $script:ConfigPath) {
        try {
            return Get-Content -Path $script:ConfigPath -Raw | ConvertFrom-Json
        } catch {
            Write-Warning "Could not parse $script:ConfigPath, ignoring: $_"
        }
    }
    return $null
}

function Save-Config($concerns, $settings)
{
    $wrapper = [PSCustomObject]@{
        concerns = [PSCustomObject]$concerns
        settings = [PSCustomObject]$settings
    }
    $wrapper | ConvertTo-Json | Set-Content -Path $script:ConfigPath -Encoding UTF8
    Write-Host "Saved config to $script:ConfigPath"
}

function Initialize-UnattendedSession()
{
    Write-Host "--- [Preflight] ---"

    # Everything here answers a question the rest of the run would otherwise
    # stop and ask interactively. Keep new prompt sources out of the main run.

    # Suppress PowerShell's own confirmation prompts for the rest of the script
    $global:ConfirmPreference = 'None'

    # No --yes needed on any choco install
    choco feature enable --name=allowGlobalConfirmation

    # "NuGet provider is required to continue - install now?" from Install-Module
    Write-Host "  Bootstrapping the NuGet package provider"
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction SilentlyContinue | Out-Null

    # "You are installing from an untrusted repository" from Install-Module
    Write-Host "  Trusting PSGallery"
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue

    # winget source/package agreements
    Write-Host "  Accepting winget source agreements"
    winget list --accept-source-agreements --disable-interactivity | Out-Null
}

function Show-InteractiveWarning($concerns)
{
    # Third party GUI installers we cannot silence - warn before the run starts
    # rather than letting the user discover it an hour in.
    $interactive = @()
    if ($concerns['chrisTitus'])   { $interactive += 'chrisTitus - opens a GUI and waits for you. Runs dead last, so everything else is done by then.' }
    if ($concerns['dev'])          { $interactive += 'dev - the sourcetree installer is not silent. Runs at the end of the dev apps, so the rest of dev is done by then.' }
    if ($concerns['visualStudio']) { $interactive += 'visualStudio - runs passive, so it shows a progress window but does not ask anything.' }

    if (-not $interactive) {
        Write-Host "No further prompts - this run is unattended from here."
        Write-Host ""
        return
    }

    Write-Host "No more questions, but these selected concerns open a window during the run:"
    foreach ($item in $interactive) { Write-Wrapped $item '  - ' '    ' }
    Write-Host "Everything else is unattended."
    Write-Host ""
}

function Show-ConcernSummary($concerns)
{
    Write-Host ""
    Write-Host "--- Selected concerns ---"
    foreach ($def in $script:ConcernDefinitions) {
        $mark = if ($concerns[$def.Key]) { '[X]' } else { '[ ]' }
        Write-Host ("  {0} {1}" -f $mark, $def.Key)
    }
    Write-Host ""
}

function Get-Concerns()
{
    $config = Get-SavedConfig
    $script:Settings = @{}

    # Saved config present: run unattended (also covers Boxstarter reboot-resume).
    # Delete the config file to force interactive reconfiguration.
    if ($config -and $config.concerns) {
        Write-Host "Loaded saved concerns from $script:ConfigPath (delete this file to reconfigure)"

        $saved = $config.concerns
        $concerns = @{}
        foreach ($def in $script:ConcernDefinitions) {
            $key = $def.Key
            $value = $false
            if ($saved.PSObject.Properties.Name -contains $key) {
                $value = [bool]$saved.$key
            }
            $concerns[$key] = $value
        }

        if ($config.settings) {
            foreach ($property in $config.settings.PSObject.Properties) {
                $script:Settings[$property.Name] = $property.Value
            }
        }

        Show-ConcernSummary $concerns
        return $concerns
    }

    # First run (no saved config): prompt interactively, default No.
    $concerns = @{}
    foreach ($def in $script:ConcernDefinitions) {

        # Don't ask questions whose answer cannot matter. Definitions are
        # ordered so a DependsOn concern is always answered before its dependents.
        if ($def.DependsOn -and -not $concerns[$def.DependsOn]) {
            Write-Host ""
            Write-Host "$($def.Prompt)? [not asked - $($def.DependsOn) was declined]"
            $concerns[$def.Key] = $false
            continue
        }

        if ($def.Precondition -and -not (& $def.Precondition)) {
            Write-Host ""
            Write-Host "$($def.Prompt)? [not asked - $($def.SkipNote)]"
            $concerns[$def.Key] = $false
            continue
        }

        Write-Host ""
        Write-Host "$($def.Prompt)?"
        if ($def.Description) { Write-Wrapped $def.Description }
        if ($def.Packages) {
            Write-Wrapped ("Packages: " + ($def.Packages -join ', ')) '  ' '            '
        }
        $answer = Read-Host "  [y/N]"
        $isSelected = ($answer -match '^(y|yes)$')
        $concerns[$def.Key] = $isSelected

        # Concerns that need a value ask for it now so later runs stay unattended
        if ($isSelected -and $def.ValueKey) {
            $value = ''
            while (-not $value) {
                $value = (Read-Host "  $($def.ValuePrompt)").Trim()
            }
            $script:Settings[$def.ValueKey] = $value
        }
    }

    Save-Config $concerns $script:Settings
    Show-ConcernSummary $concerns
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

    Start-Process 'powercfg.exe' -Verb runAs -ArgumentList '/h off'     # Disable hibernate
}

function Set-AutoLogonPolicy()
{
    Write-Host "--- [Auto Logon] ---"
    # Unhides the "Users must enter a user name and password" checkbox in netplwiz
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device" -Name "DevicePasswordLessBuildVersion" -Value 0
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

    # AWS PowerShell tools. -Force also suppresses the untrusted-repository
    # prompt; PSGallery is trusted in Initialize-UnattendedSession as well.
    Install-Module -Name AWS.Tools.Common -Force -AllowClobber -Confirm:$false
    Install-Module -Name AWS.Tools.EC2 -Force -AllowClobber -Confirm:$false
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

    # A saved config or an explicit target can reach here on a machine that has
    # no D:, so re-check rather than relocating folders onto a missing drive
    if (-not (Test-DataDrive)) {
        Write-Warning "  No D: drive on this machine, skipping"
        return
    }

    Set-Volume -DriveLetter "D" -NewFileSystemLabel "Data"

    $userDataPath = "D:\Data\User"
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
    winget uninstall Microsoft.OneDrive --silent --disable-interactivity --accept-source-agreements

    Disable-BingSearch
    Disable-GameBarTips
}

function Rename-Host()
{
    Write-Host "--- [Rename Host] ---"

    $newName = $script:Settings['hostName']
    if (-not $newName) {
        Write-Warning "  No hostName in $script:ConfigPath, skipping rename"
        return
    }

    if ($env:COMPUTERNAME -eq $newName) {
        Write-Host "  [SKIP] already named $newName"
        return
    }

    # No -Restart: the rename lands at the next reboot, whenever that happens
    Write-Host "  Renaming $env:COMPUTERNAME to $newName (effective at next reboot)"
    Rename-Computer -NewName $newName -Force -ErrorAction Continue
}

function Invoke-ChrisTitusUtility()
{
    Write-Host "--- [Chris Titus Windows Utility] ---"
    # Interactive GUI - will block an unattended run
    iwr -useb https://christitus.com/win | iex
}

# ===========================================================================
# Main
# ===========================================================================

# Command line first: --help and --list report and exit without touching the
# machine, so they stay usable on a box that has no Boxstarter installed.
$options = Get-CommandLineOptions $Arguments

if ($options.Unknown) {
    Write-Host ""
    Write-Warning ("Unknown argument(s): " + ($options.Unknown -join ', '))
    Show-Usage
    exit 1
}

if ($options.Help) { Show-Usage; exit 0 }
if ($options.List) { Show-ConcernList; exit 0 }
if ($options.Reset) { Reset-SavedConfig }

Install-Boxstarter
Import-Module Boxstarter.Chocolatey

$Boxstarter.RebootOk = $true
$Boxstarter.NoPassword = $false
$Boxstarter.AutoLogin = $true

# All questions are asked here, before any work starts, so the rest of the
# run is unattended. Anything that would prompt later belongs in Get-Concerns
# (as a concern or a ValueKey) or in Initialize-UnattendedSession.
if ($options.Targets) {
    $concerns = Get-TargetedConcerns $options.Targets
} else {
    $concerns = Get-Concerns
}

Show-InteractiveWarning $concerns
Initialize-UnattendedSession

# A targeted run does only what was named, so the always-on housekeeping below
# is skipped. A normal run keeps doing all of it.
$isFullRun = -not $options.Targets

if ($concerns['regionalSettings']) { SetRegionalSettings }

if ($isFullRun) {
    # Windows update early ensures prerequisites are met
    InstallWindowsUpdate

    InstallGraphicsDrivers
}

if ($concerns['baseSettings']) { ConfigureBaseSettings }
if ($concerns['autoLogon'])    { Set-AutoLogonPolicy }

Write-BoxstarterMessage "Starting chocolatey installs"

if ($isFullRun) {
    Write-Host "--- [User Settings] ---"
    Install-ChocoPackages $userSettingsApps
}

if ($concerns['core']) {
    Write-Host "--- [Core Apps] ---"
    Install-ChocoPackages $coreApps
}

if ($concerns['ddrive']) { ConfigureDdrive }

if ($concerns['home']) {
    Write-Host "--- [Home Apps] ---"
    Enable-RemoteDesktop
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

if ($isFullRun) {
    CleanDesktopShortcuts

    DownloadConfigFiles
}

if ($concerns['win11Tweaks']) { Invoke-Win11Tweaks }

# A pending rename must not land in the middle of a Boxstarter reboot cycle
if ($concerns['renameHost']) { Rename-Host }

# Dead last: the only step that blocks on a human. Everything above has
# finished by the time this opens its window.
if ($concerns['chrisTitus']) { Invoke-ChrisTitusUtility }

Write-Host "Provisioning complete."
