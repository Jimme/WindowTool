; SPDX-License-Identifier: GPL-2.0-or-later
; Copyright (C) 2026 JimmeYoumu
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
        tabs := g.AddTab3("x10 y10 w540 h402", ["窗口", "常规", "快捷键", "状态与诊断", "关于"])
        tabs.UseTab(1)
        CreateManagerPage(g)
        tabs.UseTab(2)
        g.AddGroupBox("x22 y44 w516 h176", "登录启动")
        WT.startupEnable := g.AddCheckbox("x34 y70 w490", "登录时以管理员身份启动")
        WT.startupStatus := g.AddText("x34 y98 w490 r2 c666666", "")
        WT.startupRepair := g.AddButton("x34 y140 w174 h26", "立即启用并修复自启")
        WT.startupRepair.OnEvent("Click", (*) => ChangeStartup(true))
        g.AddButton("x216 y140 w94 h26", "重新检测").OnEvent("Click", (*) => RefreshStartup())
        g.AddText("x34 y178 w490 r2 c666666", "勾选后点击应用；修复立即生效，取消不会撤销。`n首次设置可能需要管理员授权。")
        g.AddGroupBox("x22 y232 w516 h70", "窗口列表")
        WT.processOption := g.AddCheckbox("x34 y260 w200", "显示所属程序")
        WT.timeOption := g.AddCheckbox("x250 y260 w200", "显示收起时间")
        g.AddGroupBox("x22 y316 w516 h78", "配置文件")
        g.AddButton("x34 y346 w112 h26", "打开配置目录").OnEvent("Click", (*) => Run('explorer.exe "' A_ScriptDir '"'))
        g.AddText("x158 y346 w366 r2 c666666", "配置和窗口恢复记录保存在程序目录，`n升级时请保留。")
        tabs.UseTab(3)
        g.AddText("x22 y44 w516 r2", "勾选功能并录制快捷键，点击应用生效。冲突键位会保留。")
        WT.controls := []
        WT.controls.Length := Actions().Length
        y := 80
        ; 显示按 F10 / F11 / F12 排列，控件索引仍对应原配置。
        for row, i in [1, 2, 3, 6, 5, 4, 7, 8, 9, 10] {
            action := Actions()[i]
            if row = 1 || row = 4 || row = 7 {
                g.AddText("x22 y" y " w516 c666666", row = 1 ? "收起与恢复 / 管理" : row = 4 ? "窗口定位" : "其他操作")
                y += 18
            }
            enabled := g.AddCheckbox("x28 y" y " w138 h22", action.label)
            display := g.AddEdit("x168 y" y " w174 h22 ReadOnly", "")
            button := g.AddButton("x350 y" y " w52 h23", "录制…")
            state := g.AddText("x410 y" y " w126 h22", "")
            c := {enabled: enabled, display: display, button: button, state: state, key: ""}
            WT.controls[i] := c
            enabled.OnEvent("Click", (*) => RefreshKeyStates())
            button.OnEvent("Click", StartRecording.Bind(c))
            y += 23
        }
        g.AddText("x28 y370 w500 r2", "Esc 取消录制。CapsLock / F12 的钩子冲突可能无法检测。")
        tabs.UseTab(4)
        WT.diagnostics := g.AddEdit("x22 y46 w516 h278 ReadOnly -Wrap", "")
        g.AddButton("x22 y334 w112 h26", "重新检测快捷键").OnEvent("Click", RetryConfiguredKeys)
        g.AddButton("x142 y334 w112 h26", "修复托盘图标").OnEvent("Click", (*) => RepairTrayFromSettings())
        g.AddButton("x262 y334 w112 h26", "刷新状态").OnEvent("Click", (*) => RefreshDiagnostics())
        g.AddButton("x22 y368 w112 h26", "打开日志").OnEvent("Click", (*) => OpenLocalFile(WT.log))
        g.AddButton("x142 y368 w112 h26", "打开配置目录").OnEvent("Click", (*) => Run('explorer.exe "' A_ScriptDir '"'))
        tabs.UseTab(5)
        g.SetFont("s15")
        g.AddText("x34 y64 w490", "WindowTool " WT.version)
        g.SetFont("s9")
        g.AddText("x34 y108 w490 r4", "窗口小助手`n快捷键定位窗口、收起到托盘管理、随时恢复。`nCopyright © 2026 JimmeYoumu")
        g.AddText("x34 y196 w490 r3", "许可证：GPL-2.0-or-later`nAutoHotkey 运行时及第三方许可随发行包提供。")
        g.AddButton("x34 y270 w112 h26", "项目主页").OnEvent("Click", (*) => Run("https://github.com/Jimme/WindowTool"))
        g.AddButton("x154 y270 w112 h26", "查看许可证").OnEvent("Click", ShowLicense)
        WT.updateButton := g.AddButton("x34 y308 w112 h26", "检查更新")
        WT.updateButton.OnEvent("Click", CheckForUpdates)
        WT.releaseButton := g.AddButton("x154 y308 w112 h26 Hidden", "打开发布页")
        WT.releaseButton.OnEvent("Click", (*) => Run("https://github.com/Jimme/WindowTool/releases/latest"))
        WT.updateStatus := g.AddText("x34 y344 w490 r3", "手动检查 GitHub 正式版，不自动下载或安装。")
        tabs.UseTab()
        g.AddText("x10 y416 w540 h2 0x10", "")
        WT.summary := g.AddText("x12 y426 w536 r1 c666666", "")
        WT.keyStatus := g.AddText("x12 y420 w536 r2", "")
        WT.resetButton := g.AddButton("x12 y460 w128 h26", "恢复当前页默认")
        WT.resetButton.OnEvent("Click", ResetSettingsPage)
        WT.okButton := g.AddButton("x320 y460 w70 h26 Default", "确定")
        WT.okButton.OnEvent("Click", (*) => ApplySettings(true))
        cancel := g.AddButton("x400 y460 w70 h26", "取消")
        cancel.OnEvent("Click", (*) => CloseSettings("Discard"))
        apply := g.AddButton("x480 y460 w70 h26", "应用")
        apply.OnEvent("Click", (*) => ApplySettings())
        WT.configButtons := [WT.resetButton, WT.okButton, cancel, apply]
        WT.closeButton := g.AddButton("x480 y460 w70 h26 Hidden", "关闭")
        WT.closeButton.OnEvent("Click", (*) => CloseSettings())
        tabs.OnEvent("Change", SettingsTabChanged)
        g.OnEvent("Close", (*) => (CloseSettings(), true))
        g.OnEvent("Escape", (*) => (CloseSettings(), true))
        WT.settings := g, WT.tabs := tabs
        WT.pageMessages := Map(), WT.statusPage := 0
    }
    ; 已打开时保留尚未应用的编辑。
    if !DllCall("IsWindowVisible", "Ptr", WT.settings.Hwnd) {
        CancelRecording()
        FillSettings(WT.configuredKeys.Length ? WT.configuredKeys : WT.keys)
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
    WT.settings.Show("w560 h496")
}

