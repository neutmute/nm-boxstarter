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
Import-Module Boxstarter.Chocolatey

$userSettingsApps = @(
    'taskbar-never-combine'
    ,'explorer-show-all-folders'
    ,'explorer-expand-to-current-folder'
)

$coreApps = @(
    'chocolatey'
    ,'firefox'
    ,'googlechrome'
    ,'notepadplusplus.install'
    ,'paint.net'
    ,'irfanview'
    ,'irfanviewplugins'
    ,'7zip.install'
    ,'launchy'
    ,'wintail'
    ,'shutup10'                  #Windows privacy. Execute with OOSU10.exe
    ,'veracrypt'        
    ,'powershellhere'
    ,'powershellhere-elevated'
	,'windirstat'
    ,'wakemeonlan'
    #,'bulkrenameutility'        #works normally but fails under boxstarter
    #,'agentransack'             #works normally but fails under boxstarter
)

$homeApps = @(
    ,'fscapture'
#    ,'itunes'
#    ,'handbrake.install'
#    ,'steam'					# want this to go to d:
    ,'syncbackfree'
    ,'spotify'
    ,'evernote'
    ,'calibre'
   # ,'imgburn'
    ,'winamp'        
    ,'audacity'
    ,'alldup'                   # freeware tool for searching and removing file duplicates on your computer
	,'beebeep'
	,'sendtokindle'
)

$htpcApps = @(
   # 'k-litecodecpackfull'
   # ,'mssql2014express-defaultinstance'
   # ,'sql-server-management-studio'
   # ,'plexmediaserver'
    ,'steam'
    ,'syncbackfree'
    ,'kodi'
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
    $devApps = @(
        #'nsis.install'
        #,'commandwindowhere'
        #,'filezilla'
        #,'virtualbox'  # if VM we want this manually 
        #,'nugetpackageexplorer'
        #,'wireshark'
        'putty'
        ,'winscp'
        ,'nmap'
        ,'autohotkey.install'		
		,'microsoft-windows-terminal'
        ,'nuget.commandline'
        ,'rdcman'                   # remote desktop connection manager 
        ,'diffmerge'
        ,'checksum'
        ,'gitextensions'
        ,'ilspy'
        ,'openssl'
		,'slack'
		,'sql-server-management-studio'
        ,'vswhere'
        ,'vscode'

    )

    choco install git.install --params "'/GitAndUnixToolsOnPath /WindowsTerminal'"
    
    InstallChocoApps $devApps

    choco install sourcetree #do last since not silent
}

function InstallVisualStudio()
{
    choco install visualstudio2022community --package-parameters "--allWorkloads --includeRecommended --passive --locale en-US"
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
    Disable-BingSearch
    Disable-GameBarTips
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
    #InstallSqlServer
    InstallInternetInformationServices
    #InstallVisualStudio
}

CleanDesktopShortcuts

DownloadConfigFiles

# Assume Windows 10
Install-BoxstarterPackage -PackageName https://raw.githubusercontent.com/neutmute/nm-boxstarter/master/win10-clean.ps1

# Leaving global confirmation enabled
# choco feature disable --name=allowGlobalConfirmation

Write-Host "Follow extra optional cleanup steps in win10-clean.ps1"
Start-Process https://raw.githubusercontent.com/neutmute/nm-boxstarter/master/win10-clean.ps1
