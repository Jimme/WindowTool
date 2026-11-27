; SPDX-License-Identifier: GPL-2.0-or-later
; Copyright (C) 2026 JimmeYoumu
#Include SettingsAppearance.ahk

global WTSettingsLayout := {frameTop: 36, frameBottomMargin: 9, footerPadding: 6, footerButtonHeight: 24,
    pageHeights: [304, 284, 416, 292, 232]}

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
        WT.settingsPane := g.AddText("x9 y" WTSettingsLayout.frameTop " w510 h370 +0x04000000", "")
        tabs := g.AddTab3("x9 y9 w510 h28 +0x04000000", ["窗口", "常规", "快捷键", "状态与诊断", "关于"])
        tabs.UseTab()
        InitSettingsAppearance(tabs, WT.settingsPane)
        g.BackColor := Format("{:06X}", SettingsSurfaceColor())
        WT.pageControls := []
        seen := Map(WT.settingsPane.Hwnd, true, tabs.Hwnd, true)
        CreateManagerPage(g)
        WT.pageControls.Push(SettingsPageControls(g, seen))
        CreateGeneralPage(g)
        WT.pageControls.Push(SettingsPageControls(g, seen))
        CreateHotkeyPage(g)
        WT.pageControls.Push(SettingsPageControls(g, seen))
        CreateDiagnosticsPage(g)
        WT.pageControls.Push(SettingsPageControls(g, seen))
        CreateAboutPage(g)
        WT.pageControls.Push(SettingsPageControls(g, seen))
        WT.keyStatus := g.AddText("x20 y254 w407 h24 +0x4300", "")
        WT.resetButton := g.AddButton("x12 y460 w128 h26", "恢复本页默认")
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
        OnMessage(0x114, SettingsScroll)
        OnMessage(0x115, SettingsScroll)
        OnMessage(0x20A, SettingsWheel)
        WT.pageMessages := Map(), WT.statusPage := 0
    }
    ; 已打开时保留尚未应用的编辑。
    ResetSettingsViewport()
    if !DllCall("IsWindowVisible", "Ptr", WT.settings.Hwnd) {
        CancelRecording()
        FillSettings(WT.configuredKeys.Length ? WT.configuredKeys : WT.keys)
        WT.winF11Option.Value := WT.winF11Hook
        WT.processOption.Value := WT.showProcess
        WT.timeOption.Value := WT.showTime
        RefreshStartup(true)
        WT.pageMessages := Map(), WT.statusPage := 0
        WT.keyStatus.Text := ""
    }
    WT.tabs.Value := page + 1
    UpdateSettingsFooter()
    RefreshDiagnostics()
    RefreshManager()
    ShowSettingsLayout()
}

CreateGeneralPage(g) {
    global WT
    AddSettingsGroup(g, "x17 y46 w494 h84", "登录启动")
    WT.startupEnable := g.AddCheckbox("x29 y61 w247 h21", "登录时以管理员身份启动")
    WT.startupStatus := g.AddText("x278 y61 w136 h21 +0x200", "")
    g.AddButton("x29 y90 w78 h24", "重新检测").OnEvent("Click", (*) => RefreshStartup())
    WT.startupRepair := g.AddButton("x417 y60 w83 h24 Hidden", "立即修复")
    WT.startupRepair.OnEvent("Click", (*) => (ChangeStartup(true), SettingsOptionChanged()))
    WT.startupNote := g.AddText("x118 y88 w382 h34", "")
    AddSettingsGroup(g, "x17 y137 w494 h45", "窗口列表")
    WT.processOption := g.AddCheckbox("x29 y152 w178 h22", "显示所属程序")
    WT.timeOption := g.AddCheckbox("x215 y152 w178 h22", "显示收起时间")
    AddSettingsGroup(g, "x17 y190 w494 h47", "配置文件")
    g.AddButton("x29 y205 w101 h24", "打开配置目录").OnEvent("Click", (*) => Run('explorer.exe "' A_ScriptDir '"'))
    g.AddText("x141 y206 w359 h22 +0x200", "升级时保留配置与窗口恢复记录")
    for control in [WT.startupEnable, WT.processOption, WT.timeOption]
        control.OnEvent("Click", SettingsOptionChanged)
}

