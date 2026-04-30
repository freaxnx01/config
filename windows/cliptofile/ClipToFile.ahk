#Requires AutoHotkey v2.0
#SingleInstance Force

LogDir   := A_Temp "\claude-clip-logs"
LastPath := ""

if !DirExist(LogDir)
    DirCreate(LogDir)

; --- helpers -----------------------------------------------------------------

SaveClipboardToLog() {
    global LogDir, LastPath

    text := A_Clipboard
    if (Trim(text) = "") {
        TrayTip("Clip-to-File", "Clipboard is empty or non-text.", 0x2)
        return ""
    }
    if (StrLen(text) < 50) {
        TrayTip("Clip-to-File", "Clipboard too short (" StrLen(text) " chars). Skipped.", 0x2)
        return ""
    }

    stamp    := FormatTime(, "yyyyMMdd-HHmmss")
    fullPath := LogDir "\console-" stamp ".log"

    try {
        f := FileOpen(fullPath, "w", "UTF-8-RAW")
        f.Write(text)
        f.Close()
    } catch as e {
        TrayTip("Clip-to-File", "Write failed: " e.Message, 0x3)
        return ""
    }

    LastPath := fullPath
    return fullPath
}

WinToWslPath(p) {
    drive := StrLower(SubStr(p, 1, 1))
    rest  := StrReplace(SubStr(p, 3), "\", "/")
    return "/mnt/" drive rest
}

; --- hotkeys -----------------------------------------------------------------

; Save clipboard to file, replace clipboard with Windows path (one-shot)
^+l:: {
    full := SaveClipboardToLog()
    if (full = "")
        return
    A_Clipboard := full
    kb := Round(FileGetSize(full) / 1024, 1)
    TrayTip("Clip-to-File saved (" kb " KB)", "Win path on clipboard:`n" full, 0x1)
}

; Save clipboard to file, replace clipboard with WSL path (one-shot)
^+j:: {
    full := SaveClipboardToLog()
    if (full = "")
        return
    wsl := WinToWslPath(full)
    A_Clipboard := wsl
    kb := Round(FileGetSize(full) / 1024, 1)
    TrayTip("Clip-to-File saved (" kb " KB)", "WSL path on clipboard:`n" wsl, 0x1)
}

; Open log folder
^+o:: {
    global LogDir
    Run('explorer.exe "' LogDir '"')
}
