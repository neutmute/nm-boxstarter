. ".\Set-KnownFolderPath.ps1"
<# 
	BoxStarter way wasn't working in Win10?   
#>

Write-Host "Configuring D:\"

Set-Volume -DriveLetter "D" -NewFileSystemLabel "Data"

$userDataPath = "D:\Data\Documents"
$mediaPath    = "D:\Media"

Set-KnownFolderPath -KnownFolder 'Pictures'     -Path (Join-Path $userDataPath "Pictures")
Set-KnownFolderPath -KnownFolder 'Documents'    -Path (Join-Path $userDataPath "Documents")
Set-KnownFolderPath -KnownFolder 'Desktop'      -Path (Join-Path $userDataPath "Desktop")
Set-KnownFolderPath -KnownFolder 'Videos'       -Path (Join-Path $mediaPath "Videos")
Set-KnownFolderPath -KnownFolder 'Music'        -Path (Join-Path $mediaPath "Music")
Set-KnownFolderPath -KnownFolder 'Downloads'    -Path "D:\Downloads"