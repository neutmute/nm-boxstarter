<#
.SYNOPSIS
    Removes the policy lock on the Windows lock screen image and sets a new one.

.DESCRIPTION
    This machine has the lock screen pinned by values written into
    HKLM\SOFTWARE\Policies\Microsoft\Windows\Personalization (NoChangingLockScreen +
    LockScreenImage). Administrators hold FullControl on that key, so the values can
    simply be removed - no ownership takeover required.

    The script:
      1. Backs up every value under the Personalization policy key (and the
         PersonalizationCSP key, if present) to timestamped JSON.
      2. Removes only the image-related restrictions. NoLockScreenCamera is
         deliberately left alone - it is a security setting, not a cosmetic one.
      3. Turns Windows Spotlight off (it would otherwise take over the lock screen
         the moment the policy is gone) unless -Mode Spotlight is requested.
      4. Applies the chosen image, preferring the per-user WinRT LockScreen API so
         the Settings UI stays unlocked and you can change it yourself later.
         Falls back to the device-wide PersonalizationCSP keys if WinRT fails.

.PARAMETER Mode
    Default   - a stock Windows lock screen image from C:\Windows\Web\Screen.
    Blank     - a generated solid-colour image (black unless -BlankColor is given).
    Spotlight - re-enable Windows Spotlight (rotating daily images).
    Image     - use -ImagePath. Selected automatically when -ImagePath is supplied.

.PARAMETER ImagePath
    Path to a .jpg/.jpeg/.png/.bmp to use. Implies -Mode Image. The file is copied
    into C:\ProgramData\LockScreenTool\images so the lock screen does not break if
    the original is moved or deleted.

.PARAMETER Method
    Auto (default) - try WinRT, fall back to PersonalizationCSP.
    WinRT          - per-user API only. Leaves Settings > Lock screen editable.
    CSP            - device-wide registry only. Reliable, but re-greys the Settings UI.

.PARAMETER BlankColor
    Hex colour for -Mode Blank. Default #000000.

.PARAMETER UnlockOnly
    Remove the policy restrictions and stop. Does not change the image.

.PARAMETER Restore
    Put the policy values back exactly as the most recent backup recorded them.

.PARAMETER Persist
    Register a scheduled task that re-applies this configuration at logon. Only
    worth using if Intune later starts pushing the policy back down.

.PARAMETER RemovePersist
    Remove the scheduled task created by -Persist.

.EXAMPLE
    .\Set-LockScreen.ps1
    Unlock the policy and set the stock Windows lock screen image.

.EXAMPLE
    .\Set-LockScreen.ps1 -Mode Blank
    Unlock the policy and set a plain black lock screen.

.EXAMPLE
    .\Set-LockScreen.ps1 -ImagePath "$env:USERPROFILE\Pictures\mountain.jpg"
    Unlock the policy and use your own image.

.EXAMPLE
    .\Set-LockScreen.ps1 -Restore
    Roll everything back to the corporate configuration.

.NOTES
    Run elevated. The script self-elevates if it is not.
    This changes an MDM-managed setting on a corporate device - see your IT policy.
#>

