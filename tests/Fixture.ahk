; SPDX-License-Identifier: GPL-2.0-or-later
; Copyright (C) 2026 JimmeYoumu
#Requires AutoHotkey v2.0
#SingleInstance Off
if A_Args.Length && A_Args[1] = "--legacy"
    DllCall("SetThreadDpiAwarenessContext", "Ptr", -1, "Ptr")
else if A_Args.Length && A_Args[1] = "--per-monitor"
    DllCall("SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")
g := Gui(, "WindowTool Test Fixture " DllCall("GetCurrentProcessId"))
g.AddText("w260", "仅用于 WindowTool 的自动验证")
g.OnEvent("Close", (*) => ExitApp())
g.Show("w320 h100 NoActivate")
OnMessage(0x8001, StallFixture)
OnMessage(0x8002, ArmExitOnMove)
SetTimer((*) => ExitApp(), -60000)

StallFixture(*) {
    FileOpen(A_ScriptDir "\hung-" DllCall("GetCurrentProcessId") ".ready", "w").Write("ready")
    DllCall("Sleep", "UInt", 4500)
}

ArmExitOnMove(*) {
    OnMessage(0x46, (*) => ExitApp())
}
