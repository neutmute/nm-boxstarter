<# also see 

    --= Debloat-Windows-10 =--
    
    https://github.com/W4RH4WK/Debloat-Windows-10

    #Powershell
    choco install git.install /GitAndUnixToolsOnPath  --limitoutput --force

    #Open Elevated GitBash
    mkdir c:\temp
    cd C:\temp
    git clone https://github.com/W4RH4WK/Debloat-Windows-10.git
    cd Debloat-Windows-10/scripts
    powershell -f ./block-telemetry.ps1
    #powershell -f ./disable-services.ps1
    #powershell -f ./disable-windows-defender.ps1
    #powershell -f ./experimental_unfuckery.ps1
    powershell -f ./fix-privacy-settings.ps1
    #powershell -f ./optimize-user-interface.ps1
    #powershell -f ./optimize-windows-update.ps1
    #powershell -f ./remove-default-apps.ps1
    powershell -f ./remove-onedrive.ps1
    
#>

Function DisableCortana
{  
    $path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"    
    IF(!(Test-Path -Path $path)) { 
        New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows" -Name "Windows Search"
    } 
    Set-ItemProperty -Path $path -Name "AllowCortana" -Value 0 
    #Restart Explorer to change it immediately    
    Stop-Process -name explorer
}

Function RemoveBloat{
    #https://github.com/W4RH4WK/Debloat-Windows-10/blob/master/scripts/optimize-user-interface.ps1
    
    # Remove Videos from This PC
    Remove-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\{A0953C92-50DC-43bf-BE83-3742FED03C9C}"
    Remove-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\{f86fa3ab-70d2-4fc7-9c99-fcbf05467f3a}"
    Remove-Item "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\{A0953C92-50DC-43bf-BE83-3742FED03C9C}"
    Remove-Item "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\{f86fa3ab-70d2-4fc7-9c99-fcbf05467f3a}"
    
    # Remove 3D Objects from This PC
    Remove-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\{0DB7E03F-FC29-4DC6-9020-FF41B59E513A}"
    Remove-Item "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\{0DB7E03F-FC29-4DC6-9020-FF41B59E513A}"

    Write-Output "Setting folder view options"
    Set-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "Hidden" 1
    Set-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "HideFileExt" 0
    Set-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "HideDrivesWithNoMedia" 0
    Set-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowSyncProviderNotifications" 0

    Write-Output "Disable easy access keyboard stuff"
    Set-ItemProperty "HKCU:\Control Panel\Accessibility\StickyKeys" "Flags" "506"
    Set-ItemProperty "HKCU:\Control Panel\Accessibility\Keyboard Response" "Flags" "122"
    Set-ItemProperty "HKCU:\Control Panel\Accessibility\ToggleKeys" "Flags" "58"
}

Function RemoveDefaultApps
{
    #http://ccmexec.com/2015/08/removing-built-in-apps-from-windows-10-using-powershell/
    # Discover apps
    #$Appx = Get-AppxPackage | select name


    $AppsList = "Microsoft.BingFinance","Microsoft.BingNews","Microsoft.BingWeather","Microsoft.XboxApp","Microsoft.SkypeApp","Microsoft.MicrosoftSolitaireCollection","Microsoft.BingSports","Microsoft.ZuneMusic","Microsoft.ZuneVideo","Microsoft.Windows.Photos","Microsoft.People","Microsoft.MicrosoftOfficeHub","Microsoft.WindowsMaps","microsoft.windowscommunicationsapps","Microsoft.Getstarted","Microsoft.3DBuilder"
    ForEach ($App in $AppsList)
    {
        $PackageFullName = (Get-AppxPackage $App).PackageFullName
        $ProPackageFullName = (Get-AppxProvisionedPackage -online | where {$_.Displayname -eq $App}).PackageName
        write-host $PackageFullName
        Write-Host $ProPackageFullName
        if ($PackageFullName)
        {
            Write-Host "Removing Package: $App"
            remove-AppxPackage -package $PackageFullName
        }
        else
        {
        Write-Host "Unable to find package: $App"
        }
        if ($ProPackageFullName)
        {
        Write-Host "Removing Provisioned Package: $ProPackageFullName"
        Remove-AppxProvisionedPackage -online -packagename $ProPackageFullName
        }
        else
        {
        Write-Host "Unable to find provisioned package: $App"
        }
    }
}

DisableCortana
RemoveDefaultApps
RemoveBloat

OOSU10.exe