CreateHotkeyPage(g) {
    global WT
    WT.controls := []
    WT.controls.Length := Actions().Length
    WT.keyHints := Map()
    y := 45
    ; 显示按 F10 / F11 / F12 排列，索引仍对应原配置。
    for row, i in [1, 2, 3, 6, 5, 4, 7, 8, 9, 10] {
        if row = 1 || row = 4 || row = 7 {
            g.SetFont("w600")
            title := row = 1 ? "收起、恢复与管理" : row = 4 ? "窗口定位" : "其他操作"
            heading := g.AddText("x20 y" y " w488 h18", title)
            g.SetFont("w400")
            SubclassSettingsControl(heading, 6)
            y += 18
        }
        enabled := g.AddCheckbox("x20 y" y " w150 h21", Actions()[i].label)
        display := g.AddButton("x177 y" y " w215 h21", "未设置")
        state := g.AddText("x407 y" y " w100 h21 +0x300", "")
        help := g.AddButton("x403 y" y " w108 h21 Hidden", "Win+F11 被占用")
        help.OnEvent("Click", ShowXboxShortcutHelp)
        c := {enabled: enabled, display: display, state: state, help: help, key: ""}
        WT.controls[i] := c
        WT.keyHints[display.Hwnd] := c, WT.keyHints[state.Hwnd] := c
        SubclassSettingsControl(display, 4, i)
        SubclassSettingsControl(state, 5, i)
        enabled.OnEvent("Click", SettingsOptionChanged)
        display.OnEvent("Click", ActivateKeyField.Bind(c))
        y += 23
        if row = 3 || row = 6
            y += 5
    }
    WT.winF11Option := g.AddCheckbox("x20 y348 w380 h21", "Win+F11 兼容模式（可能拦截 Xbox 快捷键）")
    WT.winF11Option.OnEvent("Click", SettingsOptionChanged)
    WT.xboxSettings := g.AddButton("x404 y347 w106 h23 Hidden", "Xbox 设置…")
    WT.xboxSettings.OnEvent("Click", ShowXboxShortcutHelp)
}

CreateDiagnosticsPage(g) {
    global WT
    ; 视图控件由页面统一切换。二级导航无需 Tab3 的内部页面窗口占用绘制区域。
    WT.diagnosticTabs := g.AddTab2("x20 y46 w488 h27", ["概况", "详细信息"])
    WT.diagnosticTabs.UseTab()
    SubclassSettingsControl(WT.diagnosticTabs, 7)
    SetSettingsTabPadding(WT.diagnosticTabs.Hwnd)
    WT.diagnosticTabs.OnEvent("Change", ShowDiagnosticView)
    WT.diagnosticOverview := Map(), WT.diagnosticValues := []
    for index, label in ["运行权限", "快捷键", "托盘图标", "登录启动", "窗口恢复"] {
        y := 78 + (index - 1) * 27
        title := g.AddText("x20 y" y " w90 h22 +0x200", label)
        value := g.AddText("x114 y" y " w219 h22 +0x4300", "")
        WT.diagnosticOverview[title.Hwnd] := title, WT.diagnosticOverview[value.Hwnd] := value
        WT.diagnosticValues.Push(value)
    }
    WT.locateConflict := g.AddButton("x340 y105 w77 h23", "定位冲突")
    WT.locateConflict.OnEvent("Click", LocateShortcutConflict)
    retry := g.AddButton("x425 y105 w85 h23", "重新检测")
    retry.OnEvent("Click", RetryConfiguredKeys)
    repair := g.AddButton("x425 y132 w85 h23", "修复托盘")
    repair.OnEvent("Click", RepairTrayFromSettings)
    startup := g.AddButton("x425 y159 w85 h23", "前往常规")
    startup.OnEvent("Click", ShowStartup)
    for button in [WT.locateConflict, retry, repair, startup]
        WT.diagnosticOverview[button.Hwnd] := button
    WT.diagnostics := g.AddEdit("x20 y78 w490 h141 ReadOnly -Wrap HScroll VScroll", "")
    RefreshDiagnosticColors()
    g.AddButton("x20 y224 w76 h23", "刷新状态").OnEvent("Click", RefreshDiagnosticsPage)
    g.AddButton("x104 y224 w76 h23", "打开日志").OnEvent("Click", (*) => OpenLocalFile(WT.log))
    g.AddButton("x188 y224 w102 h23", "打开配置目录").OnEvent("Click", (*) => Run('explorer.exe "' A_ScriptDir '"'))
}

