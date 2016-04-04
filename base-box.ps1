$Boxstarter.RebootOk=$true
$Boxstarter.NoPassword=$false
$Boxstarter.AutoLogin=$true

Enable-RemoteDesktop
Update-ExecutionPolicy -Policy Unrestricted
#Install-WindowsUpdate -AcceptEula

Set-Volume -DriveLetter $systemDrive -NewFileSystemLabel "System"

Write-BoxstarterMessage "Starting chocolatey installs"

choco install firefox                           --yes
choco install googlechrome                      --yes
choco install flashplayerplugin                 --yes
choco install notepadplusplus.install           --yes
choco install paint.net                         --yes
choco install itunes                            --yes
choco install irfanview                         --yes
choco install irfanviewplugins                  --yes
choco install 7zip.install                      --yes
choco install k-litecodecpackfull               --yes

choco install commandwindowhere                 --yes
choco install taskbar-never-combine             --yes
choco install explorer-show-all-folders         --yes
choco install explorer-expand-to-current-folder --yes
