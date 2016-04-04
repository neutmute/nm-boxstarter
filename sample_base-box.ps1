function Convert-Array
{
  begin
  {
    $output = @(); 
  }
  process
  {
    $output += $_; 
  }
  end
  {
    return ,$output; 
  }
}

function Get-SystemDrive
{  
    return $env:SystemDrive[0]
}

function Get-SourceDrive
{
    param(
        $volumes
    )

    # remove system drive from choices of volumes
    $volumes = $volumes | Where-Object { $_.DriveLetter -ne (Get-SystemDrive) }
    
    # no other drives, source drive is system drive
    if ($volumes.Count -eq 0) {
        return Get-SystemDrive
    }

    return $volumes | Sort-Object -Property Size -Descending | Select-Object -First 1 | select -ExpandProperty DriveLetter
}

function Install-WebPackage {
    param(
        $packageName,
        [ValidateSet('exe', 'msi')]
        $fileType,
        $installParameters,
        $downloadFolder,
        $url
    )

    $filename = Split-Path $url -Leaf
    $fullFilename = Join-Path $downloadFolder $filename

    if (test-path $fullFilename) {
        Write-Host "$fullFilename already exists"
        return
    }
    
    Get-ChocolateyWebFile $packageName $fullFilename $url
    Install-ChocolateyInstallPackage $packageName $fileType $installParameters $fullFilename
}

function Move-Library {
    param(
        $libraryName,
        $newPath
    )
    
    if(-not (Test-Path $newPath)) {
        Move-LibraryDirectory -libraryName $libraryName -newPath $newPath
    }
}

$Boxstarter.RebootOk=$true # Allow reboots
$Boxstarter.NoPassword=$false # machine has login password
$Boxstarter.AutoLogin=$true # Encrypt and temp store password for auto-logins after reboot

Update-ExecutionPolicy Unrestricted

$volumes = Get-Volume | Where-Object { $_.DriveType -eq "Fixed" -and $_.DriveLetter -ne $null } | Convert-Array
$systemDrive = Get-SystemDrive
$sourceDrive = Get-SourceDrive $volumes
$systemDrivePath = "$systemDrive`:"
$sourceDrivePath = "$sourceDrive`:"
$tempInstallFolder = Join-Path $sourceDrivePath "temp\install-cache"

if(-not (Test-Path $tempInstallFolder)) {
    New-Item $tempInstallFolder -ItemType Directory
}

# set up drives
Set-Volume -DriveLetter $systemDrive -NewFileSystemLabel "OS"

if ($systemDrive -ne $sourceDrive) {
    Set-Volume -DriveLetter $sourceDrive -NewFileSystemLabel "Source"

    # move libraries of system drive
    $userPath = Join-Path $sourceDrivePath $env:HOMEPATH
    
    if(-not (Test-Path $userPath)) {
        New-Item $userPath -ItemType Directory
    }
    
    Move-Library -libraryName "My Video"    -newPath (Join-Path $userPath "Videos")
    Move-Library -libraryName "My Pictures" -newPath (Join-Path $userPath "Pictures")
    Move-Library -libraryName "Personal"    -newPath (Join-Path $userPath "Documents")
    Move-Library -libraryName "My Music"    -newPath (Join-Path $userPath "Music")
}

# make folder for source code
$sourceCodeDirectory = Join-Path $sourceDrivePath "git"
if(-not (Test-Path $sourceCodeDirectory)) {
    New-Item $sourceCodeDirectory -ItemType Directory
} 

# replace command prompt with powershell in start menu and win+x
Set-CornerNavigationOptions -EnableUsePowerShellOnWinX

# show extensions
Set-WindowsExplorerOptions -EnableShowHiddenFilesFoldersDrives -EnableShowProtectedOSFiles -EnableShowFileExtensions -EnableShowFullPathInTitleBar

# Disable hibernate
Start-Process 'powercfg.exe' -Verb runAs -ArgumentList '/h off'

# enable windows features
choco install NetFx3 --source windowsfeatures
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
choco install IIS-RequestFiltering --source windowsfeatures

choco install IIS-Performance --source windowsfeatures
choco install IIS-HttpCompressionDynamic --source windowsfeatures
choco install IIS-HttpCompressionStatic --source windowsfeatures
choco install IIS-BasicAuthentication --source windowsfeatures

choco install TelnetClient --source windowsfeatures

# install critical windows updates
Enable-MicrosoftUpdate
Install-WindowsUpdate -acceptEula 

if (Test-PendingReboot) { Invoke-Reboot }

#install apps
choco install chocolatey -y
choco install dotnet4.5.2 -y
choco install git.install -y -params '"/GitAndUnixToolsOnPath"'
choco install git-credential-manager-for-windows -y
choco install 7zip.install -y


choco install visualstudiocode -y
choco install visualstudio2015community -y -packageParameters "--Features SQL"

if (Test-PendingReboot) { Invoke-Reboot }

choco install UrlRewrite -y
choco install resharper -y
choco install dotpeek -y
choco install sourcetree -y
##choco install packer -y

#Name: "Docker"; Description: "Docker Client for Windows" ; Types: full custom; Flags: fixed
#Name: "DockerMachine"; Description: "Docker Machine for Windows" ; Types: full custom; Flags: fixed
#Name: "DockerCompose"; Description: "Docker Compose for Windows" ; Types: full custom
#Name: "VirtualBox"; Description: "VirtualBox"; Types: full custom; Flags: disablenouninstallwarning
#Name: "Kitematic"; Description: "Kitematic for Windows (Alpha)" ; Types: full custom
#Name: "Git"; Description: "Git for Windows"; Types: full custom; Flags: disablenouninstallwarning

