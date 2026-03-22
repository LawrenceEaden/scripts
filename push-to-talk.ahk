#Requires AutoHotkey v2.0

; Push-to-talk for Windows Voice Typing
; Hold Copilot key (remapped to Win+Shift+F3) to dictate, release to stop

F12::
{
    Send "#h"        ; open voice typing and start mic
    Sleep 500        ; wait for mic to be ready
    KeyWait "F12"    ; wait until key is released
    Sleep 200
    Send "#h"        ; stop dictation and dismiss toolbar
}
