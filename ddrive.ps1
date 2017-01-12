<# 
	
	START http://boxstarter.org/package/nr/url?https://raw.githubusercontent.com/neutmute/nm-boxstarter/master/ddrive.ps1

#>

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