CreateAboutPage(g) {
    global WT
    g.SetFont("s10 w600")
    g.AddText("x20 y46 w287 h23 +0x200", "WindowTool " WT.version)
    g.SetFont("s9 w400")
    g.AddButton("x338 y46 w79 h23", "项目主页").OnEvent("Click", (*) => Run("https://github.com/Jimme/WindowTool"))
    g.AddButton("x425 y46 w85 h23", "查看许可证").OnEvent("Click", ShowLicense)
    g.AddText("x20 y70 w490 h19 +0x200", "快捷键定位窗口、收起到托盘管理、随时恢复。")
    g.AddText("x20 y90 w490 h18 +0x200", "GPL-2.0-or-later  ·  Copyright © 2026 JimmeYoumu")
    AddSettingsGroup(g, "x17 y110 w494 h78", "版本更新")
    WT.updateButton := g.AddButton("x29 y131 w95 h21", "检查更新")
    WT.updateButton.OnEvent("Click", CheckForUpdates)
    WT.releaseButton := g.AddButton("x132 y131 w95 h21", "打开发布页")
    WT.releaseButton.OnEvent("Click", (*) => Run("https://github.com/Jimme/WindowTool/releases"))
    WT.updateStatus := g.AddText("x29 y155 w469 h32 +0x100", "手动检查 GitHub 正式版，不自动下载或安装。")
}

SettingsOptionChanged(*) {
    global WT
    WT.keyStatus.Text := HasUnsavedSettings() ? "有未应用的修改" : ""
    RefreshKeyStates()
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
            || ctrl = WT.diagnostics || WT.diagnosticOverview.Has(ctrl.Hwnd)
            continue
        ctrl.Visible := true
    }
    if WT.tabs.Value = 4
        ShowDiagnosticView()
    WT.startupRepair.Visible := WT.tabs.Value = 2 && WT.startupRepair.Enabled
    RefreshKeyStates()
    UpdateManagerEmpty()
}

ShowSettingsLayout(activate := true) {
    global WT
    position := ""
    if HasProp(WT, "settingsPlaced") {
        ; WinGetPos/WinMove 使用同一个屏幕坐标空间，避免把 GUI 尺寸的 DPI 换算叠加到坐标。
        WT.settings.GetPos(&x, &y)
        position := " x" x " y" y
    }
    height := WTSettingsLayout.pageHeights[WT.tabs.Value]
    WT.settings.Show("w528 h" height position (activate ? "" : " NA"))
    WT.settingsPlaced := true
    ; 先按目标页面定尺寸，再显示该页控件，防止原生控件在旧布局中重绘。
    ShowSettingsPageControls()
    FitSettingsToWorkArea()
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
    ResetSettingsViewport()
    WT.settings.GetClientPos(,, &clientW, &clientH)
    WinGetPos(&x, &y, &currentWidth, &currentHeight, target)
    width := currentWidth + SettingsScale(528 - clientW)
    height := currentHeight + SettingsScale(WTSettingsLayout.pageHeights[WT.tabs.Value] - clientH)
    if GetWorkArea(hwnd, &left, &top, &right, &bottom) {
        ; 只缺高度时给垂直滚动条留宽，避免无谓增加横向滚动。
        if height > bottom - top
            width += DllCall("GetSystemMetrics", "Int", 2)
        if width > right - left
            height += DllCall("GetSystemMetrics", "Int", 3)
        fittedWidth := Min(width, right - left), fittedHeight := Min(height, bottom - top)
        fittedX := Min(Max(x, left), right - fittedWidth), fittedY := Min(Max(y, top), bottom - fittedHeight)
        if fittedX != x || fittedY != y || fittedWidth != currentWidth || fittedHeight != currentHeight
            WinMove(fittedX, fittedY, fittedWidth, fittedHeight, target)
    }
    LayoutSettingsViewport()
}

