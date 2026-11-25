; SPDX-License-Identifier: GPL-2.0-or-later
; Copyright (C) 2026 JimmeYoumu
#Include SettingsAppearance.ahk

ShowSettings(*) {
    OpenSettings(1)
}

ShowStartup(*) {
    OpenSettings(1)
}

OpenSettings(page := 1) {
    global WT
    if !WT.settings {
        g := Gui(, "WindowTool")
        g.SetFont("s9", "Microsoft YaHei UI")
        WT.settingsPane := g.AddText("x9 y36 w510 h370 +0x04000000", "")
        tabs := g.AddTab3("x9 y9 w510 h28 +0x04000400", ["窗口", "常规", "快捷键", "状态与诊断", "关于"])
        tabs.UseTab()
        InitSettingsAppearance(tabs, WT.settingsPane)
        WT.pageControls := []
        seen := Map(WT.settingsPane.Hwnd, true, tabs.Hwnd, true)
        CreateManagerPage(g)
        WT.pageControls.Push(SettingsPageControls(g, seen))
        g.AddGroupBox("x22 y44 w484 h176", "登录启动")
        WT.startupEnable := g.AddCheckbox("x34 y70 w460", "登录时以管理员身份启动")
        WT.startupStatus := g.AddText("x34 y98 w460 r2 c666666", "")
        WT.startupRepair := g.AddButton("x34 y140 w174 h26", "立即启用并修复自启")
        WT.startupRepair.OnEvent("Click", (*) => ChangeStartup(true))
        g.AddButton("x216 y140 w94 h26", "重新检测").OnEvent("Click", (*) => RefreshStartup())
        g.AddText("x34 y178 w460 r2 c666666", "勾选后点击应用；修复立即生效，取消不会撤销。`n首次设置可能需要管理员授权。")
        g.AddGroupBox("x22 y232 w484 h70", "窗口列表")
        WT.processOption := g.AddCheckbox("x34 y260 w200", "显示所属程序")
        WT.timeOption := g.AddCheckbox("x250 y260 w200", "显示收起时间")
        g.AddGroupBox("x22 y316 w484 h78", "配置文件")
        g.AddButton("x34 y346 w112 h26", "打开配置目录").OnEvent("Click", (*) => Run('explorer.exe "' A_ScriptDir '"'))
        g.AddText("x158 y346 w336 r2 c666666", "配置和窗口恢复记录保存在程序目录，`n升级时请保留。")
        WT.pageControls.Push(SettingsPageControls(g, seen))
        g.AddText("x22 y44 w484 r2", "勾选功能并录制快捷键，点击应用生效。冲突键位会保留。")
        WT.controls := []
        WT.controls.Length := Actions().Length
        y := 80
        ; 显示按 F10 / F11 / F12 排列，控件索引仍对应原配置。
        for row, i in [1, 2, 3, 6, 5, 4, 7, 8, 9, 10] {
            action := Actions()[i]
            if row = 1 || row = 4 || row = 7 {
                g.AddText("x22 y" y " w484 c666666", row = 1 ? "收起与恢复 / 管理" : row = 4 ? "窗口定位" : "其他操作")
                y += 18
            }
            enabled := g.AddCheckbox("x28 y" y " w138 h22", action.label)
            display := g.AddEdit("x168 y" y " w174 h22 ReadOnly", "")
            button := g.AddButton("x350 y" y " w52 h23", "录制…")
            state := g.AddText("x410 y" y " w96 h22", "")
            c := {enabled: enabled, display: display, button: button, state: state, key: ""}
            WT.controls[i] := c
            enabled.OnEvent("Click", (*) => RefreshKeyStates())
            button.OnEvent("Click", StartRecording.Bind(c))
            y += 23
        }
        WT.winF11Option := g.AddCheckbox("x28 y367 w380 h22", "Win+F11 兼容模式（可能拦截 Xbox 快捷键）")
        WT.keyHelp := g.AddText("x28 y393 w478 r1", "更改后点击应用。Esc 取消录制。键盘钩子冲突可能无法检测。")
        WT.xboxSettings := g.AddButton("x394 y371 w112 h26 Hidden", "Xbox 设置…")
        WT.xboxSettings.OnEvent("Click", ShowXboxShortcutHelp)
        WT.pageControls.Push(SettingsPageControls(g, seen))
        WT.diagnostics := g.AddEdit("x22 y46 w484 h278 ReadOnly -Wrap", "")
        g.AddButton("x22 y334 w112 h26", "重新检测快捷键").OnEvent("Click", RetryConfiguredKeys)
        g.AddButton("x142 y334 w112 h26", "修复托盘图标").OnEvent("Click", (*) => RepairTrayFromSettings())
        g.AddButton("x262 y334 w112 h26", "刷新状态").OnEvent("Click", (*) => RefreshDiagnostics())
        g.AddButton("x22 y368 w112 h26", "打开日志").OnEvent("Click", (*) => OpenLocalFile(WT.log))
        g.AddButton("x142 y368 w112 h26", "打开配置目录").OnEvent("Click", (*) => Run('explorer.exe "' A_ScriptDir '"'))
        WT.pageControls.Push(SettingsPageControls(g, seen))
        g.SetFont("s15")
        g.AddText("x34 y64 w460", "WindowTool " WT.version)
        g.SetFont("s9")
        g.AddText("x34 y108 w460 r4", "窗口小助手`n快捷键定位窗口、收起到托盘管理、随时恢复。`nCopyright © 2026 JimmeYoumu")
        g.AddText("x34 y196 w460 r3", "许可证：GPL-2.0-or-later`nAutoHotkey 运行时及第三方许可随发行包提供。")
        g.AddButton("x34 y270 w112 h26", "项目主页").OnEvent("Click", (*) => Run("https://github.com/Jimme/WindowTool"))
        g.AddButton("x154 y270 w112 h26", "查看许可证").OnEvent("Click", ShowLicense)
        WT.updateButton := g.AddButton("x34 y308 w112 h26", "检查更新")
        WT.updateButton.OnEvent("Click", CheckForUpdates)
        WT.releaseButton := g.AddButton("x154 y308 w112 h26 Hidden", "打开发布页")
        WT.releaseButton.OnEvent("Click", (*) => Run("https://github.com/Jimme/WindowTool/releases/latest"))
        WT.updateStatus := g.AddText("x34 y344 w460 r3", "手动检查 GitHub 正式版，不自动下载或安装。")
        WT.pageControls.Push(SettingsPageControls(g, seen))
        WT.keyStatus := g.AddText("x12 y420 w504 r2", "")
        WT.resetButton := g.AddButton("x12 y460 w128 h26", "恢复当前页默认")
        WT.resetButton.OnEvent("Click", ResetSettingsPage)
        WT.okButton := g.AddButton("x288 y460 w70 h26 Default", "确定")
        WT.okButton.OnEvent("Click", (*) => ApplySettings(true))
        cancel := g.AddButton("x368 y460 w70 h26", "取消")
        cancel.OnEvent("Click", (*) => CloseSettings("Discard"))
        apply := g.AddButton("x448 y460 w70 h26", "应用")
        apply.OnEvent("Click", (*) => ApplySettings())
        WT.configButtons := [WT.resetButton, WT.okButton, cancel, apply]
        WT.closeButton := g.AddButton("x448 y460 w70 h26 Hidden", "关闭")
        WT.closeButton.OnEvent("Click", (*) => CloseSettings())
        tabs.OnEvent("Change", SettingsTabChanged)
        g.OnEvent("Close", (*) => (CloseSettings(), true))
        g.OnEvent("Escape", (*) => (CloseSettings(), true))
        WT.settings := g, WT.tabs := tabs
        DllCall("SetWindowPos", "Ptr", WT.settingsPane.Hwnd, "Ptr", 1, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13)
        OnMessage(0x0232, SettingsSizingDone)
        WT.pageMessages := Map(), WT.statusPage := 0
    }
    ; 已打开时保留尚未应用的编辑。
    if !DllCall("IsWindowVisible", "Ptr", WT.settings.Hwnd) {
        CancelRecording()
        FillSettings(WT.configuredKeys.Length ? WT.configuredKeys : WT.keys)
        WT.winF11Option.Value := WT.winF11Hook
        WT.processOption.Value := WT.showProcess
        WT.timeOption.Value := WT.showTime
        RefreshStartup(true)
        WT.pageMessages := Map(), WT.statusPage := 0
        WT.keyStatus.Text := "修改后点击应用生效；取消关闭会放弃未应用的修改。"
    }
    WT.tabs.Value := page + 1
    UpdateSettingsFooter()
    RefreshKeyStates()
    RefreshDiagnostics()
    RefreshManager()
    ShowSettingsLayout()
}

