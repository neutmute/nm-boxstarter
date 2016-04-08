<# 

#OPTIONAL
	# If Dev Machine
	[Environment]::SetEnvironmentVariable("BoxStarterInstallDev", "1", "Machine") # for reboots
	[Environment]::SetEnvironmentVariable("BoxStarterInstallDev", "1", "Process") # for right now
	
	# If Home Machine
	[Environment]::SetEnvironmentVariable("BoxStarterInstallHome", "1", "Machine") # for reboots
	[Environment]::SetEnvironmentVariable("BoxStarterInstallHome", "1", "Process") # for right now
	
#START
	START http://boxstarter.org/package/nr/url?https://raw.githubusercontent.com/neutmute/nm-boxstarter/master/base-box.ps1

#>

$Boxstarter.RebootOk=$true
$Boxstarter.NoPassword=$false
$Boxstarter.AutoLogin=$true

$hasDdrive = (Test-Path D:)

function ConfigureBaseSettings()
{
	Enable-RemoteDesktop
	Update-ExecutionPolicy -Policy Unrestricted

	Set-Volume -DriveLetter $env:SystemDrive[0] -NewFileSystemLabel "System"
	Set-CornerNavigationOptions -EnableUsePowerShellOnWinX
	Set-WindowsExplorerOptions -EnableShowHiddenFilesFoldersDrives -DisableShowProtectedOSFiles -EnableShowFileExtensions -EnableShowFullPathInTitleBar
	Set-TaskbarOptions -Combine Never
	
	Start-Process 'powercfg.exe' -Verb runAs -ArgumentList '/h off'		# Disable hibernate
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

function InstallChocoCoreApps()
{
	choco install firefox                           --yes --limitoutput
	choco install googlechrome                      --yes --limitoutput
	choco install flashplayerplugin                 --yes --limitoutput
	choco install notepadplusplus.install           --yes --limitoutput
	choco install paint.net                         --yes --limitoutput
	choco install irfanview                         --yes --limitoutput
	choco install irfanviewplugins                  --yes --limitoutput
	choco install 7zip.install                      --yes --limitoutput
	choco install lastpass			                --yes --limitoutput
	#choco install veracrypt 						--yes --limitoutput #not silent
}

function InstallChocoHomeApps()
{
	choco install k-litecodecpackfull               --yes --limitoutput	
	choco install itunes                            --yes --limitoutput
}

function InstallChocoUserSettings()
{
	choco install taskbar-never-combine             --yes --limitoutput
	choco install explorer-show-all-folders         --yes --limitoutput
	choco install explorer-expand-to-current-folder --yes --limitoutput
}

function InstallWindowsUpdate()
{
	Enable-MicrosoftUpdate
	#Install-WindowsUpdate -AcceptEula
	if (Test-PendingReboot) { Invoke-Reboot }
}

function InstallChocoDevApps
{
	choco install jdk7		              --yes --limitoutput  #neo4j
	choco install nsis.install            --yes --limitoutput
	choco install commandwindowhere       --yes --limitoutput
	choco install filezilla               --yes --limitoutput
	choco install putty                   --yes --limitoutput
	choco install winscp                  --yes --limitoutput
	choco install wireshark               --yes --limitoutput
	choco install nmap                    --yes --limitoutput
	choco install autohotkey.install      --yes --limitoutput
	choco install windirstat              --yes --limitoutput
	choco install console2                --yes --limitoutput
	choco install virtualbox              --yes --limitoutput
	choco install dotpeek                 --yes --limitoutput
	choco install nugetpackageexplorer    --yes --limitoutput
	choco install sourcetree 			  --yes --limitoutput --version 1.7.0.32509 		#1.8 destroyed UX
	#choco install pidgin                  --yes --limitoutput
	
	choco install git.install -params '"/GitAndUnixToolsOnPath"'	--yes --limitoutput

	choco install visualstudio2015enterprise
	Install-ChocolateyVsixPackage 'PowerShell Tools for Visual Studio 2015' https://visualstudiogallery.msdn.microsoft.com/c9eb3ba8-0c59-4944-9a62-6eee37294597/file/199313/1/PowerShellTools.14.0.vsix
	Install-ChocolateyVsixPackage 'Productivity Power Tools 2015' https://visualstudiogallery.msdn.microsoft.com/34ebc6a2-2777-421d-8914-e29c1dfa7f5d/file/169971/1/ProPowerTools.vsix
	
	Install-ChocolateyPinnedTaskBarItem "$($Boxstarter.programFiles86)\Google\Chrome\Application\chrome.exe"
	Install-ChocolateyPinnedTaskBarItem "$($Boxstarter.programFiles86)\Microsoft Visual Studio 14.0\Common7\IDE\devenv.exe"
}

function InstallInternetInformationServices()
{
	choco install IIS-WebServerRole --source windowsfeatures
	choco install IIS-WebServer --source windowsfeatures
	choco install IIS-WebServerManagementTools --source windowsfeatures
	choco install IIS-ManagementScriptingTools --source windowsfeatures
	choco install IIS-IIS6ManagementCompatibility --source windowsfeatures
	choco install IIS-Metabase --source windowsfeatures
	choco install IIS-ManagementConsole --source windowsfeatures

	choco install IIS-CommonHttpFeatures --source windowsfeatures
	choco install IIS-HttpErrors --source windowsfeatures
	choco install IIS-HttpRedirect --source windowsfeatures
	choco install IIS-StaticContent --source windowsfeatures

	choco install IIS-ApplicationDevelopment --source windowsfeatures
	choco install NetFx4Extended-ASPNET45 --source windowsfeatures
	choco install IIS-NetFxExtensibility45 --source windowsfeatures
	choco install IIS-ISAPIFilter --source windowsfeatures
	choco install IIS-ISAPIExtensions --source windowsfeatures
	choco install IIS-RequestFiltering --source windowsfeatures
	choco install IIS-ASPNET45 --source windowsfeatures
	choco install IIS-ApplicationInit --source windowsfeatures

	choco install IIS-HealthAndDiagnostics --source windowsfeatures
	choco install IIS-HttpLogging --source windowsfeatures
	choco install IIS-LoggingLibraries --source windowsfeatures
	choco install IIS-RequestMonitor --source windowsfeatures
	choco install IIS-HttpTracing --source windowsfeatures
	choco install IIS-CustomLogging --source windowsfeatures

	choco install IIS-Performance --source windowsfeatures
	choco install IIS-HttpCompressionDynamic --source windowsfeatures
	choco install IIS-HttpCompressionStatic --source windowsfeatures
	choco install IIS-BasicAuthentication --source windowsfeatures
}

ConfigureBaseSettings

Write-BoxstarterMessage "Starting chocolatey installs"

InstallChocoUserSettings	
InstallChocoCoreApps

if (Test-Path env:\BoxStarterInstallDev)
{
	Write-BoxstarterMessage "Installing dev apps"
	InstallChocoDevApps
}

if (Test-Path env:\BoxStarterInstallHome)
{
	InstallChocoHomeApps
}

if ($hasDdrive)
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

Write-BoxstarterMessage "Windows update..."
InstallWindowsUpdate