UpdateSettingsFooter() {
    global WT
    if WT.statusPage
        WT.pageMessages[WT.statusPage] := WT.keyStatus.Text
    WT.statusPage := WT.tabs.Value
    WT.keyStatus.Text := WT.pageMessages.Has(WT.statusPage) ? WT.pageMessages[WT.statusPage]
        : WT.statusPage = 4 ? "诊断操作立即生效，不修改尚未应用的设置。"
        : "修改后点击应用生效；取消会放弃未应用的修改。"
    config := WT.tabs.Value = 2 || WT.tabs.Value = 3
    for button in WT.configButtons
        button.Visible := config
    WT.keyStatus.Visible := config || WT.tabs.Value = 4
    WT.summary.Visible := WT.tabs.Value = 1
    WT.resetButton.Enabled := config
    WT.closeButton.Visible := !config
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
}

RefreshKeyStates() {
    global WT
    if !WT.settings
        return
    for i, c in WT.controls {
        desired := c.enabled.Value ? c.key : ""
        saved := WT.configuredKeys.Length >= i ? WT.configuredKeys[i] : ""
        c.state.Text := c.enabled.Value && c.key = "" ? "待录制"
            : desired != saved ? (desired = "" ? "待停用" : saved = "" ? "待启用" : "待修改")
            : WT.keyErrors.Has(i) ? "冲突（已保留）" : WT.keys.Length >= i && WT.keys[i] != "" ? "运行中" : "未启用"
    }
}

ApplySettings(closeAfter := false) {
    global WT
    WT.saveFailurePage := 2
    wantedStartup := WT.startupEnable.Value
    if !SaveSettings(WT.controls, WT.keyStatus, {process: WT.processOption.Value, time: WT.timeOption.Value})
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