SettingsPageControls(g, seen) {
    controls := []
    for hwnd, ctrl in g {
        if !seen.Has(hwnd) {
            seen[hwnd] := true
            controls.Push(ctrl)
        }
    }
    return controls
}

HideInactiveSettingsPages() {
    global WT
    for page, controls in WT.pageControls {
        if page != WT.tabs.Value
            for ctrl in controls
                ctrl.Visible := false
    }
}

ShowSettingsPageControls() {
    global WT
    for ctrl in WT.pageControls[WT.tabs.Value] {
        if ctrl = WT.xboxSettings || ctrl = WT.managerEmptyTitle || ctrl = WT.managerEmptyDetail
            continue
        ctrl.Visible := ctrl != WT.releaseButton || WT.HasOwnProp("releasePageAvailable") && WT.releasePageAvailable
    }
    UpdateManagerEmpty()
}

ShowSettingsLayout(activate := true) {
    global WT
    manager := WT.tabs.Value = 1
    position := ""
    if HasProp(WT, "settingsPlaced") {
        ; WinGetPos/WinMove 使用同一个屏幕坐标空间，避免把 GUI 尺寸的 DPI 换算叠加到坐标。
        WT.settings.GetPos(&x, &y)
        position := " x" x " y" y
    }
    WT.settings.Show("w528 h" (manager ? 304 : 496) position (activate ? "" : " NA"))
    WT.settingsPlaced := true
    FitSettingsToWorkArea()
    SizeSettingsFrame(manager ? 259 : 376)
    ; 先按目标页面定尺寸，再显示该页控件，防止原生控件在旧布局中重绘。
    ShowSettingsPageControls()
    ; 尺寸和可见性全部就绪后，重画父窗口与子控件，清除旧尺寸留下的像素。
    DllCall("RedrawWindow", "Ptr", WT.settings.Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x185)
}

