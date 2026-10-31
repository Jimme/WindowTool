; SPDX-License-Identifier: GPL-2.0-or-later
; Copyright (C) 2026 JimmeYoumu
#Requires AutoHotkey v2.0
#SingleInstance Off
g := Gui(, "WindowTool Test Fixture " DllCall("GetCurrentProcessId"))
g.AddText("w260", "仅用于 WindowTool 的自动验证")
g.OnEvent("Close", (*) => ExitApp())
g.Show("w320 h100 NoActivate")
OnMessage(0x8001, StallFixture)
SetTimer((*) => ExitApp(), -60000)

StallFixture(*) {
    FileOpen(A_ScriptDir "\hung-" DllCall("GetCurrentProcessId") ".ready", "w").Write("ready")
    DllCall("Sleep", "UInt", 4500)
}
