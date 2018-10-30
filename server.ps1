
<#
For a spun up server
Also see https://gist.github.com/alirobe/1e9fb1fd8eefd72ce5cd372459a88b59
#>

function InstallChocoApps($packageArray){

    foreach ($package in $packageArray) {
	    &choco install $package --limitoutput
    }

}


function ConfigureNotepadPlusPlus()
{
    Write-Host 'Configuring Notepad++'
    $notepadShortcutConfigRemote = 'https://raw.githubusercontent.com/neutmute/nm-boxstarter/master/files/notepad%2B%2B/shortcuts.xml'
    $notepadShortcutConfigLocal = "$($env:AppData)\Notepad++\shortcuts.xml"
    Invoke-WebRequest -Uri $notepadShortcutConfigRemote -OutFile $notepadShortcutConfigLocal
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

choco feature enable --name=allowGlobalConfirmation

# Install Apps
InstallChocoApps $serverApps

ConfigureNotepadPlusPlus