SettingsSizingDone(wParam, lParam, msg, hwnd) {
    global WT
    if IsSet(WT) && WT.settings && hwnd = WT.settings.Hwnd
        SetTimer(FitSettingsToWorkArea, -1)
}

FitSettingsToWorkArea() {
    global WT
    if !IsSet(WT) || !WT.settings || !DllCall("IsWindowVisible", "Ptr", WT.settings.Hwnd)
        return
    hwnd := WT.settings.Hwnd, target := "ahk_id " hwnd
    WinGetPos(&x, &y, &width, &height, target)
    if GetWorkArea(hwnd, &left, &top, &right, &bottom) {
        fittedWidth := Min(width, right - left), fittedHeight := Min(height, bottom - top)
        fittedX := Min(Max(x, left), right - fittedWidth), fittedY := Min(Max(y, top), bottom - fittedHeight)
        if fittedX != x || fittedY != y || fittedWidth != width || fittedHeight != height
            WinMove(fittedX, fittedY, fittedWidth, fittedHeight, target)
    }
}

UpdateSettingsFooter() {
    global WT
    if WT.statusPage
        WT.pageMessages[WT.statusPage] := WT.keyStatus.Text
    WT.statusPage := WT.tabs.Value
    WT.keyStatus.Text := WT.pageMessages.Has(WT.statusPage) ? WT.pageMessages[WT.statusPage]
        : WT.statusPage = 4 ? "诊断操作立即生效，不修改尚未应用的设置。"
        : "修改后点击应用生效；取消会放弃未应用的修改。"
    HideInactiveSettingsPages()
    config := WT.tabs.Value = 2 || WT.tabs.Value = 3
    for button in WT.configButtons
        button.Visible := config
    WT.keyStatus.Visible := config || WT.tabs.Value = 4
    WT.resetButton.Enabled := config
    WT.closeButton.Visible := !config
    WT.closeButton.Move(WT.tabs.Value = 1 ? 442 : 448, WT.tabs.Value = 1 ? 262 : 460,
        WT.tabs.Value = 1 ? 69 : 70, WT.tabs.Value = 1 ? 25 : 26)
    WT.okButton.Opt(config ? "+Default" : "-Default")
    WT.closeButton.Opt(config ? "-Default" : "+Default")
    ToolTip()
    WT.hoverControl := 0, WT.hoverSince := 0
    SetTimer(ManagerHint, WT.tabs.Value = 1 ? 100 : 0)
    if WT.tabs.Value = 1
        RefreshManager()
}

