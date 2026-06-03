#requires -Version 7
<#
.SYNOPSIS
    Merges the shared Windows Terminal config (color schemes, appearance defaults,
    and keybindings/actions) from wt-shared.json into the local settings.json of
    every installed Windows Terminal edition (stable, Preview, Canary).

.DESCRIPTION
    Machine-independent only: schemes, profiles.defaults appearance, actions, keybindings.
    Local machine-specific profiles (WSL distros, VS dev prompts, SSH hosts, GUIDs) are
    left untouched. The merge is idempotent (upsert by name / id / keys) and a timestamped
    backup of each settings.json is written before any change.

    Prerequisite: the JetBrainsMono Nerd Font must be installed for the default font to
    resolve (family name "JetBrainsMono NFM"). See the repo's Nerd Font notes.

.EXAMPLE
    pwsh -File .\Merge-WTSettings.ps1
.EXAMPLE
    pwsh -File .\Merge-WTSettings.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$SharedFile = (Join-Path $PSScriptRoot 'wt-shared.json')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $SharedFile)) { throw "Shared config not found: $SharedFile" }
$shared = Get-Content -Raw -LiteralPath $SharedFile | ConvertFrom-Json -AsHashtable

# Upsert items into a list, matching existing entries by $key; returns a fresh array.
function Merge-List {
    param($Existing, $Incoming, [string]$Key)
    $out = [System.Collections.Generic.List[object]]::new()
    if ($Existing) { foreach ($e in $Existing) { $out.Add($e) } }
    foreach ($item in $Incoming) {
        $idx = -1
        for ($i = 0; $i -lt $out.Count; $i++) {
            if ($out[$i][$Key] -eq $item[$Key]) { $idx = $i; break }
        }
        if ($idx -ge 0) { $out[$idx] = $item } else { $out.Add($item) }
    }
    return , $out.ToArray()
}

$packages = @(
    'Microsoft.WindowsTerminal_8wekyb3d8bbwe',
    'Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe',
    'Microsoft.WindowsTerminalCanary_8wekyb3d8bbwe'
)

$touched = 0
foreach ($pkg in $packages) {
    $path = Join-Path $env:LOCALAPPDATA "Packages\$pkg\LocalState\settings.json"
    if (-not (Test-Path $path)) { continue }

    if (-not $PSCmdlet.ShouldProcess($path, 'Merge shared WT settings')) { continue }

    $stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup = "$path.bak.$stamp"
    Copy-Item -LiteralPath $path -Destination $backup -Force

    $cfg = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -AsHashtable

    # 1) color schemes (match by name)
    $cfg.schemes = Merge-List $cfg.schemes $shared.schemes 'name'

    # 2) profiles.defaults appearance
    if (-not $cfg.profiles)          { $cfg.profiles = @{} }
    if (-not $cfg.profiles.defaults) { $cfg.profiles.defaults = @{} }
    $d = $cfg.profiles.defaults
    foreach ($k in $shared.profilesDefaults.Keys) {
        if ($k -eq 'font') {
            if (-not $d.font) { $d.font = @{} }
            foreach ($fk in $shared.profilesDefaults.font.Keys) {
                $d.font[$fk] = $shared.profilesDefaults.font[$fk]
            }
        }
        else {
            $d[$k] = $shared.profilesDefaults[$k]
        }
    }

    # 3) actions (match by id) and 4) keybindings (match by keys)
    $cfg.actions     = Merge-List $cfg.actions     $shared.actions     'id'
    $cfg.keybindings = Merge-List $cfg.keybindings $shared.keybindings 'keys'

    $cfg | ConvertTo-Json -Depth 32 | Set-Content -LiteralPath $path -Encoding utf8
    Write-Host "Merged -> $path"
    Write-Host "  backup: $backup"
    $touched++
}

if ($touched -eq 0) {
    Write-Warning 'No Windows Terminal installation found (stable/Preview/Canary).'
}
else {
    Write-Host "`nDone. Open a new tab/pane for changes to take effect." -ForegroundColor Green
    Write-Host "Reminder: install the JetBrainsMono Nerd Font so 'JetBrainsMono NFM' resolves." -ForegroundColor Yellow
}
