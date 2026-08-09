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
        $answer = Read-Host "$($def.Prompt)? [y/N]"
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