[CmdletBinding(DefaultParameterSetName = 'Apply')]
param(
    [Parameter(ParameterSetName = 'Apply')]
    [ValidateSet('Default', 'Blank', 'Spotlight', 'Image')]
    [string]$Mode = 'Default',

    [Parameter(ParameterSetName = 'Apply')]
    [string]$ImagePath,

    [Parameter(ParameterSetName = 'Apply')]
    [ValidateSet('Auto', 'WinRT', 'CSP')]
    [string]$Method = 'Auto',

    [Parameter(ParameterSetName = 'Apply')]
    [ValidatePattern('^#?[0-9A-Fa-f]{6}$')]
    [string]$BlankColor = '#000000',

    [Parameter(ParameterSetName = 'Apply')]
    [switch]$Persist,

    [Parameter(ParameterSetName = 'UnlockOnly', Mandatory)]
    [switch]$UnlockOnly,

    [Parameter(ParameterSetName = 'Restore', Mandatory)]
    [switch]$Restore,

    [Parameter(ParameterSetName = 'RemovePersist', Mandatory)]
    [switch]$RemovePersist
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

#region ---------------------------------------------------------------- constants

$PolicyKey    = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization'
$CspKey       = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP'
$CdmKey       = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
$WorkRoot     = Join-Path $env:ProgramData 'LockScreenTool'
$BackupDir    = Join-Path $WorkRoot 'backups'
$ImageDir     = Join-Path $WorkRoot 'images'
$TaskName     = 'LockScreenPersonalization'

# Values that pin the lock screen image. NoLockScreenCamera is intentionally absent -
# it is a security control and unrelated to which picture is displayed.
$RestrictionValues = @(
    'LockScreenImage'
    'NoChangingLockScreen'
    'LockScreenOverlaysDisabled'
    'NoLockScreenSlideshow'
)

# Windows Spotlight lock screen content, in HKCU\...\ContentDeliveryManager.
$SpotlightValues = @(
    'RotatingLockScreenEnabled'
    'RotatingLockScreenOverlayEnabled'
    'SubscribedContent-338387Enabled'
)

#endregion

#region ------------------------------------------------------------------ helpers

function Write-Step   { param([string]$Message) Write-Host "  -> $Message" }
function Write-Good   { param([string]$Message) Write-Host "  [ok] $Message"   -ForegroundColor Green }
function Write-Warn   { param([string]$Message) Write-Host "  [!]  $Message"   -ForegroundColor Yellow }
function Write-Head   { param([string]$Message) Write-Host "`n$Message" -ForegroundColor Cyan }

function Test-Elevated {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-SelfElevate {
    Write-Warn 'Not elevated - relaunching as administrator...'
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    foreach ($kv in $PSBoundParameters.GetEnumerator()) {
        if ($kv.Value -is [switch]) {
            if ($kv.Value.IsPresent) { $argList += "-$($kv.Key)" }
        }
        else { $argList += @("-$($kv.Key)", "`"$($kv.Value)`"") }
    }
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argList
    exit 0
}

function Get-KeySnapshot {
    <# Returns an ordered hashtable of every value under a registry key, or $null. #>
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    $snapshot = [ordered]@{}
    $key = Get-Item $Path
    foreach ($name in $key.GetValueNames()) {
        $snapshot[$name] = @{
            Data = $key.GetValue($name, $null, 'DoNotExpandEnvironmentNames')
            Type = $key.GetValueKind($name).ToString()
        }
    }
    return $snapshot
}

function Save-Backup {
    <# Snapshots all three keys to timestamped JSON and updates the 'latest' pointer. #>
    if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null }

    $backup = [ordered]@{
        TimestampUtc = (Get-Date).ToUniversalTime().ToString('o')
        User         = "$env:USERDOMAIN\$env:USERNAME"
        Policy       = Get-KeySnapshot $PolicyKey
        Csp          = Get-KeySnapshot $CspKey
        Cdm          = Get-KeySnapshot $CdmKey
    }

    $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $file  = Join-Path $BackupDir "lockscreen-$stamp.json"
    $json  = $backup | ConvertTo-Json -Depth 6
    [System.IO.File]::WriteAllText($file, $json, [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText((Join-Path $BackupDir 'latest.json'), $json, [System.Text.UTF8Encoding]::new($false))

    Write-Good "Backup written: $file"
    return $file
}

function Restore-Backup {
    $latest = Join-Path $BackupDir 'latest.json'
    if (-not (Test-Path $latest)) {
        throw "No backup found at $latest - nothing to restore."
    }

    $backup = Get-Content $latest -Raw | ConvertFrom-Json
    Write-Step "Restoring snapshot taken $($backup.TimestampUtc) by $($backup.User)"

    foreach ($pair in @(@{ Key = $PolicyKey; Data = $backup.Policy },
                        @{ Key = $CspKey;    Data = $backup.Csp },
                        @{ Key = $CdmKey;    Data = $backup.Cdm })) {

        if ($null -eq $pair.Data) {
            # Key did not exist when the backup was taken - remove it if we created it.
            if ($pair.Key -ne $CdmKey -and (Test-Path $pair.Key)) {
                Remove-Item $pair.Key -Recurse -Force
                Write-Step "Removed $($pair.Key) (absent in backup)"
            }
            continue
        }

        if (-not (Test-Path $pair.Key)) { New-Item -Path $pair.Key -Force | Out-Null }
        foreach ($name in $pair.Data.PSObject.Properties.Name) {
            $entry = $pair.Data.$name
            New-ItemProperty -Path $pair.Key -Name $name -Value $entry.Data `
                             -PropertyType $entry.Type -Force | Out-Null
        }
        Write-Good "Restored $($pair.Key)"
    }
}

function Remove-Restrictions {
    <# Deletes the image-pinning policy values. Leaves other values untouched. #>
    $removed = @()

    if (Test-Path $PolicyKey) {
        foreach ($name in $RestrictionValues) {
            $existing = Get-ItemProperty -Path $PolicyKey -Name $name -ErrorAction SilentlyContinue
            if ($existing) {
                Remove-ItemProperty -Path $PolicyKey -Name $name -Force
                $removed += $name
            }
        }
    }

    if ($removed.Count) {
        Write-Good "Cleared policy values: $($removed -join ', ')"
    }
    else {
        Write-Step 'No policy restrictions were present.'
    }

    # PersonalizationCSP pins the image device-wide and re-greys the Settings UI.
    if (Test-Path $CspKey) {
        Remove-Item $CspKey -Recurse -Force
        Write-Good 'Cleared PersonalizationCSP key.'
    }
}

function Set-Spotlight {
    param([bool]$Enabled)
    if (-not (Test-Path $CdmKey)) { New-Item -Path $CdmKey -Force | Out-Null }
    $data = if ($Enabled) { 1 } else { 0 }
    foreach ($name in $SpotlightValues) {
        New-ItemProperty -Path $CdmKey -Name $name -Value $data -PropertyType DWord -Force | Out-Null
    }
    Write-Good ("Windows Spotlight " + $(if ($Enabled) { 'enabled' } else { 'disabled' }) + '.')
}

function Get-PrimaryResolution {
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        if ($b.Width -gt 0 -and $b.Height -gt 0) { return @($b.Width, $b.Height) }
    }
    catch { }
    return @(3840, 2160)
}

function New-BlankImage {
    <# Generates a solid-colour JPEG sized to the primary display. #>
    param([string]$HexColor, [string]$Destination)

    Add-Type -AssemblyName System.Drawing
    $hex = $HexColor.TrimStart('#')
    $color = [System.Drawing.Color]::FromArgb(
        255,
        [Convert]::ToInt32($hex.Substring(0, 2), 16),
        [Convert]::ToInt32($hex.Substring(2, 2), 16),
        [Convert]::ToInt32($hex.Substring(4, 2), 16))

    $res = Get-PrimaryResolution
    $bmp = New-Object System.Drawing.Bitmap($res[0], $res[1])
    try {
        $gfx = [System.Drawing.Graphics]::FromImage($bmp)
        try { $gfx.Clear($color) } finally { $gfx.Dispose() }
        $bmp.Save($Destination, [System.Drawing.Imaging.ImageFormat]::Jpeg)
    }
    finally { $bmp.Dispose() }

    Write-Good "Generated $($res[0])x$($res[1]) $HexColor image."
    return $Destination
}

function Get-StockImage {
    <# Picks a stock Windows lock screen image, largest first. #>
    $candidates = @(
        'C:\Windows\Web\Screen\img100.jpg'
        'C:\Windows\Web\Screen\img101.jpg'
        'C:\Windows\Web\Screen\img102.jpg'
        'C:\Windows\Web\Wallpaper\Windows\img0.jpg'
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    throw 'No stock Windows lock screen image found.'
}

function Copy-ToWorkingDir {
    <# Copies the source image somewhere stable so the lock screen cannot break. #>
    param([string]$Source)
    if (-not (Test-Path $ImageDir)) { New-Item -ItemType Directory -Path $ImageDir -Force | Out-Null }
    $dest = Join-Path $ImageDir ('lockscreen' + [System.IO.Path]::GetExtension($Source))
    Get-ChildItem $ImageDir -Filter 'lockscreen.*' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -ne $dest } | Remove-Item -Force -ErrorAction SilentlyContinue
    Copy-Item -LiteralPath $Source -Destination $dest -Force

    # Everyone needs read access - the lock screen is rendered before sign-in.
    $acl = Get-Acl $dest
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        'BUILTIN\Users', 'Read', 'Allow')
    $acl.SetAccessRule($rule)
    Set-Acl -Path $dest -AclObject $acl

    return $dest
}

function Set-LockScreenViaWinRT {
    <# Per-user WinRT API. Leaves Settings > Personalization > Lock screen editable. #>
    param([string]$Path)

    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    [Windows.System.UserProfile.LockScreen, Windows.System.UserProfile, ContentType = WindowsRuntime] | Out-Null
    [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime] | Out-Null

    $methods = [System.WindowsRuntimeSystemExtensions].GetMethods()

    $asTaskOp = $methods | Where-Object {
        $_.Name -eq 'AsTask' -and $_.IsGenericMethodDefinition -and
        $_.GetParameters().Count -eq 1 -and
        $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
    } | Select-Object -First 1

    $asTaskAction = $methods | Where-Object {
        $_.Name -eq 'AsTask' -and -not $_.IsGenericMethodDefinition -and
        $_.GetParameters().Count -eq 1 -and
        $_.GetParameters()[0].ParameterType.FullName -eq 'Windows.Foundation.IAsyncAction'
    } | Select-Object -First 1

    if (-not $asTaskOp -or -not $asTaskAction) { throw 'WinRT async bridge unavailable.' }

    # StorageFile.GetFileFromPathAsync -> IAsyncOperation<StorageFile>
    $op   = [Windows.Storage.StorageFile]::GetFileFromPathAsync($Path)
    $task = $asTaskOp.MakeGenericMethod([Windows.Storage.StorageFile]).Invoke($null, @($op))
    $task.Wait(20000) | Out-Null
    if ($task.IsFaulted) { throw $task.Exception.GetBaseException() }
    $file = $task.Result

    # LockScreen.SetImageFileAsync -> IAsyncAction
    $action     = [Windows.System.UserProfile.LockScreen]::SetImageFileAsync($file)
    $actionTask = $asTaskAction.Invoke($null, @($action))
    $actionTask.Wait(20000) | Out-Null
    if ($actionTask.IsFaulted) { throw $actionTask.Exception.GetBaseException() }
}

function Set-LockScreenViaCsp {
    <# Device-wide fallback. Reliable, but re-greys the Settings UI. #>
    param([string]$Path)
    if (-not (Test-Path $CspKey)) { New-Item -Path $CspKey -Force | Out-Null }
    New-ItemProperty -Path $CspKey -Name 'LockScreenImagePath'   -Value $Path -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $CspKey -Name 'LockScreenImageUrl'    -Value $Path -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $CspKey -Name 'LockScreenImageStatus' -Value 1     -PropertyType DWord  -Force | Out-Null
}

function Register-PersistTask {
    param([string]$ScriptPath, [string[]]$Arguments)
    $argLine = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" {1}' -f $ScriptPath, ($Arguments -join ' ')
    $action  = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argLine
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $princ   = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -RunLevel Highest
    $set     = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
                           -Principal $princ -Settings $set -Force | Out-Null
    Write-Good "Scheduled task '$TaskName' registered (runs at logon)."
}

function Unregister-PersistTask {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Good "Scheduled task '$TaskName' removed."
    }
    else { Write-Step "No scheduled task '$TaskName' present." }
}

