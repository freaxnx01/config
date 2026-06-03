# Windows Terminal — shared config

Portable Windows Terminal settings shared across machines: **color schemes, the
appearance defaults (scheme + font), and keybindings/actions**. Deliberately *not*
the machine-specific profile list (WSL distros, VS dev prompts, SSH hosts, GUIDs) —
those stay local to each machine.

## Files

| File | What it holds |
|------|---------------|
| `wt-shared.json` | The portable fragment: `schemes`, `profilesDefaults`, `actions`, `keybindings`. |
| `Merge-WTSettings.ps1` | Idempotent merge into each installed WT edition's `settings.json` (backs up first). |

### What's in `wt-shared.json`

- **Schemes:** `Midnight Indigo Solarized` (active default), `Midnight Indigo 000435`,
  `Solarized Dark Higher Contrast` (with the legible lifted `brightBlack` tweak).
- **Defaults:** `colorScheme = Midnight Indigo Solarized`, `font.face = JetBrainsMono NFM`,
  `adjustIndistinguishableColors = always`.
- **Keybindings/actions:** `ctrl+c` copy (multi-line), `ctrl+v` paste, `ctrl+shift+f` find,
  `alt+shift+d` split pane (auto/duplicate).

## Apply on a new machine

```powershell
# from this folder, in PowerShell 7+
pwsh -File .\Merge-WTSettings.ps1          # merge into stable / Preview / Canary
pwsh -File .\Merge-WTSettings.ps1 -WhatIf  # preview which files would change
```

The script:

- Targets every installed WT edition (stable, Preview, Canary) under
  `%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal*\LocalState\settings.json`.
- Writes a timestamped backup (`settings.json.bak.<stamp>`) before each change.
- **Upserts** — schemes match by `name`, actions by `id`, keybindings by `keys` — so
  re-running never creates duplicates and leaves your local profiles intact.
- Open a new tab/pane afterward for changes to take effect.

## Prerequisite — font

The default font is **`JetBrainsMono NFM`** (JetBrainsMono Nerd Font, Mono variant).
Install it first or the face won't resolve (WT falls back to Consolas). Quick per-user
install (no admin):

```powershell
$tmp = Join-Path $env:TEMP 'jbm-nf'
Invoke-WebRequest 'https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip' -OutFile "$tmp.zip"
Expand-Archive "$tmp.zip" $tmp -Force
$dir = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"; $reg = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
Get-ChildItem $tmp -Recurse -Include *.ttf | ForEach-Object {
    Copy-Item $_.FullName $dir -Force
    New-ItemProperty $reg -Name "$($_.BaseName) (TrueType)" -Value (Join-Path $dir $_.Name) -PropertyType String -Force | Out-Null
}
Remove-Item "$tmp.zip", $tmp -Recurse -Force
```

## Updating the shared config

Edit it in WT on any machine, then copy the changed pieces back into `wt-shared.json`
and commit. Only put **machine-independent** values here.
