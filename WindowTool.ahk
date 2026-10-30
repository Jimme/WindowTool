; SPDX-License-Identifier: GPL-2.0-or-later
; Copyright (C) 2026 JimmeYoumu
; WindowTool is free software: you can redistribute it and/or modify it
; under the terms of the GNU General Public License as published by the
; Free Software Foundation, either version 2 of the License, or
; (at your option) any later version.
;
; This program is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See LICENSE.
#Requires AutoHotkey v2.0
#SingleInstance Off
;@Ahk2Exe-SetVersion 0.1.0
;@Ahk2Exe-SetDescription 窗口小助手

WT_TEST := A_Args.Length && (A_Args[1] = "--test" || A_Args[1] = "--probe"
    || A_Args[1] = "--preview" || A_Args[1] = "--crash-host")
#Include TrayManager.ahk
; 窗口小助手 v0.1.0
; Win+F12：水平、垂直同时居中；重复按下仍保持居中。
; Win+F11：上 / 中 / 下循环，水平不动。
; Win+F10：左 / 中 / 右循环，垂直不动。
; 使用所在显示器的工作区，避开任务栏；按可见边框对齐。
; 最大化、最小化及桌面/任务栏窗口不处理，不改变窗口大小。

VERT_POSITIONS := [0, 0.5, 1]
HORIZ_POSITIONS := [0, 0.5, 1]
SNAP_TOLERANCE := 50

if WT_TEST && A_Args[1] = "--test" {
    RunSelfTests()
    ExitApp()
}
if WT_TEST && A_Args[1] = "--preview" {
    PreviewTools()
    return
}
if WT_TEST && A_Args[1] = "--crash-host" {
    RunCrashHost(Integer(A_Args[2]))
    return
}
InitManager()
Persistent()

; 选取与窗口重叠面积最大的显示器；离屏时选最近的显示器。
GetWorkArea(hwnd, &L, &T, &R, &B) {
    monitor := DllCall("User32\MonitorFromWindow", "Ptr", hwnd, "UInt", 2, "Ptr")
    info := Buffer(40, 0)
    NumPut("UInt", info.Size, info)
    if !monitor || !DllCall("User32\GetMonitorInfoW", "Ptr", monitor, "Ptr", info)
        return false
    L := NumGet(info, 20, "Int"), T := NumGet(info, 24, "Int")
    R := NumGet(info, 28, "Int"), B := NumGet(info, 32, "Int")
    return true
}

; WinGetPos 包含不可见的调整大小边框，DWM 提供实际可见边框。
; 返回相对 WinMove 坐标的偏移，保留不参与调整的轴。
GetVisibleRect(hwnd, &x, &y, &w, &h, &offsetX, &offsetY) {
    WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
    offsetX := 0, offsetY := 0
    rect := Buffer(16, 0)
    if DllCall("Dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 9,
        "Ptr", rect, "UInt", rect.Size, "Int") != 0
        return
    left := NumGet(rect, 0, "Int"), top := NumGet(rect, 4, "Int")
    width := NumGet(rect, 8, "Int") - left
    height := NumGet(rect, 12, "Int") - top
    if width <= 0 || height <= 0
        return
    offsetX := left - x, offsetY := top - y
    x := left, y := top, w := width, h := height
}

; 未接近任一档位时先居中；否则移动到最近档位的下一档。
NextRatio(position, origin, usable, positions) {
    global SNAP_TOLERANCE
    if usable <= 0
        return 0
    best := 1
    bestDist := Abs(position - (origin + Round(usable * positions[1])))
    Loop positions.Length - 1 {
        i := A_Index + 1
        distance := Abs(position - (origin + Round(usable * positions[i])))
        if distance < bestDist
            best := i, bestDist := distance
    }
    return bestDist > SNAP_TOLERANCE ? 0.5 : positions[Mod(best, positions.Length) + 1]
}

PositionWindow(hwnd, mode) {
    global VERT_POSITIONS, HORIZ_POSITIONS
    if !hwnd
        return
    ; 混合 DPI 显示器下统一使用物理像素，避免与 DWM 的坐标混用。
    previousDpi := DllCall("User32\SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")
    try {
        target := "ahk_id " hwnd
        className := WinGetClass(target)
        if className = "Progman" || className = "WorkerW"
            || className = "Shell_TrayWnd" || className = "Shell_SecondaryTrayWnd"
            return
        if WinGetMinMax(target) != 0 || !GetWorkArea(hwnd, &L, &T, &R, &B)
            return
        GetVisibleRect(hwnd, &x, &y, &w, &h, &offsetX, &offsetY)
        hUsable := Max(0, R - L - w)
        vUsable := Max(0, B - T - h)
        nx := x, ny := y
        switch mode {
            case "center":
                nx := L + Round(hUsable / 2)
                ny := T + Round(vUsable / 2)
            case "vertical":
                ny := T + Round(vUsable * NextRatio(y, T, vUsable, VERT_POSITIONS))
            case "horizontal":
                nx := L + Round(hUsable * NextRatio(x, L, hUsable, HORIZ_POSITIONS))
            default:
                return
        }
        WinMove(nx - offsetX, ny - offsetY, , , target)
    } catch TargetError {
        ; 窗口可能在读取或移动前已经关闭。
        return
    } catch OSError {
        ; 无法操作的窗口不弹出错误对话框。
        return
    } finally {
        if previousDpi
            DllCall("User32\SetThreadDpiAwarenessContext", "Ptr", previousDpi, "Ptr")
    }
}
