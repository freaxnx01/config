# ClipToFile

AutoHotkey v2 helper that saves clipboard text to a timestamped log file and replaces the clipboard with the file's path. Built for the coding-agent workflow: copy a long stack trace / console dump, then paste the **path** into the agent instead of the wall of text.

## Hotkeys

| Shortcut       | Action                                                    |
| -------------- | --------------------------------------------------------- |
| `Ctrl+Shift+L` | Save clipboard to file, replace clipboard with **Windows path** |
| `Ctrl+Shift+J` | Save clipboard to file, replace clipboard with **WSL path** (`/mnt/c/...`) |
| `Ctrl+Shift+O` | Open log folder in Explorer                               |

Output dir: `%TEMP%\claude-clip-logs\`. Skipped when clipboard is empty, non-text, or shorter than 50 chars.

## Install

```powershell
winget install AutoHotkey.AutoHotkey
git clone https://github.com/freaxnx01/config.git C:\Develop\Repos\config
cd C:\Develop\Repos\config\windows\cliptofile
.\Install-ClipToFile.ps1 -LaunchNow
```

The installer copies `ClipToFile.ahk` to `-InstallPath` (default `C:\Admin\scripts`) and creates a Startup-folder shortcut targeting `AutoHotkey64.exe "<path>\ClipToFile.ahk"`.

Flags: `-InstallPath <dir>`, `-NoStartup`, `-LaunchNow`.

## Update

```powershell
cd C:\Develop\Repos\config; git pull
.\windows\cliptofile\Install-ClipToFile.ps1   # re-copies the .ahk
```

Then reload the running script via tray icon → Reload Script.

## Full documentation

See the IT vault: `Tools/ClipToFile.md` (covers WSL path conversion, Ditto coexistence, customization knobs, troubleshooting).