LayoutSettingsViewport() {
    global WT
    hwnd := WT.settings.Hwnd, page := WT.tabs.Value
    height := WTSettingsLayout.pageHeights[page]
    WT.settings.GetClientPos(,, &w, &h)
    if w < 528 || h < height {
        ; 一根滚动条可能使另一方向的空间也不足。
        Loop 2 {
            DllCall("ShowScrollBar", "Ptr", hwnd, "Int", 0, "Int", w < 528)
            DllCall("ShowScrollBar", "Ptr", hwnd, "Int", 1, "Int", h < height)
            WT.settings.GetClientPos(,, &w, &h)
        }
        items := []
        for ctrl in WT.pageControls[page] {
            footer := page = 1 && (ctrl = WT.restoreSelectedButton || ctrl = WT.restoreAllButton || ctrl = WT.summary)
            items.Push(ViewportItem(ctrl, footer))
        }
        for ctrl in [WT.closeButton, WT.keyStatus, WT.configButtons*]
            items.Push(ViewportItem(ctrl, true))
        items.Push(ViewportItem(WT.tabs, false))
        WT.viewport := {items: items, x: 0, y: 0, maxX: Max(0,528-w), maxY: Max(0,height-h),
            h: h, page: page, focus: 0}
        for axis, size in [528, height] {
            visible := axis = 1 ? w : h
            if visible >= size
                continue
            info := Buffer(28, 0)
            NumPut("UInt", 28, "UInt", 7, "Int", 0, "Int", size-1, "UInt", visible, info)
            DllCall("SetScrollInfo", "Ptr", hwnd, "Int", axis-1, "Ptr", info, "Int", true)
        }
        MoveSettingsViewport(0, 0)
    }
    SizeSettingsFrame(Max(1, Min(height,h) - WTSettingsLayout.frameBottomMargin - WTSettingsLayout.frameTop))
}

ViewportItem(ctrl, footer) {
    ctrl.GetPos(&x, &y, &w, &h)
    return {ctrl: ctrl, x: x, y: y, w: w, h: h, footer: footer}
}

ResetSettingsViewport() {
    global WT
    if !HasProp(WT, "viewport") || !WT.viewport
        return
    for item in WT.viewport.items {
        item.ctrl.Move(item.x, item.y)
        DllCall("SetWindowRgn", "Ptr", item.ctrl.Hwnd, "Ptr", 0, "Int", false)
    }
    WT.viewport := 0
    DllCall("ShowScrollBar", "Ptr", WT.settings.Hwnd, "Int", 3, "Int", false)
}

MoveSettingsViewport(x, y) {
    global WT
    v := WT.viewport
    v.x := Min(v.maxX, Max(0,x)), v.y := Min(v.maxY, Max(0,y))
    top := WTSettingsLayout.frameTop, bottom := SettingsFooterTop(v.page) - v.maxY
    for item in v.items {
        cy := item.y - (item.footer ? v.maxY : item.ctrl = WT.tabs ? 0 : v.y)
        item.ctrl.Move(item.x - v.x, cy)
        if item.footer || item.ctrl = WT.tabs
            continue
        ; 区域交给系统持有，避免滚动的内容盖住标签与固定页脚。
        start := Max(0,top-cy), end := Max(start,Min(item.h,bottom-cy))
        region := DllCall("CreateRectRgn", "Int", 0, "Int", SettingsScale(start),
            "Int", SettingsScale(item.w), "Int", SettingsScale(end), "Ptr")
        if !DllCall("SetWindowRgn", "Ptr", item.ctrl.Hwnd, "Ptr", region, "Int", true)
            DllCall("DeleteObject", "Ptr", region)
    }
    for axis, pos in [v.x,v.y]
        DllCall("SetScrollPos", "Ptr", WT.settings.Hwnd, "Int", axis-1, "Int", pos, "Int", true)
}

SettingsScroll(wp, lp, msg, hwnd) {
    global WT
    if lp || !HasProp(WT, "viewport") || !WT.viewport || hwnd != WT.settings.Hwnd
        return
    v := WT.viewport, horizontal := msg = 0x114
    pos := horizontal ? v.x : v.y, limit := horizontal ? v.maxX : v.maxY
    step := horizontal ? 100 : Max(23,v.h-90)
    switch wp & 0xFFFF {
        case 0: pos -= 23
        case 1: pos += 23
        case 2: pos -= step
        case 3: pos += step
        case 4,5: pos := wp >> 16
        case 6: pos := 0
        case 7: pos := limit
        default: return
    }
    MoveSettingsViewport(horizontal ? pos : v.x, horizontal ? v.y : pos)
    return 0
}

