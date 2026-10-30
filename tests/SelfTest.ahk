; SPDX-License-Identifier: GPL-2.0-or-later
; Copyright (C) 2026 JimmeYoumu
; 仅操作专用测试窗口、测试文件及测试命名空间。
RunSelfTests() {
    global WT
    WT.ini := A_ScriptDir "\tests\test.ini"
    WT.journal := A_ScriptDir "\tests\test.hidden"
    WT.log := A_ScriptDir "\tests\test.log"
    WT.prop := "Kirara.WindowTool.Hidden.Test.v1"
    output := A_ScriptDir "\tests\results.txt"
    FileOpen(output, "w", "UTF-8").Close()
    results := [], fixtures := [], blocker := 0
    try {
        DetectHiddenWindows(true)
        WT.keys := TestKeys()
        p := ParseKey("#^!F10")
        Assert(p.modifiers = 11 && p.vk = 0x79, "解析组合键", results)
        Assert(ParseKey("^+Tab").vk = 9 && ParseKey("^!CapsLock").vk = 20,
            "Tab 与 CapsLock 可解析", results)
        Assert(Actions().Length = 10, "十项功能共用配置定义", results)
        defaults := DefaultKeys()
        Assert(defaults[1] = "^+CapsLock" && defaults[2] = "^!CapsLock"
            && defaults[3] = "#F9", "新默认快捷键", results)
        Assert(defaults[4] = "#F12" && defaults[5] = "#F11" && defaults[6] = "#F10",
            "原定位默认保持一致", results)
        Assert(Throws(() => ParseKey("F1")) && Throws(() => ParseKey("^Ctrl")),
            "拒绝裸键及单独修饰键", results)
        RegisterKeys(WT.keys)
        duplicate := WT.keys.Clone(), duplicate[2] := "+!^F1"
        Assert(Throws(() => RegisterKeys(duplicate)) && WT.bindings.Count = 10,
            "重复组合验证不影响原注册", results)
        blocker := Gui()
        Assert(DllCall("RegisterHotKey", "Ptr", blocker.Hwnd, "Int", 900,
            "UInt", 7, "UInt", 0x7A), "准备外部快捷键冲突", results)
        conflict := WT.keys.Clone(), conflict[2] := "^!+F11"
        Assert(Throws(() => RegisterKeys(conflict)) && WT.bindings.Count = 10,
            "外部冲突不注销旧快捷键", results)
        Assert(!DllCall("RegisterHotKey", "Ptr", blocker.Hwnd, "Int", 901,
            "UInt", 7, "UInt", 0x70), "失败后旧组合仍被真实占用", results)
        DllCall("UnregisterHotKey", "Ptr", blocker.Hwnd, "Int", 900)
        swap := WT.keys.Clone(), swap[1] := WT.keys[2], swap[2] := WT.keys[1]
        RegisterKeys(swap)
        Assert(WT.keys[1] = "^!+F2" && WT.bindings.Count = 10, "可原子交换两个功能的组合", results)
        RegisterKeys(TestKeys())
        disabled := WT.keys.Clone(), disabled[10] := ""
        RegisterKeys(disabled)
        Assert(WT.bindings.Count = 9, "单独禁用功能", results)
        hookKeys := TestKeys(), hookKeys[1] := "^!+CapsLock", hookKeys[4] := "^!+F12"
        RegisterKeys(hookKeys)
        Assert(WT.bindings[ParseKey(hookKeys[1]).signature].hook != ""
            && WT.bindings[ParseKey(hookKeys[4]).signature].hook != "", "CapsLock 与 F12 使用键盘钩子", results)
        UnregisterKeys()
        WT.keys := TestKeys()
        Assert(NextRatio(2, 0, 1000, [0, 0.5, 1]) = 0.5
            && NextRatio(500, 0, 1000, [0, 0.5, 1]) = 1
            && NextRatio(1000, 0, 1000, [0, 0.5, 1]) = 0, "定位循环三档", results)
        Loop 2 {
            runtime := A_IsCompiled ? EnvGet("WINDOWTOOL_AHK") : A_AhkPath
            if runtime = ""
                runtime := A_ProgramFiles "\AutoHotkey\v2\AutoHotkey64.exe"
            Run('"' runtime '" "' A_ScriptDir '\tests\Fixture.ahk"', , , &pid)
            hwnd := WinWait("WindowTool Test Fixture " pid, , 10)
            fixtures.Push({pid: pid, hwnd: hwnd})
        }
        hwnd := fixtures[1].hwnd
        target := "ahk_id " hwnd
        WinGetPos(&x, &y, &w, &h, target)
        PositionWindow(hwnd, "center")
        WinGetPos(&cx, &cy, &cw, &ch, target)
        Assert(cw = w && ch = h, "定位不改变窗口大小", results)
        PositionWindow(hwnd, "center")
        WinGetPos(&cx2, &cy2, , , target)
        Assert(cx2 = cx && cy2 = cy, "重复居中保持位置", results)
        Assert(HideWindow(hwnd) && !DllCall("IsWindowVisible", "Ptr", hwnd), "隐藏窗口并写恢复记录", results)
        Assert(!HideWindow(hwnd) && WT.windows.Count = 1, "重复隐藏不覆盖记录", results)
        Assert(HideWindow(fixtures[2].hwnd), "收起第二个窗口", results)
        RestoreLatest()
        Assert(DllCall("IsWindowVisible", "Ptr", fixtures[2].hwnd)
            && !DllCall("IsWindowVisible", "Ptr", hwnd), "按收起顺序恢复最近窗口", results)
        WT.windows := Map()
        RecoverWindows()
        Assert(DllCall("IsWindowVisible", "Ptr", hwnd) && WT.windows.Count = 0,
            "从磁盘记录恢复", results)
        crashJournal := A_ScriptDir "\tests\crash.hidden"
        crashReady := A_ScriptDir "\tests\crash.ready"
        if FileExist(crashReady)
            FileDelete(crashReady)
        crashCommand := A_IsCompiled ? '"' A_ScriptFullPath '" --crash-host ' hwnd
            : '"' A_AhkPath '" "' A_ScriptFullPath '" --crash-host ' hwnd
        Run(crashCommand, , , &crashPid)
        Loop 100 {
            if FileExist(crashReady)
                break
            Sleep(50)
        }
        Assert(FileExist(crashReady) && !DllCall("IsWindowVisible", "Ptr", hwnd),
            "独立进程写入记录并隐藏测试窗口", results)
        ProcessClose(crashPid)
        ProcessWaitClose(crashPid, 5)
        normalJournal := WT.journal
        WT.journal := crashJournal
        RecoverWindows()
        WT.journal := normalJournal
        Assert(DllCall("IsWindowVisible", "Ptr", hwnd), "强制终止进程后仍可恢复窗口", results)
        originalJournal := WT.journal
        WT.journal := A_ScriptDir "\tests\missing-folder\blocked.hidden"
        Assert(!HideWindow(hwnd, false) && DllCall("IsWindowVisible", "Ptr", hwnd)
            && WT.windows.Count = 0, "写记录失败不会隐藏窗口", results)
        Assert(!DllCall("GetProp", "Ptr", hwnd, "Str", WT.prop, "Ptr"), "写入失败清除临时标记", results)
        WT.journal := originalJournal
        HideWindow(hwnd)
        WinMaximize("ahk_id " fixtures[2].hwnd)
        HideWindow(fixtures[2].hwnd)
        WT.gui := 0
        ShowManager()
        WinActivate("ahk_id " WT.gui.Hwnd)
        before := WinExist("A")
        RestoreAll(false)
        Assert(WinExist("A") = before, "批量恢复不抢焦点", results)
        Assert(WinGetMinMax("ahk_id " fixtures[2].hwnd) = 1, "恢复保持最大化状态", results)
        WinRestore("ahk_id " fixtures[2].hwnd)
        HideWindow(hwnd)
        WT.list.Modify(1, "Select Focus")
        selection := WT.list.GetText(WT.list.GetNext(), 2)
        RefreshManager()
        Assert(WT.list.GetText(WT.list.GetNext(), 2) = selection, "无变化时不重建列表选择", results)
        DllCall("ShowWindow", "Ptr", hwnd, "Int", 8)
        MaintainWindows()
        Assert(WT.windows.Count = 0, "自动清理自行重新显示的窗口", results)
        HideWindow(hwnd)
        Assert(ManagerExit("Exit", 0) != 1 && DllCall("IsWindowVisible", "Ptr", hwnd),
            "正常退出恢复窗口", results)
        WT.keys := TestKeys()
        ShowStartup()
        Assert(WT.startupStatus.Text != "" && WT.startupEnable.Enabled = !!A_IsCompiled,
            "自启动状态界面及源码模式限制", results)
        WT.startupGui.Hide()
        ShowSettings()
        Assert(WT.controls.Length = 10, "全功能设置界面", results)
        c := WT.controls[1]
        StartRecording(c)
        ih := WT.recorder.hook
        RecordKey(ih, 0xA2, 0), RecordKey(ih, 0xA0, 0), RecordKey(ih, 9, 0)
        Assert(c.key = "^+Tab" && !WT.recorder, "录制 Tab 不触发焦点导航", results)
        StartRecording(c)
        ih := WT.recorder.hook
        RecordKey(ih, 0xA2, 0), RecordKey(ih, 0xA4, 0), RecordKey(ih, 0x14, 0)
        Assert(c.key = "^!CapsLock" && !WT.recorder, "录制 CapsLock", results)
        StartRecording(c)
        ih := WT.recorder.hook
        RecordKey(ih, 0xA2, 0), RecordKeyUp(ih, 0xA2, 0), RecordKey(ih, 0x5B, 0), RecordKey(ih, 0x78, 0)
        Assert(c.key = "#F9", "录制 Win 及修饰键释放", results)
        StartRecording(c)
        ih := WT.recorder.hook
        RecordKey(ih, 0x1B, 0)
        Assert(!WT.recorder && c.key = "#F9", "Esc 取消录制保留原键", results)
        StartRecording(c)
        CloseSettings()
        Assert(!WT.recorder, "关闭设置停止键盘录制", results)
        ShowSettings()
        StartRecording(c)
        WT.settings.Hide()
        WatchRecording()
        Assert(!WT.recorder, "离开设置自动取消录制", results)
        ResumeHooks()
        Assert(!WT.hooksPaused, "松开按键后恢复钩子", results)
        status := {Text: ""}
        if FileExist(WT.ini)
            FileDelete(WT.ini)
        IniWrite("keep", WT.ini, "Other", "Test")
        controls := ControlsFor(TestKeys())
        Assert(SaveSettings(controls, status) && LoadKeys()[10] = "^!+F10", "十项配置保存并生效", results)
        Assert(IniRead(WT.ini, "Other", "Test") = "keep", "保存保留其他配置段", results)
        iniBefore := FileRead(WT.ini)
        controls[2].key := controls[1].key
        Assert(!SaveSettings(controls, status) && FileRead(WT.ini) = iniBefore
            && WT.keys[2] = "^!+F2", "冲突不修改磁盘或运行配置", results)
        controls := ControlsFor(TestKeys())
        originalIni := WT.ini
        WT.ini := A_ScriptDir "\tests\missing-folder\blocked.ini"
        controls[1].key := "^!+F11"
        Assert(!SaveSettings(controls, status) && WT.keys[1] = "^!+F1"
            && WT.bindings.Count = 10, "保存失败释放新注册并保留旧注册", results)
        WT.ini := originalIni
        IniWrite("invalid-key", WT.ini, "Hotkeys", "RepairTray")
        StartKeys()
        Assert(WT.bindings.Count = 9 && WT.keys[9] = "" && WT.keys[8] != "",
            "单项错误不使所有快捷键失效", results)
        Assert(IniRead(WT.ini, "Hotkeys", "RepairTray") = "invalid-key", "错误配置不被启动静默覆盖", results)
        controls := ControlsFor(TestKeys())
        SaveSettings(controls, status)
        A_IconHidden := true
        Assert(!TrayExists() && EnsureTray() && TrayExists(), "检测托盘丢失并重建", results)
        UnregisterKeys()
        InitManager()
        Assert(WT.mutex && TrayExists(), "完整启动初始化", results)
        CloseSettings()
        WT.gui.Hide()
        command := A_IsCompiled ? '"' A_ScriptFullPath '" --probe'
            : '"' A_AhkPath '" "' A_ScriptFullPath '" --probe'
        Run(command, , , &probePid)
        ProcessWaitClose(probePid, 10)
        Sleep(150)
        Assert(!ProcessExist(probePid) && DllCall("IsWindowVisible", "Ptr", WT.gui.Hwnd),
            "再次启动打开原实例", results)
        A_IconHidden := true
        DllCall("PostMessage", "Ptr", A_ScriptHwnd, "UInt", WT.taskbarMsg, "Ptr", 0, "Ptr", 0)
        Sleep(150)
        Assert(TrayExists(), "任务栏重建通知恢复图标", results)
        ; 损坏的记录不能被新收起操作覆盖。
        FileOpen(WT.journal, "w", "UTF-8").Write(hwnd "|0`n")
        Assert(Throws(RecoverWindows), "拒绝零令牌，防止误恢复其他窗口", results)
        WT.recoveryBlocked := true
        corrupt := FileRead(WT.journal)
        Assert(!HideWindow(hwnd, false) && FileRead(WT.journal) = corrupt,
            "恢复记录损坏时禁止覆盖", results)
        WT.recoveryBlocked := false
        SaveJournal()
        HideWindow(hwnd)
        ProcessClose(fixtures[1].pid)
        ProcessWaitClose(fixtures[1].pid, 5)
        WinWaitClose("ahk_id " hwnd, , 5)
        MaintainWindows()
        Assert(WT.windows.Count = 0, "自动清理已关闭的隐藏窗口", results)
        FileAppend("PASS " results.Length " checks`n" JoinResults(results), output, "UTF-8")
    } catch Error as e {
        FileAppend("FAIL " e.Message "`n" e.Stack "`n" JoinResults(results), output, "UTF-8")
        failed := true
    } finally {
        WT.recoveryBlocked := false
        CancelRecording()
        RestoreAll()
        UnregisterKeys()
        if IsObject(blocker)
            blocker.Destroy()
        for fixture in fixtures {
            try ProcessClose(fixture.pid)
        }
        if IsSet(crashPid) {
            try ProcessClose(crashPid)
        }
    }
    ExitApp(IsSet(failed) ? 1 : 0)
}

