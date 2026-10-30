; SPDX-License-Identifier: GPL-2.0-or-later
; Copyright (C) 2026 JimmeYoumu
; 托盘与窗口管理。保留原有窗口定位逻辑。
global WT := {version: "0.1.0", windows: Map(), keys: [], bindings: Map(), nextKeyId: 8192,
    gui: 0, list: 0, settings: 0, recorder: 0, warnings: "", summary: 0, snapshot: "",
    recoveryBlocked: false, lastError: "", hooksPaused: false,
    ini: A_ScriptDir "\WindowTool.ini", journal: A_ScriptDir "\WindowTool.hidden",
    log: A_ScriptDir "\WindowTool.log", prop: "Kirara.WindowTool.Hidden.v1",
    title: "Kirara.WindowTool.Manager.v1", mutex: 0, retry: 0, serial: 0}
#Include Hotkeys.ahk

InitManager() {
    global WT, WT_TEST
    namespace := WT_TEST ? "Kirara.WindowTool.Test.v1" : "Kirara.WindowTool.v1"
    WT.title := namespace ".Manager"
    ; 二次启动只打开已有实例的管理界面，不替换持有隐藏窗口的实例。
    WT.openMsg := DllCall("RegisterWindowMessage", "Str", namespace ".Open", "UInt")
    DetectHiddenWindows(true)
    SetTitleMatchMode(3)
    ; 先走窗口消息，普通权限的第二次启动无需打开管理员实例的互斥体。
    if OpenExistingManager()
        ExitApp()
    WT.mutex := DllCall("CreateMutex", "Ptr", 0, "Int", false,
        "Str", "Local\" namespace, "Ptr")
    alreadyRunning := A_LastError = 183
    if !WT.mutex || alreadyRunning {
        Loop 30 {
            if OpenExistingManager()
                ExitApp()
            Sleep(100)
        }
        MsgBox("已有 WindowTool 实例，但暂时无法连接。请稍后再次打开。")
        ExitApp()
    }
    DetectHiddenWindows(true)
    WinSetTitle(WT.title, "ahk_id " A_ScriptHwnd)
    WT.taskbarMsg := DllCall("RegisterWindowMessage", "Str", "TaskbarCreated", "UInt")
    ; 仅允许两个无参数通知通过 UIPI：任务栏重建、打开管理界面。
    for msg in [WT.openMsg, WT.taskbarMsg] {
        if !DllCall("ChangeWindowMessageFilterEx", "Ptr", A_ScriptHwnd,
            "UInt", msg, "UInt", 1, "Ptr", 0)
            WTLog("消息过滤设置失败: " msg " error=" A_LastError)
    }
    OnMessage(WT.openMsg, (*) => ShowManager())
    OnMessage(WT.taskbarMsg, TaskbarRecreated)
    OnMessage(0x312, HandleHotkey)
    OnExit(ManagerExit)
    try RecoverWindows()
    catch Error as e {
        WT.warnings .= "恢复记录读取失败：" e.Message "`n"
        WT.recoveryBlocked := true
        WTLog(WT.warnings)
    }
    try StartKeys()
    catch Error as e {
        WT.warnings .= "配置读取失败：" e.Message "`n"
        StartKeys(DefaultKeys())
    }
    A_IconTip := "窗口小助手 v" WT.version
    A_TrayMenu.Delete()
    A_TrayMenu.Add("窗口管理 / 快捷键设置…", (*) => ShowManager())
    A_TrayMenu.Default := "窗口管理 / 快捷键设置…"
    A_TrayMenu.Add("快捷键设置…", ShowSettings)
    A_TrayMenu.Add("恢复最近收起的窗口", (*) => RestoreLatest())
    A_TrayMenu.Add("恢复全部窗口", (*) => RestoreAll())
    A_TrayMenu.Add()
    A_TrayMenu.Add("重新创建托盘图标", (*) => StartTrayRecovery())
    A_TrayMenu.Add("退出（恢复全部窗口）", (*) => ExitApp())
    StartTrayRecovery()
    ; 图标检查只在图标缺失时重建，不周期性闪烁已有图标。
    SetTimer(EnsureTray, 30000)
    SetTimer(MaintainWindows, 2000)
    WTLog("启动 AHK=" A_AhkVersion " admin=" A_IsAdmin " pid=" DllCall("GetCurrentProcessId"))
    if WT.warnings != ""
        ShowManager()
}

OpenExistingManager() {
    global WT
    if hwnd := WinExist(WT.title " ahk_class AutoHotkey")
        return DllCall("PostMessage", "Ptr", hwnd, "UInt", WT.openMsg, "Ptr", 0, "Ptr", 0)
    return false
}

WTLog(message) {
    global WT
    try {
        if FileExist(WT.log) && FileGetSize(WT.log) > 524288
            FileMove(WT.log, WT.log ".old", true)
        FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " " message "`n", WT.log, "UTF-8")
    }
}