SettingsWheel(wp, lp, msg, hwnd) {
    global WT
    if !HasProp(WT, "viewport") || !WT.viewport || !WT.viewport.maxY || hwnd != WT.settings.Hwnd
        return
    v := WT.viewport
    MoveSettingsViewport(v.x, v.y + ((wp >> 16) & 0x8000 ? 46 : -46))
    return 0
}

RevealSettingsFocus() {
    global WT
    if !HasProp(WT, "viewport") || !WT.viewport
        return
    v := WT.viewport, focus := DllCall("GetFocus", "Ptr")
    if focus = v.focus
        return
    v.focus := focus
    for item in v.items {
        if item.ctrl.Hwnd != focus
            continue
        x := Min(item.x, Max(v.x,item.x + item.w - (528-v.maxX)))
        y := item.footer || item.ctrl = WT.tabs ? v.y
            : Min(item.y-WTSettingsLayout.frameTop, Max(v.y,item.y+item.h-SettingsFooterTop(v.page)+v.maxY))
        MoveSettingsViewport(x,y)
        break
    }
}

UpdateSettingsFooter() {
    global WT
    if WT.statusPage
        WT.pageMessages[WT.statusPage] := WT.keyStatus.Text = "有未应用的修改" ? "" : WT.keyStatus.Text
    WT.statusPage := WT.tabs.Value
    config := WT.tabs.Value = 2 || WT.tabs.Value = 3
    message := WT.pageMessages.Get(WT.statusPage, "")
    WT.keyStatus.Text := message != "" ? message : WT.statusPage = 4 ? "诊断操作立即生效，不修改尚未应用的设置。"
        : config && HasUnsavedSettings() ? "有未应用的修改" : ""
    HideInactiveSettingsPages()
    for button in WT.configButtons
        button.Visible := config
    WT.keyStatus.Visible := config || WT.tabs.Value = 4
    WT.resetButton.Enabled := config
    WT.closeButton.Visible := !config
    PositionSettingsFooter(WT.tabs.Value, config)
    WT.okButton.Opt(config ? "+Default" : "-Default")
    WT.closeButton.Opt(config ? "-Default" : "+Default")
    ToolTip()
    UpdateSettingsHover(0)
    SetTimer(SettingsHint, 60)
    if WT.tabs.Value = 1
        RefreshManager()
}

SettingsFrameBottom(page) => WTSettingsLayout.pageHeights[page] - WTSettingsLayout.frameBottomMargin

SettingsFooterTop(page) => SettingsFrameBottom(page) - WTSettingsLayout.footerButtonHeight - 2 * WTSettingsLayout.footerPadding

PositionSettingsFooter(page, config) {
    global WT
    y := SettingsFooterTop(page) + WTSettingsLayout.footerPadding
    height := WTSettingsLayout.footerButtonHeight
    if config {
        WT.keyStatus.Move(132, y, 148, height)
        for index, x in [18, 294, 369, 444]
            WT.configButtons[index].Move(x, y, index = 1 ? 102 : 66, height)
    } else {
        WT.keyStatus.Move(20, y, 407, height)
        WT.closeButton.Move(442, y, page = 1 ? 69 : 68, height)
        if page = 1
            for control in [WT.restoreSelectedButton, WT.restoreAllButton, WT.summary]
                control.Move(, y, , height)
    }
}

SettingsTabChanged(*) {
    global WT
    ResetSettingsViewport()
    CancelRecording()
    UpdateSettingsFooter()
    if WT.tabs.Value = 4
        RefreshDiagnostics()
    ShowSettingsLayout(false)
}

