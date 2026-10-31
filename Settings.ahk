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
        g := Gui(, "WindowTool 设置 — v" WT.version)
        g.SetFont("s10", "Microsoft YaHei UI")
        tabs := g.AddTab3("x16 y16 w728 h510", ["常规", "快捷键", "状态与诊断", "关于"])
        tabs.UseTab(1)
        g.AddGroupBox("x32 y58 w696 h220", "登录启动")
        WT.startupEnable := g.AddCheckbox("x48 y88 w640", "当前用户登录时，以管理员身份启动")
        WT.startupStatus := g.AddEdit("x48 y122 w660 h110 ReadOnly -Wrap", "")
        WT.startupRepair := g.AddButton("x48 y240 w190", "更新为当前路径（立即）")
        WT.startupRepair.OnEvent("Click", (*) => ChangeStartup(true))
        g.AddButton("x250 y240 w130", "重新检测").OnEvent("Click", (*) => RefreshStartup())
        g.AddText("x48 y290 w660 r3", "登录后延迟 10 秒启动，首次设置可能需要管理员授权。`n启用时备份匹配的旧自启快捷方式；关闭后不会恢复旧自启。")
        g.AddGroupBox("x32 y360 w696 h100", "窗口列表")
        WT.processOption := g.AddCheckbox("x48 y392 w220", "显示所属程序")
        WT.timeOption := g.AddCheckbox("x300 y392 w220", "显示收起时间")
        tabs.UseTab(2)
        g.AddText("x32 y58 w690", "录制组合键后点击应用；冲突键位会保留，可到“状态与诊断”重新检测。")
        WT.controls := []
        y := 88
        for i, action in Actions() {
            if i = 1 || i = 4 || i = 7 {
                g.AddText("x32 y" y " w690 c666666", i = 1 ? "收起与恢复 / 管理" : i = 4 ? "窗口定位" : "其他操作")
                y += 25
            }
            enabled := g.AddCheckbox("x40 y" y " w170 h24", action.label)
            display := g.AddEdit("x218 y" y " w218 h24 ReadOnly", "")
            button := g.AddButton("x446 y" y " w72 h26", "录制…")
            state := g.AddText("x530 y" y " w190 h26", "")
            c := {enabled: enabled, display: display, button: button, state: state, key: ""}
            WT.controls.Push(c)
            button.OnEvent("Click", StartRecording.Bind(c))
            y += 29
        }
        g.AddText("x40 y474 w680 r2", "Esc 取消录制。CapsLock / F12 使用键盘钩子，无法完整检测其他钩子的冲突。")
        tabs.UseTab(3)
        WT.diagnostics := g.AddEdit("x32 y60 w696 h335 ReadOnly -Wrap", "")
        g.AddButton("x32 y412 w150", "重新检测快捷键").OnEvent("Click", RetryConfiguredKeys)
        g.AddButton("x194 y412 w140", "修复托盘图标").OnEvent("Click", (*) => RepairTrayFromSettings())
        g.AddButton("x346 y412 w140", "刷新状态").OnEvent("Click", (*) => RefreshDiagnostics())
        g.AddButton("x32 y456 w150", "打开日志").OnEvent("Click", (*) => OpenLocalFile(WT.log))
        g.AddButton("x194 y456 w140", "打开配置目录").OnEvent("Click", (*) => Run('explorer.exe "' A_ScriptDir '"'))
        tabs.UseTab(4)
        g.SetFont("s18")
        g.AddText("x44 y80 w640", "WindowTool " WT.version)
        g.SetFont("s10")
        g.AddText("x44 y132 w640 r4", "窗口小助手`n快捷键定位窗口、收起到托盘管理、随时恢复。`nCopyright © 2026 JimmeYoumu")
        g.AddText("x44 y240 w640 r3", "许可证：GPL-2.0-or-later`nAutoHotkey 运行时及第三方许可随发行包提供。")
        g.AddButton("x44 y330 w150", "项目主页").OnEvent("Click", (*) => Run("https://github.com/Jimme/WindowTool"))
        g.AddButton("x206 y330 w150", "查看许可证").OnEvent("Click", (*) => OpenLocalFile(A_ScriptDir "\LICENSE"))
        tabs.UseTab()
        WT.keyStatus := g.AddText("x20 y536 w720 r3", "")
        g.AddButton("x20 y602 w150", "恢复当前页默认").OnEvent("Click", ResetSettingsPage)
        g.AddButton("x452 y602 w90 Default", "确定").OnEvent("Click", (*) => ApplySettings(true))
        g.AddButton("x552 y602 w90", "取消").OnEvent("Click", (*) => CloseSettings())
        g.AddButton("x652 y602 w90", "应用").OnEvent("Click", (*) => ApplySettings())
        tabs.OnEvent("Change", SettingsTabChanged)
        g.OnEvent("Close", (*) => CloseSettings())
        g.OnEvent("Escape", (*) => CloseSettings())
        WT.settings := g, WT.tabs := tabs
    }
    ; 已打开时保留尚未应用的编辑。
    if !DllCall("IsWindowVisible", "Ptr", WT.settings.Hwnd) {
        CancelRecording()
        FillSettings(WT.configuredKeys.Length ? WT.configuredKeys : WT.keys)
        WT.processOption.Value := WT.showProcess
        WT.timeOption.Value := WT.showTime
        RefreshStartup()
        WT.keyStatus.Text := "修改后点击应用生效；取消关闭会放弃未应用的修改。"
    }
    WT.tabs.Value := page
    RefreshKeyStates()
    RefreshDiagnostics()
    WT.settings.Show("w760 h650")
}

SettingsTabChanged(*) {
    global WT
    CancelRecording()
    RefreshKeyStates()
    if WT.tabs.Value = 3
        RefreshDiagnostics()
}

RefreshKeyStates() {
    global WT
    if !WT.settings
        return
    for i, c in WT.controls
        c.state.Text := WT.keyErrors.Has(i) ? "暂不可用（键位保留）" : WT.keys.Length >= i && WT.keys[i] != "" ? "运行中" : "未启用"
}

ApplySettings(closeAfter := false) {
    global WT
    wantedStartup := WT.startupEnable.Value
    if !SaveSettings(WT.controls, WT.keyStatus, {process: WT.processOption.Value, time: WT.timeOption.Value})
        return false
    if WT.startupEnable.Enabled && wantedStartup != WT.startupBaseline {
        if !ChangeStartup(wantedStartup) {
            WT.keyStatus.Text := "快捷键与列表设置已保存；自启修改未完成，请查看常规页的实际状态。"
            RefreshKeyStates()
            return false
        }
    }
    RefreshKeyStates()
    RefreshDiagnostics()
    if closeAfter
        CloseSettings()
    return true
}

ResetSettingsPage(*) {
    global WT
    if WT.tabs.Value = 2 {
        FillSettings(DefaultKeys())
        WT.keyStatus.Text := "本页已恢复默认，点击应用后生效。"
    } else if WT.tabs.Value = 1 {
        WT.startupEnable.Value := false
        WT.processOption.Value := true, WT.timeOption.Value := true
        WT.keyStatus.Text := "本页已恢复默认（自启关闭、显示程序与时间），点击应用后生效。"
    } else
        WT.keyStatus.Text := "当前页没有可重置的配置。"
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
        . "`r`n`r`n自启（点击常规页重新检测可更新）：`r`n" WT.startupStatus.Text
    for i, errorText in WT.keyErrors
        text .= "`r`n`r`n" Actions()[i].label "：" errorText
    if WT.lastError != ""
        text .= "`r`n`r`n最近错误：" WT.lastError
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
