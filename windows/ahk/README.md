# AHK scripts

Personal AutoHotkey v2 scripts, loaded by a single master so the systray shows
**one** tray icon instead of one per script.

## Files

| File | Purpose |
|------|---------|
| `ahk-startup.ahk` | Master launcher — `#Include`s every script into one process. Add a new script by adding an `#Include` line. |
| `claude-altgr-fix.ahk` | Types AltGr symbols (`@ # \| [] {}`) inside terminal windows, where the Claude Code TUI otherwise swallows the Alt modifier. Scoped to terminals only so it doesn't intercept AltGr globally (which silently broke espanso triggers ending in `#`). |

`ClipToFile.ahk` lives in [`../cliptofile/`](../cliptofile/) and is `#Include`d by the master too.

## Deploy

Scripts run from `C:\Admin\scripts\` (the `#Include` paths in `ahk-startup.ahk` are
absolute and point there). Copy the `.ahk` files into that folder, then run the
master once:

```powershell
& "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" "C:\Admin\scripts\ahk-startup.ahk"
```

## Autostart

A shortcut named `AHK Startup.lnk` in `shell:startup` launches the master on login:

- Target: `C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe`
- Arguments: `"C:\Admin\scripts\ahk-startup.ahk"`
