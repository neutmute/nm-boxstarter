<#
    Main provisioning script. Run from an elevated PowerShell:

    Set-ExecutionPolicy Unrestricted -Force
    .\base-box.ps1

    Boxstarter is installed automatically if it is not already present.

    Install profiles ("concerns") are chosen interactively at runtime and
    persisted to neutmute-boxstarter.json in the user's Documents folder.
    The script is idempotent and safe to run multiple times.
#>

function Install-Boxstarter()
{
    if (Get-Module -ListAvailable -Name Boxstarter.Chocolatey) { return }
    Write-Host "Installing Boxstarter..."
    . { Invoke-WebRequest -useb https://boxstarter.org/bootstrapper.ps1 } | Invoke-Expression
    Get-Boxstarter -Force
}

Install-Boxstarter
Import-Module Boxstarter.Chocolatey

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

$Boxstarter.RebootOk = $true
$Boxstarter.NoPassword = $false
$Boxstarter.AutoLogin = $true

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
    $saved = Get-SavedConcerns

    # Saved config present: run unattended (also covers Boxstarter reboot-resume).
    # Delete the config file to force interactive reconfiguration.
    if ($saved) {
        Write-Host "Loaded saved concerns from $script:ConfigPath (delete this file to reconfigure)"

        $concerns = @{}
        foreach ($def in $script:ConcernDefinitions) {
            $key = $def.Key
            $value = $false
            if ($saved.PSObject.Properties.Name -contains $key) {
                $value = [bool]$saved.$key
            }
            $concerns[$key] = $value
        }

        Show-ConcernSummary $concerns
        return $concerns
    }

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

    Save-Concerns $concerns
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
    winget uninstall Microsoft.OneDrive --accept-source-agreements
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

$concerns = Get-Concerns

if ($concerns['regionalSettings']) { SetRegionalSettings }

# Windows update early ensures prerequisites are met
InstallWindowsUpdate

InstallGraphicsDrivers

# disable chocolatey default confirmation behaviour (no need for --yes)
choco feature enable --name=allowGlobalConfirmation

if ($concerns['baseSettings']) { ConfigureBaseSettings }
if ($concerns['autoLogon'])    { Set-AutoLogonPolicy }

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

if ($concerns['win11Tweaks']) { Invoke-Win11Tweaks }
if ($concerns['chrisTitus'])  { Invoke-ChrisTitusUtility }

Write-Host "Provisioning complete."