TaskbarRecreated(*) {
    WTLog("收到 TaskbarCreated")
    StartTrayRecovery()
    ; 不返回非空值，让 AHK 自带的消息处理继续执行。
}

StartTrayRecovery() {
    global WT
    WT.retry := 0
    EnsureTray()
    SetTimer(RetryTray, 2000)
}

RetryTray() {
    global WT
    if EnsureTray() {
        SetTimer(RetryTray, 0)
        return
    }
    WT.retry += 1
    if WT.retry >= 15
        SetTimer(RetryTray, 0)
}

TrayExists() {
    ; 默认 AHK 托盘图标 ID=1028 (AHK_NOTIFYICON)，结构大小兼容 x86/x64。
    ident := Buffer(A_PtrSize = 8 ? 40 : 28, 0)
    NumPut("UInt", ident.Size, ident)
    NumPut("Ptr", A_ScriptHwnd, ident, A_PtrSize = 8 ? 8 : 4)
    NumPut("UInt", 1028, ident, A_PtrSize = 8 ? 16 : 8)
    rect := Buffer(16, 0)
    return DllCall("Shell32\Shell_NotifyIconGetRect", "Ptr", ident, "Ptr", rect, "Int") = 0
}

EnsureTray() {
    if TrayExists()
        return true
    ; 切换可清除 AHK 初次 NIM_ADD 失败后留下的内部状态。
    A_IconHidden := true
    A_IconHidden := false
    ok := TrayExists()
    WTLog("托盘重建 " (ok ? "成功" : "失败，等待重试"))
    return ok
}

WindowMatches(hwnd, record) {
    global WT
    return DllCall("IsWindow", "Ptr", hwnd) &&
        DllCall("GetProp", "Ptr", hwnd, "Str", WT.prop, "Ptr") = record.token
}

SaveJournal() {
    global WT
    if WT.recoveryBlocked
        throw Error("恢复记录尚未成功读取，为保护原记录，暂不允许收起新窗口。")
    content := ""
    for hwnd, record in WT.windows
        content .= hwnd "|" record.token "`n"
    ; 原子替换；写入失败时不隐藏新的窗口。
    file := FileOpen(WT.journal ".tmp", "w", "UTF-8")
    if !file
        throw Error("无法写入隐藏窗口恢复记录。")
    try {
        if file.Write(content) != StrLen(content) || !DllCall("FlushFileBuffers", "Ptr", file.Handle)
            throw Error("隐藏窗口恢复记录未能完整写入。")
    } finally {
        file.Close()
    }
    FileMove(WT.journal ".tmp", WT.journal, true)
}

RecoverWindows() {
    global WT
    if !FileExist(WT.journal)
        return
    Loop Parse FileRead(WT.journal, "UTF-8"), "`n", "`r" {
        if Trim(A_LoopField) = ""
            continue
        fields := StrSplit(A_LoopField, "|")
        if fields.Length != 2 || !IsInteger(fields[1]) || !IsInteger(fields[2])
            || Integer(fields[1]) <= 0 || Integer(fields[2]) <= 0 || Integer(fields[2]) > 0x7FFFFFFF
            throw Error("隐藏窗口恢复记录格式损坏，请保留原文件并检查。")
        hwnd := Integer(fields[1]), record := {token: Integer(fields[2]), title: "上次收起的窗口", order: ++WT.serial}
        if WindowMatches(hwnd, record)
            WT.windows[hwnd] := record
    }
    RestoreAll(false)
}

