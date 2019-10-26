<# 
#OPTIONAL

    # If Dev Machine
    [Environment]::SetEnvironmentVariable("BoxStarterInstallDev", "1", "Machine") # for reboots
    [Environment]::SetEnvironmentVariable("BoxStarterInstallDev", "1", "Process") # for right now
    
    [Environment]::SetEnvironmentVariable("choco:sqlserver2008:isoImage", "D:\Downloads\en_sql_server_2008_r2_developer_x86_x64_ia64_dvd_522665.iso", "Machine") # for reboots
    [Environment]::SetEnvironmentVariable("choco:sqlserver2008:isoImage", "D:\Downloads\en_sql_server_2008_r2_developer_x86_x64_ia64_dvd_522665.iso", "Process") # for right now
    
    [Environment]::SetEnvironmentVariable("choco:sqlserver2012:isoImage", "D:\Downloads\en_sql_server_2012_developer_edition_with_service_pack_3_x64_dvd_7286643.iso", "Machine") # for reboots
    [Environment]::SetEnvironmentVariable("choco:sqlserver2012:isoImage", "D:\Downloads\en_sql_server_2012_developer_edition_with_service_pack_3_x64_dvd_7286643.iso", "Process") # for right now
    
    [Environment]::SetEnvironmentVariable("choco:sqlserver2016:isoImage", "D:\Downloads\en_sql_server_2016_rc_2_x64_dvd_8509698.iso", "Machine") # for reboots
    [Environment]::SetEnvironmentVariable("choco:sqlserver2016:isoImage", "D:\Downloads\en_sql_server_2016_rc_2_x64_dvd_8509698.iso", "Process") # for right now
    
    # If Home Machine
    [Environment]::SetEnvironmentVariable("BoxStarterInstallHome", "1", "Machine") # for reboots
    [Environment]::SetEnvironmentVariable("BoxStarterInstallHome", "1", "Process") # for right now
    
    # If HTPC
    [Environment]::SetEnvironmentVariable("BoxStarterInstallHtpc", "1", "Machine") # for reboots
    [Environment]::SetEnvironmentVariable("BoxStarterInstallHtpc", "1", "Process") # for right now
    