RefreshKeyStates() {
    global WT
    if !WT.settings
        return
    hotkeyPage := WT.tabs.Value = 3
    WT.configButtons[4].Enabled := HasUnsavedSettings()
    xboxConflict := false
    for i, c in WT.controls {
        desired := c.enabled.Value ? c.key : ""
        saved := WT.configuredKeys.Length >= i ? WT.configuredKeys[i] : ""
        recording := WT.recorder && WT.recorder.control = c
        state := recording ? "录制中" : c.enabled.Value && c.key = "" ? "待录制"
            : desired != saved ? (desired = "" ? "待停用" : saved = "" ? "待启用" : "待修改")
            : WT.keyErrors.Has(i) ? "冲突（已保留）" : WT.keys.Length >= i && WT.keys[i] != "" ? "运行中" : "未启用"
        label := recording ? "录制中… 点击取消" : c.key = "" ? "未设置" : KeyLabel(c.key)
        if c.display.Text != label
            c.display.Text := label
        if c.state.Text != state {
            c.state.Text := state
            InvalidateSettingsControl(c.display.Hwnd)
            InvalidateSettingsControl(c.state.Hwnd)
        }
        isWinF11 := false
        if hotkeyPage && desired != "" {
            ; 比较组合签名，也识别旧配置中使用 vk7A 的同一键位。
            try isWinF11 := ParseKey(desired).signature = "8:122"
        }
        xboxConflict := xboxConflict || isWinF11
        occupied := isWinF11 && state = "冲突（已保留）" && InStr(WT.keyErrors[i], "Windows 错误 1409")
        c.help.Visible := !!occupied
        c.state.Visible := hotkeyPage && !occupied
    }
    WT.winF11Option.Visible := hotkeyPage
    WT.xboxSettings.Visible := xboxConflict
}

ShowXboxShortcutHelp(*) {
    global WT
    CancelRecording()
    answer := MsgBox(
        "Win+F11 可能被 Xbox 模式或其他程序占用。若设备启用了 Xbox 模式，可在 Windows 设置 → 游戏 → Xbox 模式关闭该功能。"
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
        !!WT.winF11Option.Value) {
        RefreshKeyStates()
        return false
    }
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
        || (WT.startupEnable.Enabled && HasProp(WT, "startupBaseline") && WT.startupEnable.Value != WT.startupBaseline)
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

ShowDiagnosticView(*) {
    global WT
    overview := WT.diagnosticTabs.Value = 1
    for , control in WT.diagnosticOverview
        control.Visible := overview
    WT.diagnostics.Visible := !overview
    InvalidateSettingsControl(WT.diagnosticTabs.Hwnd)
}

LocateShortcutConflict(*) {
    global WT
    for index in WT.keyErrors {
        OpenSettings(2)
        WT.controls[index].display.Focus()
        break
    }
}

RefreshDiagnosticsPage(*) {
    global WT
    RefreshStartup()
    RefreshDiagnostics()
    WT.keyStatus.Text := "已刷新运行状态。"
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
    if WT.tabs.Value != 4
        return
    conflicts := WT.keyErrors.Count
    firstKey := ""
    for index in WT.keyErrors {
        if index <= WT.configuredKeys.Length
            firstKey := StrReplace(KeyLabel(WT.configuredKeys[index]), " + ", "+")
        break
    }
    tray := TrayExists()
    WT.locateConflict.Enabled := conflicts > 0
    labels := [A_IsAdmin ? "管理员" : "普通用户",
        conflicts ? conflicts " 项不可用" (firstKey != "" ? " · " firstKey : "")
            : WT.bindings.Count ? WT.bindings.Count " 项已生效" : "未启用",
        tray ? "可用" : "未检测到", WT.startupStatus.Text,
        WT.recoveryBlocked ? "恢复记录异常，已禁止继续收起"
            : WT.windows.Count " 个已收起，" WT.pendingRestore.Count " 个正在恢复"]
    shades := [WTColors.ink, conflicts ? WTColors.conflict : WTColors.ink,
        tray ? WTColors.ink : WTColors.warning, WT.startupWarning ? WTColors.warning : WTColors.ink,
        WT.recoveryBlocked ? WTColors.conflict : WTColors.ink]
    for index, control in WT.diagnosticValues {
        control.Text := labels[index]
        SetSettingsTextColor(control, shades[index])
    }
}

RepairTrayFromSettings(*) {
    global WT
    StartTrayRecovery()
    RefreshDiagnostics()
    WT.keyStatus.Text := TrayExists() ? "托盘图标已存在。Windows 可能将其放在折叠区。" : "托盘尚未恢复，正在重试。"
}

OpenLocalFile(path) {
    if !FileExist(path) {
        MsgBox("文件尚未生成或不存在：`n" path, "WindowTool")
        return
    }
    Run('notepad.exe "' path '"')
}