HideWindow(hwnd, notify := true) {
    global WT
    previousCritical := A_IsCritical
    Critical("On")
    try {
        if !hwnd || hwnd = A_ScriptHwnd || WT.windows.Has(hwnd)
            return false
        if WT.recoveryBlocked
            throw Error("恢复记录读取失败，暂不允许收起新窗口。请保留恢复记录并检查日志。")
        target := "ahk_id " hwnd
        if WinGetPID(target) = DllCall("GetCurrentProcessId")
            return false
        className := WinGetClass(target)
        if className = "Progman" || className = "WorkerW" || InStr(className, "Shell_") = 1
            return false
        if !DllCall("IsWindowVisible", "Ptr", hwnd)
            || DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr") != hwnd
            return false
        ; 新窗口属性会随窗口销毁自动消失，避免句柄重用后误恢复其他窗口。
        record := {title: WinGetTitle(target), token: Random(1, 0x7FFFFFFF), order: ++WT.serial}
        if !DllCall("SetProp", "Ptr", hwnd, "Str", WT.prop, "Ptr", record.token)
            throw Error("无法操作这个窗口，请确认 WindowTool 与目标程序的权限。")
        WT.windows[hwnd] := record
        try SaveJournal()
        catch Error as e {
            WT.windows.Delete(hwnd)
            DllCall("RemoveProp", "Ptr", hwnd, "Str", WT.prop, "Ptr")
            throw e
        }
        WinHide(target)
        if DllCall("IsWindowVisible", "Ptr", hwnd)
            throw Error("目标窗口拒绝隐藏。")
        RefreshManager()
        return true
    } catch Error as e {
        WT.lastError := e.Message
        WTLog("收起失败: " e.Message)
        if notify
            MsgBox(e.Message)
        return false
    } finally {
        Critical(previousCritical)
    }
}

RestoreWindow(hwnd, activate := true) {
    global WT
    previousCritical := A_IsCritical
    Critical("On")
    try {
    if !WT.windows.Has(hwnd)
        return false
    record := WT.windows[hwnd]
    if WindowMatches(hwnd, record) {
        try {
            ; 批量恢复只显示窗口，不抢走正在工作的窗口焦点。
            DllCall("ShowWindow", "Ptr", hwnd, "Int", activate ? 5 : 8)
            if !DllCall("IsWindowVisible", "Ptr", hwnd)
                return false
            DllCall("RemoveProp", "Ptr", hwnd, "Str", WT.prop, "Ptr")
            if activate {
                target := "ahk_id " hwnd
                if WinGetMinMax(target) = -1
                    WinRestore(target)
                try WinActivate(target)
            }
        } catch Error as e {
            WTLog("恢复失败: " e.Message)
            return false
        }
    }
    WT.windows.Delete(hwnd)
    try SaveJournal()
    catch Error as e
        WTLog("更新恢复记录失败: " e.Message)
    RefreshManager()
    return true
    } finally {
        Critical(previousCritical)
    }
}

RestoreLatest() {
    global WT
    stale := [], latest := 0, order := -1
    for hwnd, record in WT.windows {
        if !WindowMatches(hwnd, record)
            stale.Push(hwnd)
        else if record.order > order
            latest := hwnd, order := record.order
    }
    for hwnd in stale
        RestoreWindow(hwnd, false)
    if latest
        RestoreWindow(latest)
}

RestoreAll(activate := false) {
    global WT
    handles := []
    for hwnd in WT.windows
        handles.Push(hwnd)
    for hwnd in handles
        RestoreWindow(hwnd, activate)
}

