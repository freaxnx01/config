#Requires AutoHotkey v2.0
#SingleInstance Force

; ---------------------------------------------------------------------------
; Master launcher: loads all personal AHK scripts in ONE process, so there is
; a single tray (H) icon instead of one per script.
;
; To add another script: drop a "#Include" line below.
; Order note: scripts with top-level init code (e.g. ClipToFile sets LogDir
; and creates its log dir) must be included BEFORE the first hotkey is parsed
; in the auto-execute flow, so include them first. Set any global options the
; included files rely on (e.g. title match mode) up here.
; ---------------------------------------------------------------------------

SetTitleMatchMode("RegEx")   ; needed by claude-altgr-fix's #HotIf WinActive regex

#Include "C:\Admin\scripts\ClipToFile.ahk"
#Include "C:\Admin\scripts\claude-altgr-fix.ahk"