#endregion

#region --------------------------------------------------------------------- main

if (-not (Test-Elevated)) { Invoke-SelfElevate }

Write-Host "`n=== Windows Lock Screen Policy Tool ===" -ForegroundColor White

switch ($PSCmdlet.ParameterSetName) {

    'RemovePersist' {
        Unregister-PersistTask
        break
    }

    'Restore' {
        Write-Head 'Restoring corporate configuration'
        Restore-Backup
        Write-Head 'Done. Sign out and back in for the lock screen to revert.'
        break
    }

    'UnlockOnly' {
        Write-Head 'Backing up current state'
        Save-Backup | Out-Null

        Write-Head 'Removing policy restrictions'
        Remove-Restrictions

        Write-Head 'Done.'
        Write-Host '  Settings > Personalization > Lock screen is now editable.'
        break
    }

    'Apply' {
        if ($PSBoundParameters.ContainsKey('ImagePath') -and $ImagePath) { $Mode = 'Image' }

        Write-Head 'Backing up current state'
        Save-Backup | Out-Null

        Write-Head 'Removing policy restrictions'
        Remove-Restrictions

        Write-Head "Applying mode: $Mode"

        if ($Mode -eq 'Spotlight') {
            Set-Spotlight -Enabled $true
            Write-Head 'Done. Windows Spotlight will fetch a new image shortly.'
            break
        }

        # Spotlight overrides any fixed image, so it must be off first.
        Set-Spotlight -Enabled $false

        if (-not (Test-Path $ImageDir)) { New-Item -ItemType Directory -Path $ImageDir -Force | Out-Null }

        switch ($Mode) {
            'Blank' {
                $target = New-BlankImage -HexColor $BlankColor -Destination (Join-Path $ImageDir 'lockscreen.jpg')
            }
            'Default' {
                $stock  = Get-StockImage
                Write-Step "Using stock image: $stock"
                $target = Copy-ToWorkingDir -Source $stock
            }
            'Image' {
                if (-not (Test-Path -LiteralPath $ImagePath)) { throw "Image not found: $ImagePath" }
                $ext = [System.IO.Path]::GetExtension($ImagePath).ToLowerInvariant()
                if ($ext -notin '.jpg', '.jpeg', '.png', '.bmp') {
                    throw "Unsupported image type '$ext'. Use .jpg, .jpeg, .png or .bmp."
                }
                $resolved = (Resolve-Path -LiteralPath $ImagePath).Path
                Write-Step "Using image: $resolved"
                $target = Copy-ToWorkingDir -Source $resolved
            }
        }

        Write-Step "Staged at: $target"

        $applied = $null
        if ($Method -in 'Auto', 'WinRT') {
            try {
                Set-LockScreenViaWinRT -Path $target
                $applied = 'WinRT (per-user; Settings stays editable)'
            }
            catch {
                if ($Method -eq 'WinRT') { throw }
                Write-Warn "WinRT API failed: $($_.Exception.Message)"
                Write-Step 'Falling back to PersonalizationCSP...'
            }
        }

        if (-not $applied) {
            Set-LockScreenViaCsp -Path $target
            $applied = 'PersonalizationCSP (device-wide; Settings UI will be greyed out)'
        }

        Write-Good "Lock screen applied via $applied"

        if ($Persist) { Register-PersistTask -ScriptPath $PSCommandPath -Arguments @("-Mode $Mode") }

        Write-Head 'Done.'
        Write-Host '  Press Win+L to check. If the old image persists, sign out and back in'
        Write-Host '  (Windows caches the pre-sign-in lock screen render).'
        Write-Host "  Roll back at any time with:  .\Set-LockScreen.ps1 -Restore"
        break
    }
}

Write-Host ''
#endregion
