; SPDX-License-Identifier: GPL-2.0-or-later
; Copyright (C) 2026 JimmeYoumu
; 托盘与窗口管理。保留原有窗口定位逻辑。
global WT := {version: "0.1.2", windows: Map(), keys: [], configuredKeys: [], keyErrors: Map(), bindings: Map(), nextKeyId: 8192,
    gui: 0, list: 0, settings: 0, recorder: 0, warnings: "", summary: 0, snapshot: "",
    recoveryBlocked: false, lastError: "", hooksPaused: false, pendingRestore: Map(),
    showProcess: true, showTime: true, icons: Map(), imageList: 0, trayReady: false,
    ini: A_ScriptDir "\WindowTool.ini", journal: A_ScriptDir "\WindowTool.hidden",
    log: A_ScriptDir "\WindowTool.log", prop: "Kirara.WindowTool.Hidden.v1",
    title: "Kirara.WindowTool.Manager.v1", mutex: 0, retry: 0, serial: 0}
#Include Hotkeys.ahk
#Include Startup.ahk
#Include Settings.ahk

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
    A_TrayMenu.Add("窗口管理…", (*) => ShowManager())
    A_TrayMenu.Default := "窗口管理…"
    A_TrayMenu.Add("恢复最近收起的窗口", (*) => RestoreLatest())
    A_TrayMenu.Add("恢复全部窗口", (*) => RestoreAll())
    A_TrayMenu.Add()
    A_TrayMenu.Add("设置…", ShowSettings)
    A_TrayMenu.Add()
    A_TrayMenu.Add("退出（恢复全部窗口）", (*) => ExitApp())
    WT.trayReady := true
    UpdateTrayActions()
    try {
        WT.showProcess := IniRead(WT.ini, "Interface", "ShowProcess", 1) = 1
        WT.showTime := IniRead(WT.ini, "Interface", "ShowTime", 1) = 1
    }
    StartTrayRecovery()
    ; 图标检查只在图标缺失时重建，不周期性闪烁已有图标。
    SetTimer(EnsureTray, 30000)
    SetTimer(MaintainWindows, 2000)
    WTLog("启动 AHK=" A_AhkVersion " admin=" A_IsAdmin " pid=" DllCall("GetCurrentProcessId"))
    if WT.warnings != "" || WT.keyErrors.Count
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
        record := {title: WinGetTitle(target), token: Random(1, 0x7FFFFFFF), order: ++WT.serial,
            time: FormatTime(, "HH:mm:ss"), process: "", path: ""}
        try record.process := WinGetProcessName(target)
        try record.path := WinGetProcessPath(target)
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
    if !WT.windows.Has(hwnd)
        return false
    record := WT.windows[hwnd]
    if !WindowMatches(hwnd, record) {
        FinishRestore(hwnd)
        return true
    }
    if WT.pendingRestore.Has(hwnd)
        return true
    ; 不等待其他进程处理显示消息，目标无响应时主界面仍可操作。
    mode := activate ? (DllCall("IsIconic", "Ptr", hwnd) ? 9 : 5) : 8
    if !DllCall("ShowWindowAsync", "Ptr", hwnd, "Int", mode) {
        WT.lastError := "无法发送恢复请求；窗口记录已保留，可稍后重试。"
        return false
    }
    WT.pendingRestore[hwnd] := {started: A_TickCount, activate: activate}
    SetTimer(PollRestores, 50)
    PollRestores()
    return true
}

FinishRestore(hwnd) {
    global WT
    if WT.windows.Has(hwnd) {
        if WindowMatches(hwnd, WT.windows[hwnd])
            DllCall("RemoveProp", "Ptr", hwnd, "Str", WT.prop, "Ptr")
        WT.windows.Delete(hwnd)
    }
    if WT.pendingRestore.Has(hwnd)
        WT.pendingRestore.Delete(hwnd)
    try SaveJournal()
    catch Error as e
        WTLog("更新恢复记录失败: " e.Message)
    RefreshManager()
}

