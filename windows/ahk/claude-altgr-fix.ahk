#Requires AutoHotkey v2.0
#SingleInstance Force

; ---------------------------------------------------------------------------
; Fix: AltGr-produced symbols (@, #, |, [], {} ...) don't type in the
;      Claude Code CLI because its TUI treats the Alt modifier as a keybinding.
;
; How it works: AltGr = Left Ctrl + Right Alt  ->  AHK prefix  <^>!
;      SendText() injects the character as Unicode with NO modifier held,
;      so Claude Code inserts it normally. Output is identical to the
;      normal layout, so nothing changes for you visually.
;
; Scoped to terminal windows ONLY. Globally intercepting AltGr+<n> sends the
; symbol via SendText() (a Unicode packet), which espanso's keyboard hook does
; NOT see -- that silently broke every espanso trigger ending in '#' (AltGr+3).
; Outside the terminal, AltGr now passes through natively so espanso works.
; Swiss-German layout mappings below — adjust the right-hand sides if needed.
; ---------------------------------------------------------------------------

SetTitleMatchMode("RegEx")
#HotIf WinActive("ahk_exe (WindowsTerminal|wt|warp|Code|wezterm|alacritty)\.exe")

<^>!2::SendText("@")     ; AltGr+2  -> @   (the important one)
<^>!3::SendText("#")     ; AltGr+3  -> #
<^>!7::SendText("|")     ; AltGr+7  -> |
<^>!9::SendText("]")     ; AltGr+9  -> ]
<^>!0::SendText("}")     ; AltGr+0  -> }
<^>!ü::SendText("[")     ; AltGr+ü  -> [
<^>!¨::SendText("{")     ; AltGr+¨  -> {   (key right of ü; rename if AHK errors)

; No-AltGr fallback chords (terminal-scoped too):
>^2::SendText("@")       ; Right Ctrl + 2  -> @
^+2::SendText("@")       ; Ctrl + Shift + 2 -> @  (works with either Ctrl)

#HotIf
