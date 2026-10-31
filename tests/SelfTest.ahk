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
        Loop 4 {
            runtime := A_IsCompiled ? EnvGet("WINDOWTOOL_AHK") : A_AhkPath
            if runtime = ""
                runtime := A_ProgramFiles "\AutoHotkey\v2\AutoHotkey64.exe"
            Run('"' runtime '" "' A_ScriptDir '\tests\Fixture.ahk"' (A_Index = 3 ? " --legacy" : A_Index = 4 ? " --per-monitor" : ""), , , &pid)
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
        px := -3, py := 503
        ConstrainLegacyOrigin("horizontal", &px, &py, 0, 0)
        Assert(px = 0 && py = 503, "旧式窗口边界约束不改纵坐标", results)
        px := -1923, py := -5
        ConstrainLegacyOrigin("vertical", &px, &py, -1920, 0)
        Assert(px = -1923 && py = 0, "垂直边界约束不改横坐标", results)
        ConstrainLegacyOrigin("center", &px, &py, -1920, 0)
        Assert(px = -1920 && py = 0, "负坐标屏幕约束使用实际原点", results)
        Assert(DllCall("GetAwarenessFromDpiAwarenessContext", "Ptr", DllCall("GetWindowDpiAwarenessContext", "Ptr", fixtures[3].hwnd, "Ptr"), "Int") = 0,
            "兼容性窗口实际为 DPI 不感知模式", results)
        Assert(DllCall("GetAwarenessFromDpiAwarenessContext", "Ptr", DllCall("GetWindowDpiAwarenessContext", "Ptr", fixtures[4].hwnd, "Ptr"), "Int") = 2,
            "现代窗口实际为逐显示器 DPI 模式", results)
        for fixtureIndex in [1, 3, 4] {
            testHwnd := fixtures[fixtureIndex].hwnd
            Loop MonitorGetCount() {
                monitorIndex := A_Index
                PlaceFixtureOnMonitor(testHwnd, monitorIndex)
                PositionWindow(testHwnd, "center")
                Sleep(80)
                baseline := PhysicalGeometry(testHwnd)
                xs := Map(), ys := Map(), stable := true
                Loop 12 {
                    PositionWindow(testHwnd, "horizontal")
                    Sleep(80)
                    actual := PhysicalGeometry(testHwnd)
                    stable := stable && actual.y = baseline.y && actual.w = baseline.w && actual.h = baseline.h
                    xs[actual.x] := true
                }
                Assert(stable && xs.Count = 3, "连续水平循环保持纵坐标和尺寸 " fixtureIndex "/" monitorIndex, results)
                baseline := PhysicalGeometry(testHwnd)
                Loop 12 {
                    PositionWindow(testHwnd, "vertical")
                    Sleep(80)
                    actual := PhysicalGeometry(testHwnd)
                    stable := stable && actual.x = baseline.x && actual.w = baseline.w && actual.h = baseline.h
                    ys[actual.y] := true
                }
                Assert(stable && ys.Count = 3, "连续垂直循环保持横坐标和尺寸 " fixtureIndex "/" monitorIndex, results)
                baseline := PhysicalGeometry(testHwnd)
                xs := Map(), stable := true
                Loop 9 {
                    PositionWindow(testHwnd, "horizontal")
                    actual := PhysicalGeometry(testHwnd)
                    stable := stable && actual.y = baseline.y && actual.w = baseline.w && actual.h = baseline.h
                    xs[actual.x] := true
                }
                Assert(stable && xs.Count = 3, "无间隔水平连按不乱序 " fixtureIndex "/" monitorIndex, results)
                baseline := PhysicalGeometry(testHwnd)
                ys := Map()
                Loop 9 {
                    PositionWindow(testHwnd, "vertical")
                    actual := PhysicalGeometry(testHwnd)
                    stable := stable && actual.x = baseline.x && actual.w = baseline.w && actual.h = baseline.h
                    ys[actual.y] := true
                }
                Assert(stable && ys.Count = 3, "无间隔垂直连按不乱序 " fixtureIndex "/" monitorIndex, results)
            }
        }
        closingHwnd := fixtures[4].hwnd
        SendMessage(0x8002, 0, 0, , "ahk_id " closingHwnd)
        started := A_TickCount
        PositionWindow(closingHwnd, "center")
        Assert(A_TickCount - started < 250 && WinWaitClose("ahk_id " closingHwnd, , 1),
            "定位途中目标关闭不会卡住或报错", results)
        Assert(HideWindow(hwnd) && !DllCall("IsWindowVisible", "Ptr", hwnd), "隐藏窗口并写恢复记录", results)
        Assert(!HideWindow(hwnd) && WT.windows.Count = 1, "重复隐藏不覆盖记录", results)
        Assert(HideWindow(fixtures[2].hwnd), "收起第二个窗口", results)
        RestoreLatest()
        WaitForRestores()
        Assert(DllCall("IsWindowVisible", "Ptr", fixtures[2].hwnd)
            && !DllCall("IsWindowVisible", "Ptr", hwnd), "按收起顺序恢复最近窗口", results)
        WT.windows := Map()
        RecoverWindows()
        WaitForRestores()
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
        WaitForRestores()
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
        WaitForRestores()
        Assert(WinExist("A") = before, "批量恢复不抢焦点", results)
        Assert(WinGetMinMax("ahk_id " fixtures[2].hwnd) = 1, "恢复保持最大化状态", results)
        WinRestore("ahk_id " fixtures[2].hwnd)
        HideWindow(hwnd)
        hungReady := A_ScriptDir "\tests\hung-" fixtures[1].pid ".ready"
        if FileExist(hungReady)
            FileDelete(hungReady)
        DllCall("PostMessage", "Ptr", hwnd, "UInt", 0x8001, "Ptr", 0, "Ptr", 0)
        Loop 100 {
            if FileExist(hungReady)
                break
            Sleep(10)
        }
        Assert(FileExist(hungReady), "测试窗口进入真实无响应状态", results)
        stalledGeometry := PhysicalGeometry(hwnd)
        beforeDpi := DllCall("GetThreadDpiAwarenessContext", "Ptr")
        beforeCritical := A_IsCritical
        started := A_TickCount
        Assert(PositionWindow(hwnd, "center") = false && A_TickCount - started < 250,
            "无响应定位有界返回且不提交移动", results)
        Assert(DllCall("AreDpiAwarenessContextsEqual", "Ptr", beforeDpi,
            "Ptr", DllCall("GetThreadDpiAwarenessContext", "Ptr")) && A_IsCritical = beforeCritical,
            "定位超时恢复线程 DPI 和 Critical 状态", results)
        started := A_TickCount
        PositionWindow(fixtures[2].hwnd, "center")
        Assert(A_TickCount - started < 250, "卡住一个窗口仍可定位另一个", results)
        started := A_TickCount
        Assert(RestoreWindow(hwnd, false) && A_TickCount - started < 500,
            "无响应窗口恢复请求不阻塞主线程", results)
        HideWindow(fixtures[2].hwnd)
        RestoreWindow(fixtures[2].hwnd, false)
        deadline := A_TickCount + 1000
        while WT.windows.Has(fixtures[2].hwnd) && A_TickCount < deadline {
            Sleep(20)
            PollRestores()
        }
        Assert(!WT.windows.Has(fixtures[2].hwnd), "一个窗口卡住仍可恢复其他窗口", results)
        WaitForRestores()
        Assert(WT.windows.Has(hwnd) && InStr(FileRead(WT.journal), hwnd "|"),
            "无响应超时保留窗口与磁盘恢复记录", results)
        Sleep(1700)
        MaintainWindows()
        Assert(!WT.windows.Has(hwnd), "目标恢复响应后正常清理记录", results)
        resumedGeometry := PhysicalGeometry(hwnd)
        Assert(resumedGeometry.x = stalledGeometry.x && resumedGeometry.y = stalledGeometry.y,
            "目标恢复后不执行被跳过的旧定位", results)
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
        Assert(WT.startupStatus.Text != "" && !WT.startupEnable.Enabled && !WT.startupRepair.Enabled,
            "自启动状态界面及源码模式限制", results)
        WT.settings.Hide()
        ShowSettings()
        Assert(WT.controls.Length = 10, "全功能设置界面", results)
        service := ComObject("Schedule.Service")
        service.Connect()
        definition := StartupDefinition(service, StartupSID(), A_IsCompiled ? A_ScriptFullPath : A_AhkPath)
        path := definition.Actions.Item(1).Path
        Assert(StartupIssues(definition, path) = "", "正常任务定义通过健康检查", results)
        definition.Triggers.Item(1).Enabled := false
        Assert(InStr(StartupIssues(definition, path), "触发器"), "识别已停用登录触发器", results)
        definition.Actions.Item(1).Path := A_ScriptDir "\does-not-exist.exe"
        Assert(InStr(StartupIssues(definition, path), "不存在"), "识别失效自启路径", results)
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
        CloseSettings("Discard")
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
        Assert(SaveSettings(ControlsFor(WT.configuredKeys), status)
            && IniRead(WT.ini, "Hotkeys", "RepairTray") = "invalid-key",
            "保存其他设置保留暂不可用的原键位", results)
        UnregisterKeys()
        Assert(DllCall("RegisterHotKey", "Ptr", blocker.Hwnd, "Int", 902,
            "UInt", 7, "UInt", 0x74), "准备启动时快捷键冲突", results)
        StartKeys(TestKeys())
        Assert(WT.keys[5] = "" && WT.configuredKeys[5] = "^!+F5", "运行状态与用户配置分离", results)
        Assert(SaveSettings(ControlsFor(WT.configuredKeys), status)
            && IniRead(WT.ini, "Hotkeys", "Vertical") = "^!+F5", "临时冲突后保存不丢配置", results)
        DllCall("UnregisterHotKey", "Ptr", blocker.Hwnd, "Int", 902)
        RetryConfiguredKeys()
        Assert(WT.keys[5] = "^!+F5" && !WT.keyErrors.Count, "释放占用后可重试恢复原快捷键", results)
        controls := ControlsFor(TestKeys())
        SaveSettings(controls, status)
        ShowSettings()
        WT.startupEnable.Enabled := false ; 不允许 GUI 应用测试修改正式自启。
        FillSettings(WT.configuredKeys)
        WT.processOption.Value := false, WT.timeOption.Value := false
        Assert(ApplySettings() && IniRead(WT.ini, "Interface", "ShowProcess") = 0
            && !WT.showTime, "统一应用保存列表偏好", results)
        WT.processOption.Value := true
        CloseSettings("Discard")
        ShowSettings()
        Assert(!WT.processOption.Value, "取消丢弃未应用的选项", results)
        WT.startupEnable.Enabled := false
        WT.processOption.Value := true, WT.timeOption.Value := true
        Assert(ApplySettings(true) && !DllCall("IsWindowVisible", "Ptr", WT.settings.Hwnd),
            "确定应用后关闭设置", results)
        OpenSettings(2)
        WT.controls[4].enabled.Value := false
        RefreshKeyStates()
        Assert(WT.controls[4].state.Text = "待停用", "未应用的停用状态", results)
        WT.controls[4].enabled.Value := true
        WT.controls[4].key := "^!+F24"
        RefreshKeyStates()
        Assert(WT.controls[4].state.Text = "待修改", "未应用的改键状态", results)
        FillSettings(WT.configuredKeys)
        choice := WT.startupEnable.Value
        WT.startupEnable.Value := !choice
        RefreshStartup()
        Assert(WT.startupEnable.Value = !choice, "重新检测保留未应用自启选择", results)
        RefreshStartup(true)
        OpenSettings(4)
        Assert(!WT.resetButton.Enabled, "关于页禁用恢复默认", results)
        OpenSettings(2)
        Assert(WT.resetButton.Enabled, "配置页可恢复默认", results)
        WT.controls[4].enabled.Value := false
        WT.processOption.Value := false
        ShowManager()
        Assert(WT.gui.Hwnd = WT.settings.Hwnd && WT.tabs.Value = 1,
            "窗口管理与设置共用单一窗口", results)
        Assert(!WT.okButton.Visible && WT.closeButton.Visible && !WT.keyStatus.Visible,
            "窗口页不显示配置提交按钮", results)
        OpenSettings(2)
        Assert(!WT.controls[4].enabled.Value && !WT.processOption.Value,
            "切换窗口页保留未保存的配置", results)
        Assert(WT.okButton.Visible && !WT.closeButton.Visible,
            "配置页恢复应用与取消入口", results)
        FillSettings(WT.configuredKeys)
        WT.processOption.Value := WT.showProcess
        Assert(Throws(ConfigureStartup.Bind(true, "")), "预览入口禁止修改正式自启", results)
        WT.controls[7].key := ""
        WT.controls[7].enabled.Value := true
        RefreshKeyStates()
        Assert(WT.controls[7].state.Text = "待录制", "勾选空键位提示待录制", results)
        FillSettings(WT.configuredKeys)
        WT.processOption.Value := !WT.showProcess
        ShowManager()
        Assert(HasUnsavedSettings() && !CloseSettings("Cancel")
            && DllCall("IsWindowVisible", "Ptr", WT.settings.Hwnd), "取消关闭保留未保存配置", results)
        Assert(CloseSettings("Save") && WT.showProcess = !!WT.processOption.Value,
            "关闭时可保存配置", results)
        OpenSettings(2)
        WT.controls[7].key := ""
        WT.controls[7].enabled.Value := true
        ShowManager()
        Assert(!CloseSettings("Save") && WT.tabs.Value = 3
            && InStr(WT.keyStatus.Text, "录制快捷键"), "跨页保存失败保留具体原因", results)
        FillSettings(WT.configuredKeys)
        WT.timeOption.Value := !WT.showTime
        Assert(ManagerExit("Exit", 0, "Cancel") = 1 && HasUnsavedSettings(),
            "主动退出可取消并保留未保存设置", results)
        Assert(ConfirmLeaveSettings("Discard") && !HasUnsavedSettings(),
            "放弃后不会重复提示未保存", results)
        WT.timeOption.Value := !WT.showTime
        Assert(ConfirmLeaveSettings("Save") && !HasUnsavedSettings(),
            "退出与关闭共用保存流程", results)
        workingDirectory := A_WorkingDir
        try {
            SetWorkingDir(A_Temp)
            Assert(StrLen(ReadLicense()) > 1000, "其他工作目录下可读取许可证", results)
        } finally {
            SetWorkingDir(workingDirectory)
        }
        OpenSettings(2)
        WT.keyStatus.Text := "快捷键页测试提示"
        OpenSettings(3)
        Assert(!InStr(WT.keyStatus.Text, "快捷键页测试提示"), "诊断页不沿用配置页提示", results)
        OpenSettings(2)
        Assert(WT.keyStatus.Text = "快捷键页测试提示", "切回页面保留本页提示", results)
        ShowLicense()
        Assert(StrLen(WT.licenseGui["Edit1"].Value) > 1000, "内置许可证可独立查看", results)
        WT.licenseGui.Hide()
        Critical("On")
        actualWindows := WT.windows
        WT.windows := Map()
        Loop 40
            WT.windows[-100000 - A_Index] := {title: "测试窗口 " A_Index}
        WT.snapshot := ""
        ShowManager()
        WT.list.Modify(25, "Select Focus")
        selectedHandle := Integer(WT.list.GetText(25, 2))
        SendMessage(0x1013, 24, 0, WT.list.Hwnd)
        top := SendMessage(0x1027, 0, 0, WT.list.Hwnd)
        WT.list.ModifyCol(1, 173)
        WT.windows[selectedHandle].title := "标题已更新"
        RefreshManager()
        Assert(WT.list.GetNext() = 25 && WT.list.GetText(25, 1) = "标题已更新",
            "逐行更新保持选中项", results)
        Assert(SendMessage(0x1027, 0, 0, WT.list.Hwnd) = top,
            "标题刷新保持滚动位置", results)
        Assert(Abs(SendMessage(0x101D, 0, 0, WT.list.Hwnd) - Round(173 * A_ScreenDPI / 96)) <= 1,
            "列表刷新保持手动列宽", results)
        WT.windows := actualWindows
        RefreshManager()
        Critical("Off")
        CloseSettings("Discard")
        ShowManager()
        Assert(!WT.restoreAllButton.Enabled && !WT.restoreSelectedButton.Enabled,
            "空列表禁用恢复按钮", results)
        oldError := WT.lastError
        WT.lastError := "历史测试错误"
        WT.activeIssues.Clear()
        UpdateSummary()
        Assert(!InStr(WT.summary.Text, "异常"), "历史错误不冒充当前故障", results)
        WT.activeIssues["restore:0"] := "测试恢复错误"
        UpdateSummary()
        Assert(InStr(WT.summary.Text, "异常"), "当前故障显示提醒", results)
        FinishRestore(0)
        Assert(!WT.activeIssues.Count && WT.lastError = "历史测试错误",
            "恢复成功清除故障但保留历史", results)
        WT.lastError := oldError
        WT.showProcess := true, WT.showTime := true
        ApplyListPreferences()
        WT.showProcess := false, WT.showTime := false
        ApplyListPreferences()
        width := SendMessage(0x101D, 0, 0, WT.list.Hwnd)
        Assert(width > Round(500 * A_ScreenDPI / 96), "隐藏附属列后标题填满", results)
        WT.showProcess := true, WT.showTime := true
        ApplyListPreferences()
        A_IconHidden := true
        Assert(!TrayExists() && EnsureTray() && TrayExists(), "检测托盘丢失并重建", results)
        UnregisterKeys()
        InitManager()
        Assert(WT.mutex && TrayExists(), "完整启动初始化", results)
        CloseSettings("Discard")
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

PhysicalGeometry(hwnd) {
    previous := DllCall("SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")
    try {
        WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
        return {x: x, y: y, w: w, h: h}
    } finally {
        DllCall("SetThreadDpiAwarenessContext", "Ptr", previous, "Ptr")
    }
}

PlaceFixtureOnMonitor(hwnd, index) {
    previous := DllCall("SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")
    try {
        MonitorGetWorkArea(index, &l, &t, &r, &b)
        WinGetPos(, , &w, &h, "ahk_id " hwnd)
        DllCall("SetWindowPos", "Ptr", hwnd, "Ptr", 0,
            "Int", l + Max(0, (r - l - w) // 2), "Int", t + Max(0, (b - t - h) // 2),
            "Int", 0, "Int", 0, "UInt", 0x15)
        Sleep(100)
    } finally {
        DllCall("SetThreadDpiAwarenessContext", "Ptr", previous, "Ptr")
    }
}

WaitForRestores() {
    global WT
    deadline := A_TickCount + 4000
    while WT.pendingRestore.Count && A_TickCount < deadline {
        Sleep(20)
        PollRestores()
    }
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
    keys := TestKeys()
    for i, action in Actions()
        IniWrite(keys[i], WT.ini, "Hotkeys", action.name)
    InitManager()
    ShowManager()
    ShowSettings()
    ShowManager()
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