#START
    Set-ExecutionPolicy Unrestricted
    . { iwr -useb http://boxstarter.org/bootstrapper.ps1 } | iex; get-boxstarter -Force
    $cred=Get-Credential
    Install-BoxstarterPackage -PackageName https://raw.githubusercontent.com/neutmute/nm-boxstarter/master/base-box.ps1 -Credential $cred
#>

$userSettingsApps = @(
    'taskbar-never-combine'
    ,'explorer-show-all-folders'
    ,'explorer-expand-to-current-folder'
)

$coreApps = @(
    'chocolatey'
    ,'firefox'
    ,'googlechrome'
    #,'flashplayerplugin'
    ,'notepadplusplus.install'
    ,'paint.net'
    ,'irfanview'
    ,'irfanviewplugins'
    ,'7zip.install'
    ,'lastpass'
    ,'launchy'
    ,'wintail'
    ,'fscapture'
    ,'shutup10'                  #Windows 10 privacy. Execute with OOSU10.exe
    ,'veracrypt'        
    ,'powershellhere'
    ,'powershellhere-elevated'
    #,'bulkrenameutility'        #works normally but fails under boxstarter
    #,'agentransack'             #works normally but fails under boxstarter
)

$homeApps = @(
    'k-litecodecpackfull'
    ,'itunes'
    ,'handbrake.install'
    ,'steam'
    ,'syncback'
    ,'spotify'
    ,'wakemeonlan'
    ,'evernote'
    ,'calibre'
    ,'imgburn'
    ,'winamp'        
    ,'audacity'
    ,'alldup'                   # freeware tool for searching and removing file duplicates on your computer
)

$htpcApps = @(
    'k-litecodecpackfull'
    ,'mssql2014express-defaultinstance'
    ,'sql-server-management-studio'
    ,'plexmediaserver'
    ,'steam'
    ,'syncback'
    ,'kodi'
    #'tightvnc'     # hipporemote is dead
    #'setpoint'     # logitech
)

$Boxstarter.RebootOk=$true
$Boxstarter.NoPassword=$false
$Boxstarter.AutoLogin=$true

# Need to ensure D: exists but also that it isn't the CD ROM
$hasDdrive = -not((Get-CimInstance Win32_LogicalDisk | Where-Object{($_.DriveType -eq 3) -and ($_.DeviceID -eq "D:")}) -eq $null)

function ConfigureBaseSettings()
{
    Update-ExecutionPolicy -Policy Unrestricted

    Set-Volume -DriveLetter $env:SystemDrive[0] -NewFileSystemLabel "System"
    Set-CornerNavigationOptions -EnableUsePowerShellOnWinX
    Set-WindowsExplorerOptions -EnableShowHiddenFilesFoldersDrives -DisableShowProtectedOSFiles -EnableShowFileExtensions -EnableShowFullPathInTitleBar
    Set-TaskbarOptions -Combine Never
    
    Start-Process 'powercfg.exe' -Verb runAs -ArgumentList '/h off'     # Disable hibernate
}

function MoveLibrary {
    param(
        $libraryName,
        $newPath
    )
    
    if(-not (Test-Path $newPath))  #idempotent
    {
        Move-LibraryDirectory -libraryName $libraryName -newPath $newPath
    }
}

function InstallChocoApps($packageArray){

    foreach ($package in $packageArray) {
        &choco install $package --limitoutput
    }

}

function SetRegionalSettings(){
    #http://stackoverflow.com/questions/4235243/how-to-set-timezone-using-powershell
    &"$env:windir\system32\tzutil.exe" /s "AUS Eastern Standard Time"
    
    Set-ItemProperty -Path "HKCU:\Control Panel\International" -Name sShortDate     -Value dd-MMM-yy
    Set-ItemProperty -Path "HKCU:\Control Panel\International" -Name sCountry       -Value Australia
    Set-ItemProperty -Path "HKCU:\Control Panel\International" -Name sShortTime     -Value HH:mm
    Set-ItemProperty -Path "HKCU:\Control Panel\International" -Name sTimeFormat    -Value HH:mm:ss
    Set-ItemProperty -Path "HKCU:\Control Panel\International" -Name sLanguage      -Value ENA
}

function InstallWindowsUpdate()
{
    Enable-MicrosoftUpdate
    Install-WindowsUpdate -AcceptEula
    if (Test-PendingReboot) { Invoke-Reboot }
}

function InstallSqlServer()
{   
    #rejected by chocolatey.org since iso image is required  :|
    $sqlPackageSource = "https://www.myget.org/F/nm-chocolatey-packs/api/v2"

    choco install sql-server-management-studio
        
    if ((Test-Path env:\choco:sqlserver2008:isoImage) -or (Test-Path env:\choco:sqlserver2008:setupFolder))
    {
        if (Test-PendingReboot) { Invoke-Reboot }   
        $env:choco:sqlserver2008:INSTANCEID="sql2008"
        $env:choco:sqlserver2008:INSTANCENAME="sql2008"
        $env:choco:sqlserver2008:AGTSVCACCOUNT="NT AUTHORITY\SYSTEM"
        $env:choco:sqlserver2008:SQLCOLLATION="SQL_Latin1_General_CP1_CI_AS"
        $env:choco:sqlserver2008:SQLSVCACCOUNT="NT AUTHORITY\SYSTEM"
        $env:choco:sqlserver2008:INSTALLSQLDATADIR="D:\Data\sql"
        choco install sqlserver2008 --source=$sqlPackageSource
    }
    
    if ((Test-Path env:\choco:sqlserver2012:isoImage) -or (Test-Path env:\choco:sqlserver2012:setupFolder))
    {
        if (Test-PendingReboot) { Invoke-Reboot }
        $env:choco:sqlserver2012:INSTALLSQLDATADIR="D:\Data\Sql"
        $env:choco:sqlserver2012:INSTANCEID="sql2012"
        $env:choco:sqlserver2012:INSTANCENAME="sql2012"
        $env:choco:sqlserver2012:FEATURES="SQLENGINE"
        $env:choco:sqlserver2012:AGTSVCACCOUNT="NT Service\SQLAgent`$SQL2012"
        $env:choco:sqlserver2012:SQLSVCACCOUNT="NT Service\MSSQL`$SQL2012"
        $env:choco:sqlserver2012:SQLCOLLATION="SQL_Latin1_General_CP1_CI_AS"
        choco install sqlserver2012 --source=$sqlPackageSource
    }
    
    if ((Test-Path env:\choco:sqlserver2016:isoImage) -or (Test-Path env:\choco:sqlserver2016:setupFolder))
    {
        # Note: No support for Windows 7 https://msdn.microsoft.com/en-us/library/ms143506.aspx
        if (Test-PendingReboot) { Invoke-Reboot }
        $env:choco:sqlserver2016:INSTALLSQLDATADIR="D:\Data\Sql"
        $env:choco:sqlserver2016:INSTANCEID="sql2016"
        $env:choco:sqlserver2016:INSTANCENAME="sql2016"
        $env:choco:sqlserver2016:AGTSVCACCOUNT="NT Service\SQLAgent`$SQL2016"
        $env:choco:sqlserver2016:SQLSVCACCOUNT="NT Service\MSSQL`$SQL2016"
        $env:choco:sqlserver2016:SQLCOLLATION="SQL_Latin1_General_CP1_CI_AS"
        choco install sqlserver2016 --source=$sqlPackageSource
    }   
}

function InstallChocoDevApps
{
    #choco install jdk7                  --limitoutput  #neo4j - but can use docker now

    $devApps = @(
        'nsis.install'
        #,'commandwindowhere'
        ,'filezilla'
        ,'putty'
        ,'winscp'
        ,'wireshark'
        ,'nmap'
        ,'autohotkey.install'
        ,'console2'
        ,'virtualbox'
        ,'dotpeek'
        ,'nuget.commandline'
        ,'nugetpackageexplorer'
        ,'rdcman'                   # remote desktop connection manager
        ,'diffmerge'
        ,'cmake'                     #emgucv
        ,'fiddler4'
        ,'visualstudiocode'
        ,'nodejs'
        ,'checksum'
        ,'gitextensions'
        ,'ilspy'
        ,'poshgit'
        ,'vswhere'
    )
    
    InstallChocoApps $devApps

    choco install git -params '"/GitAndUnixToolsOnPath"'
    choco install sourcetree #do last since not silent
}

function InstallVisualStudio()
{
#    choco install visualstudio2015enterprise --source=https://www.myget.org/F/chocolatey-vs/api/v2 #kennethB is slow pushing to nuget
#    Install-ChocolateyVsixPackage 'PowerShell Tools for Visual Studio 2015' https://visualstudiogallery.msdn.microsoft.com/c9eb3ba8-0c59-4944-9a62-6eee37294597/file/199313/1/PowerShellTools.14.0.vsix
#    Install-ChocolateyVsixPackage 'Productivity Power Tools 2015' https://visualstudiogallery.msdn.microsoft.com/34ebc6a2-2777-421d-8914-e29c1dfa7f5d/file/169971/1/ProPowerTools.vsix
#    
#    Install-ChocolateyPinnedTaskBarItem "$($Boxstarter.programFiles86)\Google\Chrome\Application\chrome.exe"
#    Install-ChocolateyPinnedTaskBarItem "$($Boxstarter.programFiles86)\Microsoft Visual Studio 14.0\Common7\IDE\devenv.exe"

    choco install visualstudio2019community --package-parameters "--allWorkloads --includeRecommended --passive --locale en-US"
}

function InstallInternetInformationServices()
{
    $windowsFeatures = @(
        'Windows-Identity-Foundation'
        ,'Microsoft-Windows-Subsystem-Linux'
        ,'IIS-WebServerRole'
        ,'IIS-WebServer'
        ,'IIS-CommonHttpFeatures'
        ,'IIS-HttpErrors'
        ,'IIS-HttpRedirect'
        ,'IIS-ApplicationDevelopment'
        ,'IIS-NetFxExtensibility45'
        ,'IIS-HealthAndDiagnostics'
        ,'IIS-HttpLogging'
        ,'IIS-LoggingLibraries'
        ,'IIS-RequestMonitor'
        ,'IIS-HttpTracing'
        ,'IIS-Security'
        ,'IIS-URLAuthorization'
        ,'IIS-RequestFiltering'
        ,'IIS-Performance'
        ,'IIS-HttpCompressionDynamic'
        ,'IIS-WebServerManagementTools'
        ,'IIS-ManagementScriptingTools'
        ,'IIS-HostableWebCore'
        ,'IIS-StaticContent'
        ,'IIS-DefaultDocument'
        ,'IIS-WebSockets'
        ,'IIS-ASPNET'
        ,'IIS-ServerSideIncludes'
        ,'IIS-CustomLogging'
        ,'IIS-BasicAuthentication'
        ,'IIS-HttpCompressionStatic'
        ,'IIS-ManagementConsole'
        ,'IIS-ManagementService'
        ,'IIS-WMICompatibility'
        ,'IIS-CertProvider'
        ,'IIS-WindowsAuthentication'
        ,'IIS-DigestAuthentication'
    )
    
    foreach ($package in $windowsFeatures) {
        &choco install $package --source windowsfeatures
    }
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
    Get-ChildItem -Path $allUsersDesktop\*.lnk -Exclude *BoxStarter* | remove-item
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

SetRegionalSettings

# SQL Server requires some KB patches before it will work, so windows update first
Write-BoxstarterMessage "Windows update..."
InstallWindowsUpdate

# disable chocolatey default confirmation behaviour (no need for --yes)
choco feature enable --name=allowGlobalConfirmation

ConfigureBaseSettings

Write-BoxstarterMessage "Starting chocolatey installs"

InstallChocoApps $userSettingsApps    

InstallChocoApps $coreApps

if (Test-Path env:\BoxStarterInstallHome)
{
    Enable-RemoteDesktop                            # already enabled on corp machine and it failed when running
    InstallChocoApps $homeApps
}

if (Test-Path env:\BoxStarterInstallHtpc)
{
    InstallChocoApps $htpcApps
}

if ($hasDdrive)
{
    ConfigureDdrive
}

# Put last as the big SQL server / VS2017 tend to fail and kill Boxstarter it seems
if (Test-Path env:\BoxStarterInstallDev)
{
    Write-BoxstarterMessage "Installing Dev Apps"
    InstallChocoDevApps
    InstallSqlServer
    InstallInternetInformationServices
    InstallVisualStudio
}

CleanDesktopShortcuts

DownloadConfigFiles

# Assume Windows 10
Install-BoxstarterPackage -PackageName https://raw.githubusercontent.com/neutmute/nm-boxstarter/master/win10-clean.ps1

# Leaving global confirmation enabled
# choco feature disable --name=allowGlobalConfirmation

Write-Host "Follow extra optional cleanup steps in win10-clean.ps1"
start https://raw.githubusercontent.com/neutmute/nm-boxstarter/master/win10-clean.ps1