TestKeys() {
    keys := []
    Loop Actions().Length
        keys.Push("^!+F" A_Index)
    return keys
}

ControlsFor(keys) {
    controls := []
    for key in keys
        controls.Push({key: key, enabled: {Value: key != ""}})
    return controls
}

Throws(callback) {
    try callback.Call()
    catch Error
        return true
    return false
}

Assert(condition, label, results) {
    if !condition
        throw Error(label)
    results.Push(label)
}

JoinResults(results) {
    content := ""
    for result in results
        content .= "  " result "`n"
    return content
}

PreviewTools() {
    global WT
    WT.ini := A_ScriptDir "\tests\preview.ini"
    WT.journal := A_ScriptDir "\tests\preview.hidden"
    WT.log := A_ScriptDir "\tests\preview.log"
    WT.prop := "Kirara.WindowTool.Hidden.Test.v1"
    keys := DefaultKeys()
    Loop keys.Length - 3
        keys[A_Index + 3] := ""
    for i, action in Actions()
        IniWrite(keys[i], WT.ini, "Hotkeys", action.name)
    InitManager()
    ShowManager()
    ShowSettings()
    SetTimer(PreviewState, 250)
    SetTimer((*) => ExitApp(), -180000)
    Persistent()
}

PreviewState() {
    global WT
    FileOpen(A_ScriptDir "\tests\preview-state.txt", "w", "UTF-8").Write(
        "windows=" WT.windows.Count " caps=" GetKeyState("CapsLock", "T")
        . " recording=" (WT.recorder ? 1 : 0))
}

RunCrashHost(hwnd) {
    global WT
    WT.journal := A_ScriptDir "\tests\crash.hidden"
    WT.log := A_ScriptDir "\tests\crash.log"
    WT.prop := "Kirara.WindowTool.Hidden.Test.v1"
    DetectHiddenWindows(true)
    if !HideWindow(hwnd, false)
        ExitApp(1)
    FileOpen(A_ScriptDir "\tests\crash.ready", "w", "UTF-8").Write("ready")
    SetTimer((*) => ExitApp(), -60000)
    Persistent()
}