PollRestores() {
    global WT
    done := [], timeout := []
    for hwnd, request in WT.pendingRestore {
        if !WT.windows.Has(hwnd) || !WindowMatches(hwnd, WT.windows[hwnd])
            done.Push(hwnd)
        else if DllCall("IsWindowVisible", "Ptr", hwnd) {
            if request.activate
                DllCall("SetForegroundWindow", "Ptr", hwnd)
            done.Push(hwnd)
        } else if A_TickCount - request.started >= 3000
            timeout.Push(hwnd)
    }
    for hwnd in done
        FinishRestore(hwnd)
    for hwnd in timeout {
        WT.pendingRestore.Delete(hwnd)
        WT.lastError := "窗口恢复超时，可能未响应；恢复记录已保留，可再次尝试。"
        WTLog(WT.lastError)
    }
    if timeout.Length {
        WT.snapshot := ""
        RefreshManager()
        UpdateSummary()
    }
    if !WT.pendingRestore.Count
        SetTimer(PollRestores, 0)
}

RestoreLatest() {
    global WT
    stale := [], latest := 0, order := -1
    for hwnd, record in WT.windows {
        if !WindowMatches(hwnd, record)
            stale.Push(hwnd)
        else if !WT.pendingRestore.Has(hwnd) && record.order > order
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
        WT.gui.AddText("w740", "双击恢复窗口；无响应窗口会保留记录，可稍后重试。")
        WT.list := WT.gui.AddListView("w740 r12 -Multi", ["窗口标题", "窗口句柄", "所属程序", "收起时间"])
        WT.imageList := IL_Create(16)
        WT.list.SetImageList(WT.imageList, 1)
        WT.icons := Map()
        WT.list.ModifyCol(1, 400), WT.list.ModifyCol(2, 0)
        ApplyListPreferences()
        WT.list.OnEvent("DoubleClick", (*) => RestoreSelected())
        WT.gui.AddButton("w130", "恢复选中").OnEvent("Click", (*) => RestoreSelected())
        WT.gui.AddButton("x+10 w130", "恢复全部").OnEvent("Click", (*) => RestoreAll())
        WT.gui.AddButton("x+10 w160", "设置…").OnEvent("Click", (*) => OpenSettings(1))
        WT.summary := WT.gui.AddEdit("xm w740 r4 ReadOnly -Wrap", "")
        WT.gui.OnEvent("Close", (*) => CloseManager())
        WT.gui.OnEvent("Escape", (*) => CloseManager())
    }
    UpdateSummary()
    RefreshManager()
    WT.gui.Show()
}

RefreshManager() {
    global WT
    UpdateTrayActions()
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
        icon := 0
        if HasProp(record, "path") && record.path != "" {
            if !WT.icons.Has(record.path) {
                try WT.icons[record.path] := IL_Add(WT.imageList, record.path)
                catch
                    WT.icons[record.path] := 0
            }
            icon := WT.icons[record.path]
        }
        row := WT.list.Add(icon ? "Icon" icon : "", record.title = "" ? "（无标题窗口）" : record.title, hwnd,
            HasProp(record, "process") ? record.process : "未知", HasProp(record, "time") ? record.time : "上次运行")
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
    if WT.keyErrors.Count
        text .= "`n有 " WT.keyErrors.Count " 项快捷键暂不可用，原键位已保留；请到设置查看。"
    if WT.lastError != ""
        text .= "`n" WT.lastError
    WT.summary.Text := text
}

MaintainWindows() {
    global WT
    previousCritical := A_IsCritical
    Critical("On")
    try {
        stale := []
        for hwnd, record in WT.windows {
            if WT.pendingRestore.Has(hwnd)
                continue
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
        UpdateTrayActions()
    } finally {
        Critical(previousCritical)
    }
}

ManagerExit(reason, code) {
    global WT
    CancelRecording()
    RestoreAll()
    ; 退出仅作有界等待，绝不因目标无响应无限阻塞。
    deadline := A_TickCount + 500
    while WT.pendingRestore.Count && A_TickCount < deadline {
        Sleep(20)
        PollRestores()
    }
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

UpdateTrayActions() {
    global WT
    if !WT.trayReady
        return
    for label in ["恢复最近收起的窗口", "恢复全部窗口"] {
        if WT.windows.Count
            A_TrayMenu.Enable(label)
        else
            A_TrayMenu.Disable(label)
    }
}

ApplyListPreferences() {
    global WT
    if WT.list {
        WT.list.ModifyCol(3, WT.showProcess ? 190 : 0)
        WT.list.ModifyCol(4, WT.showTime ? 120 : 0)
    }
}

#Include tests\SelfTest.ahk
