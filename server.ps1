# For a spun up server

function InstallChocoApps($packageArray){

    foreach ($package in $packageArray) {
	    &choco install $package --limitoutput
    }

}

$serverApps = @(
    'taskbar-never-combine'
    ,'explorer-show-all-folders'
    ,'explorer-expand-to-current-folder'
    ,'googlechrome'
    ,'wintail'
    ,'notepadplusplus.install'
)

# Install Chocolatey
Set-ExecutionPolicy Bypass -Scope Process -Force; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))

# Install Apps
InstallChocoApps $serverApps