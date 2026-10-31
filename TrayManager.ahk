; SPDX-License-Identifier: GPL-2.0-or-later
; Copyright (C) 2026 JimmeYoumu
; 托盘与窗口管理。保留原有窗口定位逻辑。
global WT := {version: "0.1.3", windows: Map(), keys: [], configuredKeys: [], keyErrors: Map(), bindings: Map(), nextKeyId: 8192,
    gui: 0, list: 0, settings: 0, recorder: 0, warnings: "", summary: 0, snapshot: "",
    recoveryBlocked: false, lastError: "", activeIssues: Map(), hooksPaused: false, pendingRestore: Map(),
    showProcess: true, showTime: true, icons: Map(), imageList: 0, trayReady: false,
    ini: A_ScriptDir "\WindowTool.ini", journal: A_ScriptDir "\WindowTool.hidden",
    log: A_ScriptDir "\WindowTool.log", prop: "Kirara.WindowTool.Hidden.v1",
    title: "Kirara.WindowTool.Manager.v1", mutex: 0, retry: 0, serial: 0}
#Include Hotkeys.ahk
#Include Startup.ahk
#Include Settings.ahk
#Include Updates.ahk

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
        MsgBox("已有 WindowTool 实例，但暂时无法连接。请稍后再次打开。", "WindowTool")
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
    A_IconTip := "WindowTool"
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
        if WT.activeIssues.Has("hide")
            WT.activeIssues.Delete("hide")
        RefreshManager()
        return true
    } catch Error as e {
        WT.lastError := e.Message
        WT.activeIssues["hide"] := e.Message
        WTLog("收起失败: " e.Message)
        if notify
            MsgBox(e.Message, "WindowTool")
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
        WT.activeIssues["restore:" hwnd] := WT.lastError
        return false
    }
    WT.pendingRestore[hwnd] := {started: A_TickCount, activate: activate}
    SetTimer(PollRestores, 50)
    PollRestores()
    return true
}

FinishRestore(hwnd) {
    global WT
    if WT.activeIssues.Has("restore:" hwnd)
        WT.activeIssues.Delete("restore:" hwnd)
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
        WT.activeIssues["restore:" hwnd] := WT.lastError
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
    OpenSettings(0)
}

CreateManagerPage(g) {
    global WT
        WT.gui := g
        WT.list := g.AddListView("x22 y46 w516 h310 -Multi", ["窗口标题", "窗口句柄", "所属程序", "收起时间"])
        WT.listLayout := ""
        WT.imageList := IL_Create(16)
        WT.list.SetImageList(WT.imageList, 1)
        WT.icons := Map()
        WT.list.ModifyCol(1, 280), WT.list.ModifyCol(2, 0)
        ApplyListPreferences()
        WT.list.OnEvent("DoubleClick", (*) => RestoreSelected())
        WT.list.OnEvent("ItemSelect", (*) => UpdateManagerButtons())
        selected := g.AddButton("x22 y368 w90 h26", "恢复选中")
        selected.OnEvent("Click", (*) => RestoreSelected())
        WT.restoreSelectedButton := selected
        all := g.AddButton("x+8 w90 h26", "恢复全部")
        all.OnEvent("Click", (*) => RestoreAll())
        WT.restoreAllButton := all
        WT.managerHints := Map(WT.list.Hwnd, "list", selected.Hwnd, "selected", all.Hwnd, "all")
        WT.hoverControl := 0, WT.hoverSince := 0
}

RefreshManager() {
    global WT
    UpdateTrayActions()
    UpdateSummary()
    if !WT.list
        return
    UpdateManagerButtons()
    snapshot := ""
    for hwnd, record in WT.windows
        snapshot .= hwnd "|" record.title "`n"
    if snapshot = WT.snapshot
        return
    WT.snapshot := snapshot
    top := SendMessage(0x1027, 0, 0, WT.list.Hwnd) + 1
    topHwnd := top <= WT.list.GetCount() ? WT.list.GetText(top, 2) : ""
    row := WT.list.GetCount()
    while row > 0 {
        if !WT.windows.Has(Integer(WT.list.GetText(row, 2)))
            WT.list.Delete(row)
        row--
    }
    rows := Map()
    Loop WT.list.GetCount()
        rows[Integer(WT.list.GetText(A_Index, 2))] := A_Index
    for hwnd, record in WT.windows {
        title := record.title = "" ? "（无标题窗口）" : record.title
        process := HasProp(record, "process") ? record.process : "未知"
        time := HasProp(record, "time") ? record.time : "上次运行"
        if rows.Has(hwnd) {
            row := rows[hwnd]
            if WT.list.GetText(row, 1) != title || WT.list.GetText(row, 3) != process || WT.list.GetText(row, 4) != time
                WT.list.Modify(row, "", title, hwnd, process, time)
            continue
        }
        icon := 0
        if HasProp(record, "path") && record.path != "" {
            if !WT.icons.Has(record.path) {
                try WT.icons[record.path] := IL_Add(WT.imageList, record.path)
                catch
                    WT.icons[record.path] := 0
            }
            icon := WT.icons[record.path]
        }
        rows[hwnd] := WT.list.Add(icon ? "Icon" icon : "", title, hwnd, process, time)
    }
    if topHwnd != "" && rows.Has(Integer(topHwnd)) {
        delta := rows[Integer(topHwnd)] - 1 - SendMessage(0x1027, 0, 0, WT.list.Hwnd)
        rect := Buffer(16, 0)
        if delta && SendMessage(0x100E, 0, rect.Ptr, WT.list.Hwnd)
            SendMessage(0x1014, 0, delta * (NumGet(rect, 12, "Int") - NumGet(rect, 4, "Int")), WT.list.Hwnd)
    }
    UpdateManagerButtons()
}