#Name: desktopicon; Description: "{cm:CreateDesktopIcon}"
#Name: modifypath; Description: "Add docker binaries to &PATH"
#Name: upgradevm; Description: "Upgrade Boot2Docker VM"

Install-WebPackage 'Docker Toolbox' 'exe' '/SILENT /COMPONENTS="Docker,DockerMachine,DockerCompose,VirtualBox,Kitematic" /TASKS="modifypath"' $tempInstallFolder https://github.com/docker/toolbox/releases/download/v1.9.1i/DockerToolbox-1.9.1i.exe
choco install redis-desktop-manager -y
choco install nodejs.install -y
choco install Notepadplusplus.install -y
choco install baretail -y

choco install slack -y
choco install googlechrome -y
choco install Firefox -y
choco install webpi -y
#choco install cmder -y // need to figure out how to configure properly
choco install paint.net -y
choco install teamviewer -y
choco install putty.install -y
#choco install dropbox -y
#choco install vlc -y
choco install skype -y
choco install fiddler4 -y
choco install adobereader -y

# pin apps that update themselves
choco pin add -n=googlechrome
choco pin add -n=Firefox 
choco pin add -n=visualstudiocode
choco pin add -n=visualstudio2015community
choco pin add -n=sourcetree
choco pin add -n='paint.net'

# install powershell modules
Set-PSRepository -Name 'PSGallery' -InstallationPolicy 'Trusted'
Install-Module -Name posh-git
Install-Module -Name Carbon
Install-Module -Name PowerShellHumanizer
Install-Module -Name PsConfig
Install-Module -Name posh-vs
#Install-Module -Name posh-docker
#Install-Module -Name posh-npm
Set-PSRepository -Name 'PSGallery' -InstallationPolicy 'Untrusted'

#if (Test-PendingReboot) { Invoke-Reboot }

## Install Dev extensions
Install-ChocolateyVsixPackage 'SideWaffle Template Pack' https://visualstudiogallery.msdn.microsoft.com/a16c2d07-b2e1-4a25-87d9-194f04e7a698/referral/110630
Install-ChocolateyVsixPackage 'Web Essentials 2015.1' https://visualstudiogallery.msdn.microsoft.com/ee6e6d8c-c837-41fb-886a-6b50ae2d06a2/file/146119/34/Web%20Essentials%202015.1%20v1.0.203.vsix
Install-ChocolateyVsixPackage 'Glyphfriend' https://visualstudiogallery.msdn.microsoft.com/5fd24afb-b3b2-4cec-9b03-1cfcec6123aa/file/150806/7/Glyphfriend.vsix
Install-ChocolateyVsixPackage 'Web Compiler' https://visualstudiogallery.msdn.microsoft.com/3b329021-cd7a-4a01-86fc-714c2d05bb6c/file/164873/35/Web%20Compiler%20v1.10.300.vsix
Install-ChocolateyVsixPackage 'PowerShell Tools for Visual Studio 2015' https://visualstudiogallery.msdn.microsoft.com/c9eb3ba8-0c59-4944-9a62-6eee37294597/file/199313/1/PowerShellTools.14.0.vsix
Install-ChocolateyVsixPackage 'Productivity Power Tools 2015' https://visualstudiogallery.msdn.microsoft.com/34ebc6a2-2777-421d-8914-e29c1dfa7f5d/file/169971/1/ProPowerTools.vsix
Install-ChocolateyVsixPackage 'Image Optimizer' https://visualstudiogallery.msdn.microsoft.com/a56eddd3-d79b-48ac-8c8f-2db06ade77c3/file/38601/34/Image%20Optimizer%20v3.3.51.vsix
Install-ChocolateyVsixPackage 'Package Installer' https://visualstudiogallery.msdn.microsoft.com/753b9720-1638-4f9a-ad8d-2c45a410fd74/file/173807/20/Package%20Installer%20v1.5.69.vsix
Install-ChocolateyVsixPackage 'PostSharp' https://visualstudiogallery.msdn.microsoft.com/a058d5d3-e654-43f8-a308-c3bdfdd0be4a/file/89212/78/PostSharp-4.2.18.exe
Install-ChocolateyVsixPackage 'BuildVision' https://visualstudiogallery.msdn.microsoft.com/23d3c821-ca2d-4e1a-a005-4f70f12f77ba/file/95980/13/BuildVision.vsix
Install-ChocolateyVsixPackage 'File Nesting' https://visualstudiogallery.msdn.microsoft.com/3ebde8fb-26d8-4374-a0eb-1e4e2665070c/file/123284/23/File%20Nesting%20v2.2.36.vsix

Install-WebPackage 'Microsoft ASP.NET and Web Tools' 'exe' '/s /S /q /Q /quiet /silent /SILENT' $tempInstallFolder https://visualstudiogallery.msdn.microsoft.com/c94a02e9-f2e9-4bad-a952-a63a967e3935/file/77371/6/AspNet5.ENU.RC1_Update1.exe

if (Test-PendingReboot) { Invoke-Reboot }

# reload path environment variable 
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    
npm install -g typings
npm install -g jspm

[Environment]::SetEnvironmentVariable("HOME", $Env:UserProfile, "User")

Install-ChocolateyPinnedTaskBarItem "$($Boxstarter.programFiles86)\Google\Chrome\Application\chrome.exe"
Install-ChocolateyPinnedTaskBarItem "$($Boxstarter.programFiles86)\Microsoft Visual Studio 14.0\Common7\IDE\devenv.exe"

Install-ChocolateyFileAssociation ".dll" "$($Boxstarter.programFiles86)\jetbrains\dotpeek\v1.1\Bin\dotpeek32.exe"

# install critical windows updates
Enable-MicrosoftUpdate
Install-WindowsUpdate -acceptEula 

if (Test-PendingReboot) { Invoke-Reboot }