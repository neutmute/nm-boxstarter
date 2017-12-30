# also see https://github.com/W4RH4WK/Debloat-Windows-10

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