ShowManager(*) {
    global WT
    if !WT.gui {
        WT.gui := Gui(, "窗口小助手 v" WT.version)
        WT.gui.SetFont("s10", "Microsoft YaHei UI")
        WT.gui.AddText("w580", "双击恢复窗口；托盘不可见时，也可再次启动 WindowTool 打开这里。")
        WT.list := WT.gui.AddListView("w580 r10 -Multi", ["窗口标题", "窗口句柄"])
        WT.list.ModifyCol(1, 450), WT.list.ModifyCol(2, 110)
        WT.list.OnEvent("DoubleClick", (*) => RestoreSelected())
        WT.gui.AddButton("w130", "恢复选中").OnEvent("Click", (*) => RestoreSelected())
        WT.gui.AddButton("x+10 w130", "恢复全部").OnEvent("Click", (*) => RestoreAll())
        WT.gui.AddButton("x+10 w160", "快捷键设置…").OnEvent("Click", (*) => ShowSettings())
        WT.summary := WT.gui.AddText("xm w580 r4", "")
        WT.gui.OnEvent("Close", (*) => CloseManager())
        WT.gui.OnEvent("Escape", (*) => CloseManager())
    }
    UpdateSummary()
    RefreshManager()
    WT.gui.Show()
}

RefreshManager() {
    global WT
    if !WT.list
        return
    snapshot := ""
    for hwnd, record in WT.windows
        snapshot .= hwnd "|" record.title "`n"
    if snapshot = WT.snapshot
        return
    WT.snapshot := snapshot
    selected := WT.list.GetNext()
    selectedHwnd := selected ? WT.list.GetText(selected, 2) : ""
    WT.list.Delete()
    for hwnd, record in WT.windows {
        row := WT.list.Add(, record.title = "" ? "（无标题窗口）" : record.title, hwnd)
        if hwnd "" = selectedHwnd
            WT.list.Modify(row, "Select Focus")
    }
}

RestoreSelected() {
    global WT
    if row := WT.list.GetNext() {
        if !RestoreWindow(Integer(WT.list.GetText(row, 2)))
            MsgBox("窗口暂时无法恢复，请确认目标程序与 WindowTool 的运行权限，并保留恢复记录。")
    }
}

CloseManager() {
    global WT
    if WT.settings
        CloseSettings()
    WT.gui.Hide()
}

UpdateSummary() {
    global WT
    if !WT.summary
        return
    text := "收起：" KeyLabel(WT.keys[1]) "　恢复：" KeyLabel(WT.keys[2])
        . "`n管理：" KeyLabel(WT.keys[3]) "　所有功能均可在设置中自定义。"
    if !A_IsAdmin
        text .= "`n当前未以管理员运行，部分管理员窗口无法操作。"
    if WT.warnings != ""
        text .= "`n" Trim(WT.warnings, "`n")
    WT.summary.Text := text
}

MaintainWindows() {
    global WT
    previousCritical := A_IsCritical
    Critical("On")
    try {
        stale := []
        for hwnd, record in WT.windows {
            if !WindowMatches(hwnd, record)
                stale.Push(hwnd)
            else if DllCall("IsWindowVisible", "Ptr", hwnd) {
                DllCall("RemoveProp", "Ptr", hwnd, "Str", WT.prop, "Ptr")
                stale.Push(hwnd)
            } else {
                try record.title := WinGetTitle("ahk_id " hwnd)
            }
        }
        for hwnd in stale
            WT.windows.Delete(hwnd)
        if stale.Length {
            try SaveJournal()
            catch Error as e
                WTLog("清理恢复记录失败: " e.Message)
        }
        if WT.gui && DllCall("IsWindowVisible", "Ptr", WT.gui.Hwnd)
            RefreshManager()
    } finally {
        Critical(previousCritical)
    }
}

ManagerExit(reason, code) {
    global WT
    CancelRecording()
    RestoreAll()
    ; 恢复失败时阻止普通退出，保留再次尝试的入口。
    if WT.windows.Count && reason != "Shutdown" && reason != "Logoff" {
        MsgBox("仍有窗口未能恢复，请先在管理界面恢复后再退出。")
        ShowManager()
        return 1
    }
    UnregisterKeys()
    if WT.mutex {
        DllCall("CloseHandle", "Ptr", WT.mutex)
        WT.mutex := 0
    }
}

#Include tests\SelfTest.ahk
