#Requires -Version 5
<#
.SYNOPSIS
    Installs ClipToFile.ahk to a target directory and creates a startup shortcut.

.DESCRIPTION
    Copies ClipToFile.ahk (must be next to this script) into -InstallPath,
    verifies AutoHotkey v2 is installed, and creates a Startup-folder shortcut
    that launches the script via AutoHotkey64.exe on login.

.PARAMETER InstallPath
    Target directory for ClipToFile.ahk. Default: C:\Admin\scripts

.PARAMETER NoStartup
    Skip creating the autostart shortcut.

.PARAMETER LaunchNow
    Launch ClipToFile.ahk immediately after install.

.EXAMPLE
    .\Install-ClipToFile.ps1 -LaunchNow

.EXAMPLE
    .\Install-ClipToFile.ps1 -InstallPath "$env:USERPROFILE\Scripts" -LaunchNow
#>
[CmdletBinding()]
param(
    [string]$InstallPath = 'C:\Admin\scripts',
    [switch]$NoStartup,
    [switch]$LaunchNow
)

$ErrorActionPreference = 'Stop'

$src = Join-Path $PSScriptRoot 'ClipToFile.ahk'
if (-not (Test-Path -LiteralPath $src)) {
    throw "ClipToFile.ahk not found next to this script ($src)."
}

$ahkExe = 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe'
if (-not (Test-Path -LiteralPath $ahkExe)) {
    Write-Warning "AutoHotkey v2 not found at: $ahkExe"
    Write-Warning "Install with:  winget install AutoHotkey.AutoHotkey"
}

if (-not (Test-Path -LiteralPath $InstallPath)) {
    New-Item -Path $InstallPath -ItemType Directory -Force | Out-Null
}
$dst = Join-Path $InstallPath 'ClipToFile.ahk'
Copy-Item -LiteralPath $src -Destination $dst -Force
Write-Host "Copied ClipToFile.ahk -> $dst"

if (-not $NoStartup) {
    $startup = [Environment]::GetFolderPath('Startup')
    $lnkPath = Join-Path $startup 'ClipToFile.lnk'
    $wsh = New-Object -ComObject WScript.Shell
    $sc  = $wsh.CreateShortcut($lnkPath)
    if (Test-Path -LiteralPath $ahkExe) {
        $sc.TargetPath = $ahkExe
        $sc.Arguments  = "`"$dst`""
    } else {
        $sc.TargetPath = $dst
    }
    $sc.WorkingDirectory = $InstallPath
    $sc.Description = 'Clip-to-File: save clipboard to log file via Ctrl+Shift+L'
    $sc.Save()
    Write-Host "Startup shortcut -> $lnkPath"
}

if ($LaunchNow) {
    if (Test-Path -LiteralPath $ahkExe) {
        Start-Process -FilePath $ahkExe -ArgumentList "`"$dst`""
        Write-Host "Launched."
    } else {
        Write-Warning "Skipped launch: AutoHotkey v2 not installed."
    }
}

Write-Host ""
Write-Host "Hotkeys:"
Write-Host "  Ctrl+Shift+L  save clipboard to file, replace clipboard with Windows path"
Write-Host "  Ctrl+Shift+W  replace clipboard with WSL path of last saved file"
Write-Host "  Ctrl+Shift+P  re-copy Windows path of last saved file"
Write-Host "  Ctrl+Shift+O  open log folder in Explorer"