SettingsTabChanged(*) {
    global WT
    CancelRecording()
    UpdateSettingsFooter()
    RefreshKeyStates()
    if WT.tabs.Value = 4
        RefreshDiagnostics()
    ShowSettingsLayout(false)
}

RefreshKeyStates() {
    global WT
    if !WT.settings
        return
    hotkeyPage := WT.tabs.Value = 3
    xboxConflict := false
    for i, c in WT.controls {
        desired := c.enabled.Value ? c.key : ""
        saved := WT.configuredKeys.Length >= i ? WT.configuredKeys[i] : ""
        c.state.Text := c.enabled.Value && c.key = "" ? "待录制"
            : desired != saved ? (desired = "" ? "待停用" : saved = "" ? "待启用" : "待修改")
            : WT.keyErrors.Has(i) ? "冲突（已保留）" : WT.keys.Length >= i && WT.keys[i] != "" ? "运行中" : "未启用"
        if hotkeyPage && !xboxConflict && desired != "" {
            ; 比较组合签名，也识别旧配置中使用 vk7A 的同一键位。
            try xboxConflict := ParseKey(desired).signature = "8:122"
        }
    }
    WT.winF11Option.Visible := hotkeyPage
    WT.keyHelp.Visible := hotkeyPage
    WT.xboxSettings.Visible := xboxConflict
}

ShowXboxShortcutHelp(*) {
    global WT
    CancelRecording()
    answer := MsgBox(
        "Win+F11 可进入或退出 Xbox 模式。若要保留这个键位给 WindowTool，可在 Windows 设置 → 游戏 → Xbox 模式关闭该功能。"
        . "`n`n普通电脑关闭「启用 Xbox 模式」。游戏掌机可把主页应用选为「无」。"
        . "`n`n关闭 Xbox 模式后若 Win+F11 仍被占用，可勾选「Win+F11 兼容模式」并应用。兼容模式可能优先于其他使用该键的软件。"
        . "`n`n现在打开 Windows 的 Xbox 模式设置？", "WindowTool", "OKCancel Iconi Owner" WT.settings.Hwnd)
    if answer != "OK"
        return
    try Run("ms-settings:gaming-fullscreen")
    catch Error
        WT.keyStatus.Text := "无法打开 Xbox 模式设置。请在 Windows 设置 → 游戏中查找「Xbox 模式」。"
}

ApplySettings(closeAfter := false) {
    global WT
    WT.saveFailurePage := 2
    wantedStartup := WT.startupEnable.Value
    if !SaveSettings(WT.controls, WT.keyStatus, {process: WT.processOption.Value, time: WT.timeOption.Value},
        !!WT.winF11Option.Value)
        return false
    if WT.startupEnable.Enabled && wantedStartup != WT.startupBaseline {
        if !ChangeStartup(wantedStartup) {
            WT.saveFailurePage := 1
            WT.keyStatus.Text := "快捷键与列表设置已保存；自启修改未完成，请查看常规页的实际状态。"
            RefreshKeyStates()
            return false
        }
    }
    RefreshKeyStates()
    RefreshDiagnostics()
    if closeAfter
        CloseSettings("Discard")
    return true
}

HasUnsavedSettings() {
    global WT
    if !WT.settings
        return false
    for i, c in WT.controls {
        saved := WT.configuredKeys.Length >= i ? WT.configuredKeys[i] : WT.keys[i]
        if !!c.enabled.Value != (saved != "") || (c.enabled.Value && c.key != saved)
            return true
    }
    return WT.processOption.Value != WT.showProcess || WT.timeOption.Value != WT.showTime
        || !!WT.winF11Option.Value != WT.winF11Hook
        || (WT.startupEnable.Enabled && WT.startupEnable.Value != WT.startupBaseline)
}