UpdateManagerButtons() {
    global WT
    if !HasProp(WT, "restoreSelectedButton")
        return
    WT.restoreSelectedButton.Enabled := WT.list.GetNext() != 0
    WT.restoreAllButton.Enabled := WT.windows.Count > 0
}

RestoreSelected() {
    global WT
    if row := WT.list.GetNext() {
        if !RestoreWindow(Integer(WT.list.GetText(row, 2)))
            MsgBox("窗口暂时无法恢复，请确认目标程序与 WindowTool 的运行权限，并保留恢复记录。", "WindowTool")
    }
}

CloseManager() {
    CloseSettings()
}

ManagerHint() {
    global WT
    MouseGetPos(, , &window, &control, 2)
    if window != WT.gui.Hwnd || !WT.managerHints.Has(control) {
        if WT.hoverControl {
            ToolTip()
            WT.hoverControl := 0
        }
        return
    }
    if control != WT.hoverControl {
        ToolTip()
        WT.hoverControl := control, WT.hoverSince := A_TickCount
        return
    }
    if WT.hoverSince = 0 || A_TickCount - WT.hoverSince < 500
        return
    switch WT.managerHints[control] {
        case "list":
            text := "双击恢复窗口；无响应时保留记录，可稍后重试。"
        case "selected":
            text := "恢复列表中选中的窗口；也可双击该行。"
        case "all":
            text := "恢复所有已收起的窗口。`n快捷键：" KeyLabel(WT.keys[7])
        case "settings":
            text := "自定义快捷键、启动和界面选项。`n快捷键：" KeyLabel(WT.keys[8])
    }
    ToolTip(text)
    WT.hoverSince := 0
}

UpdateSummary() {
    global WT
    if !WT.summary
        return
    text := "已收起 " WT.windows.Count " 个窗口"
    if WT.pendingRestore.Count
        text .= "　正在恢复 " WT.pendingRestore.Count " 个"
    if WT.recoveryBlocked
        text .= "　恢复记录异常，请到设置查看。"
    else if WT.activeIssues.Count || WT.warnings != ""
        text .= "　操作异常，详情见设置 → 状态与诊断。"
    else if WT.keyErrors.Count
        text .= "　" WT.keyErrors.Count " 项快捷键不可用，请到设置查看。"
    else if !A_IsAdmin
        text .= "　当前为普通权限"
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
        for hwnd in stale
            if WT.activeIssues.Has("restore:" hwnd)
                WT.activeIssues.Delete("restore:" hwnd)
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

ManagerExit(reason, code, decision := "") {
    global WT
    CancelRecording()
    if reason != "Shutdown" && reason != "Logoff" && reason != "Error"
        if !ConfirmLeaveSettings(decision, "退出")
            return 1
    RestoreAll()
    ; 退出仅作有界等待，绝不因目标无响应无限阻塞。
    deadline := A_TickCount + 500
    while WT.pendingRestore.Count && A_TickCount < deadline {
        Sleep(20)
        PollRestores()
    }
    ; 恢复失败时阻止普通退出，保留再次尝试的入口。
    if WT.windows.Count && reason != "Shutdown" && reason != "Logoff" {
        MsgBox("仍有窗口未能恢复，请先在管理界面恢复后再退出。", "WindowTool")
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
        layout := WT.showProcess ":" WT.showTime
        if WT.listLayout = layout
            return
        WT.listLayout := layout
        rect := Buffer(16, 0)
        DllCall("GetClientRect", "Ptr", WT.list.Hwnd, "Ptr", rect)
        width := Floor(NumGet(rect, 8, "Int") * 96 / A_ScreenDPI) - 4
        WT.list.ModifyCol(1, Max(100, width - (WT.showProcess ? 166 : 0) - (WT.showTime ? 90 : 0)))
        WT.list.ModifyCol(3, WT.showProcess ? 166 : 0)
        WT.list.ModifyCol(4, WT.showTime ? 90 : 0)
    }
}

#Include tests\SelfTest.ahk
