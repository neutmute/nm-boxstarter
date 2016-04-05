<# 
Invoke with

OPTIONAL
	[Environment]::SetEnvironmentVariable("BoxStarterIsDev", "1", "Machine")
	
	
START
	START http://boxstarter.org/package/nr/url?https://raw.githubusercontent.com/neutmute/nm-boxstarter/master/base-box.ps1


#>
#Import-Module Boxstarter.Chocolatey

$Boxstarter.RebootOk=$true
$Boxstarter.NoPassword=$false
$Boxstarter.AutoLogin=$true


Enable-RemoteDesktop
Update-ExecutionPolicy -Policy Unrestricted

Set-Volume -DriveLetter $env:SystemDrive[0] -NewFileSystemLabel "System"

Set-WindowsExplorerOptions -EnableShowHiddenFilesFoldersDrives -EnableShowProtectedOSFiles -EnableShowFileExtensions -EnableShowFullPathInTitleBar
Set-TaskbarOptions -Combine Never

function InstallChocoCoreApps()
{
	Write-BoxstarterMessage "Starting chocolatey installs"
	
	choco install firefox                           --yes --limitoutput
	choco install googlechrome                      --yes --limitoutput
	choco install flashplayerplugin                 --yes --limitoutput
	choco install notepadplusplus.install           --yes --limitoutput
	choco install paint.net                         --yes --limitoutput
	choco install itunes                            --yes --limitoutput
	choco install irfanview                         --yes --limitoutput
	choco install irfanviewplugins                  --yes --limitoutput
	choco install 7zip.install                      --yes --limitoutput
	choco install k-litecodecpackfull               --yes --limitoutput
	#choco install veracrypt 						--yes --limitoutput #not silent
}

function InstallChocoUserSettings()
{
	choco install commandwindowhere                 --yes --limitoutput
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
	#choco install boxstarter              --yes --limitoutput
	choco install nsis.install            --yes --limitoutput
	choco install commandwindowhere       --yes --limitoutput
	choco install filezilla               --yes --limitoutput
	choco install putty                   --yes --limitoutput
	choco install wireshark               --yes --limitoutput
	choco install autohotkey.install      --yes --limitoutput
	choco install winscp                  --yes --limitoutput
	choco install windirstat              --yes --limitoutput
	choco install console2                --yes --limitoutput
	choco install virtualbox              --yes --limitoutput
	choco install nmap                    --yes --limitoutput
	choco install dotpeek                 --yes --limitoutput
	choco install nugetpackageexplorer    --yes --limitoutput
	#choco install pidgin                  --yes --limitoutput
}

InstallChocoCoreApps
InstallChocoUserSettings

if ($env:BoxStarterIsDev eq "1")
{
	InstallChocoDevApps
}

InstallWindowsUpdate