<#
    Thin bootstrap: clone this repo next to wherever you run it, then hand over
    to base-box.ps1 (which installs Boxstarter itself).

    Run from an elevated PowerShell:

        Set-ExecutionPolicy Unrestricted -Force
        . { iwr -useb https://raw.githubusercontent.com/neutmute/nm-boxstarter/master/bootstrap.ps1 } | iex
#>

$repoUrl = 'https://github.com/neutmute/nm-boxstarter.git'
$target = Join-Path (Get-Location).Path 'nm-boxstarter'

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "git not found, installing..."
    winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
}

if (Test-Path (Join-Path $target '.git')) {
    Write-Host "Updating existing clone at $target"
    git -C $target pull
} else {
    Write-Host "Cloning $repoUrl to $target"
    git clone $repoUrl $target
}

Write-Host ""
Write-Host "Done. Now run, from an elevated PowerShell:"
Write-Host ""
Write-Host "    cd $target"
Write-Host "    .\base-box.ps1"
Write-Host ""
Write-Host "Run '.\base-box.ps1 --help' for options (--list, --reset, single concerns)."
Write-Host ""