ShowLicense(*) {
    global WT
    if !HasProp(WT, "licenseGui") || !WT.licenseGui {
        license := ReadLicense()
        g := Gui("+Owner" WT.settings.Hwnd, "WindowTool")
        g.SetFont("s9", "Microsoft YaHei UI")
        g.AddEdit("w520 r24 ReadOnly", license)
        g.AddButton("xm w80", "关闭").OnEvent("Click", (*) => g.Hide())
        g.OnEvent("Close", (*) => g.Hide())
        g.OnEvent("Escape", (*) => g.Hide())
        WT.licenseGui := g
    }
    WT.licenseGui.Show()
}

ReadLicense() {
    if !A_IsCompiled
        return FileRead(A_ScriptDir "\LICENSE", "UTF-8")
    ; 编译版内嵌许可，源码版按脚本绝对路径读取。
    path := A_Temp "\WindowTool-license-" DllCall("GetCurrentProcessId") ".txt"
    try {
        FileInstall("LICENSE", path, true)
        return FileRead(path, "UTF-8")
    } finally {
        if FileExist(path)
            FileDelete(path)
    }
}

ResetSettingsPage(*) {
    global WT
    if WT.tabs.Value = 3 {
        FillSettings(DefaultKeys())
        WT.winF11Option.Value := false
        WT.keyStatus.Text := "本页已恢复默认，点击应用后生效。"
    } else if WT.tabs.Value = 2 {
        WT.startupEnable.Value := false
        WT.processOption.Value := true, WT.timeOption.Value := true
        WT.keyStatus.Text := "本页已恢复默认（自启关闭、显示程序与时间），点击应用后生效。"
    } else
        WT.keyStatus.Text := "当前页没有可重置的配置。"
    RefreshKeyStates()
}

RetryConfiguredKeys(*) {
    global WT
    CancelRecording()
    StartKeys(WT.configuredKeys.Length ? WT.configuredKeys : LoadKeys())
    RefreshKeyStates()
    RefreshDiagnostics()
    UpdateSummary()
    WT.keyStatus.Text := WT.keyErrors.Count ? "仍有 " WT.keyErrors.Count " 项不可用，详见状态与诊断。" : "已重新检测，已配置快捷键均可用。"
}

RefreshDiagnostics() {
    global WT
    if !WT.settings
        return
    text := "版本：" WT.version "`r`n运行权限：" (A_IsAdmin ? "管理员" : "普通用户")
        . "`r`n程序路径：" A_ScriptFullPath "`r`n配置文件：" WT.ini
        . "`r`n日志文件：" WT.log "`r`n恢复记录：" (WT.recoveryBlocked ? "异常，已禁止继续收起" : "正常")
        . "`r`n已收起窗口：" WT.windows.Count "；等待恢复：" WT.pendingRestore.Count
        . "`r`n`r`n自启（点击常规页重新检测可更新）：`r`n" (HasProp(WT, "startupDetails") ? WT.startupDetails : WT.startupStatus.Text)
    for i, errorText in WT.keyErrors
        text .= "`r`n`r`n" Actions()[i].label "：" errorText
    if WT.bindings.Has("8:122")
        text .= "`r`n`r`nWin+F11：" (WT.bindings["8:122"].hook != "" ? "已绑定（键盘钩子）" : "已绑定（系统注册）")
    else if WT.winF11Hook
        text .= "`r`n`r`nWin+F11：兼容模式已开启，当前无生效绑定。"
    for scope, errorText in WT.activeIssues
        text .= "`r`n`r`n当前问题：" errorText
    if WT.lastError != ""
        text .= "`r`n`r`n最近一次错误（历史记录）：" WT.lastError
    if WT.warnings != ""
        text .= "`r`n`r`n" WT.warnings
    WT.diagnostics.Value := text
}

RepairTrayFromSettings() {
    global WT
    StartTrayRecovery()
    WT.keyStatus.Text := TrayExists() ? "托盘图标已存在。Windows 可能将其放在折叠区。" : "托盘尚未恢复，正在重试。"
}

OpenLocalFile(path) {
    if !FileExist(path) {
        MsgBox("文件尚未生成或不存在：`n" path, "WindowTool")
        return
    }
    Run('notepad.exe "' path '"')
}
