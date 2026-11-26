; SPDX-License-Identifier: GPL-2.0-or-later
; Copyright (C) 2026 JimmeYoumu
; 原生控件处理输入和焦点，浅色样式集中绘制。
global WTColors := {panel: 0xF0F0F0, tab: 0xE5E5E5, frame: 0xB6B6B6, border: 0xC8C8C8,
    line: 0xD0D0D0, keyLine: 0xC9C9C9, groupBorder: 0xBEBEBE, ink: 0x222222, muted: 0x555555, white: 0xFFFFFF, header: 0xECECEC,
    accent: 0x0067C0, recording: 0xEAF3FB, hover: 0xF7F7F7, hoverBorder: 0x929292,
    idleKey: 0xE8E8E8, idleKeyHover: 0xF2F2F2,
    ok: 0x23824D, warning: 0x815100, conflict: 0x9B2F35}

SettingsHighContrast() {
    high := Buffer(A_PtrSize = 8 ? 16 : 12, 0)
    NumPut("UInt", high.Size, high)
    return DllCall("SystemParametersInfoW", "UInt", 0x42, "UInt", high.Size, "Ptr", high, "UInt", 0)
        && (NumGet(high, 4, "UInt") & 1) != 0
}

SettingsScale(value) => Round(value * A_ScreenDPI / 96)
SettingsColor(rgb) => ((rgb & 255) << 16) | (rgb & 0xFF00) | ((rgb >> 16) & 255)
SettingsSurfaceColor() {
    global WT
    return WT.uiHighContrast ? SettingsColor(DllCall("GetSysColor", "Int", 15, "UInt")) : WTColors.panel
}

SettingsRect(left, top, right, bottom) {
    rect := Buffer(16)
    NumPut("Int", left, "Int", top, "Int", right, "Int", bottom, rect)
    return rect
}

SettingsBrush(rgb) {
    global WT
    if !WT.uiBrushes.Has(rgb)
        WT.uiBrushes[rgb] := DllCall("CreateSolidBrush", "UInt", SettingsColor(rgb), "Ptr")
    return WT.uiBrushes[rgb]
}

SettingsDrawText(dc, rect, value, color, font, center := false) {
    old := font ? DllCall("SelectObject", "Ptr", dc, "Ptr", font, "Ptr") : 0
    DllCall("SetBkMode", "Ptr", dc, "Int", 1)
    DllCall("SetTextColor", "Ptr", dc, "UInt", SettingsColor(color))
    DllCall("DrawTextW", "Ptr", dc, "Str", value, "Int", -1, "Ptr", rect, "UInt", 0x8824 | (center ? 1 : 0))
    if old
        DllCall("SelectObject", "Ptr", dc, "Ptr", old)
}

SettingsFont(hwnd) => DllCall("SendMessageW", "Ptr", hwnd, "UInt", 0x31, "Ptr", 0, "Ptr", 0, "Ptr")

SettingsTextWidth(dc, text, font) {
    size := Buffer(8, 0)
    old := font ? DllCall("SelectObject", "Ptr", dc, "Ptr", font, "Ptr") : 0
    DllCall("GetTextExtentPoint32W", "Ptr", dc, "Str", text, "Int", StrLen(text), "Ptr", size)
    if old
        DllCall("SelectObject", "Ptr", dc, "Ptr", old)
    return NumGet(size, "Int")
}

SizeSettingsFrame(height) {
    global WT
    tab := Buffer(16), pane := Buffer(16)
    DllCall("GetWindowRect", "Ptr", WT.tabs.Hwnd, "Ptr", tab)
    DllCall("GetWindowRect", "Ptr", WT.settingsPane.Hwnd, "Ptr", pane)
    ; 取两者实际位置，避免在分数 DPI 下分别换算高度产生重叠。
    sizes := [[WT.tabs.Hwnd, tab, NumGet(pane, 4, "Int") - NumGet(tab, 4, "Int")],
        [WT.settingsPane.Hwnd, pane, SettingsScale(height)]]
    for spec in sizes {
        rect := spec[2]
        top := NumGet(rect, 4, "Int"), bottom := NumGet(rect, 12, "Int")
        if bottom - top = spec[3]
            continue
        width := NumGet(rect, 8, "Int") - NumGet(rect, "Int")
        ; NOMOVE | NOZORDER | NOREDRAW | NOACTIVATE | NOCOPYBITS
        DllCall("SetWindowPos", "Ptr", spec[1], "Ptr", 0, "Int", 0, "Int", 0,
            "Int", width, "Int", spec[3], "UInt", 0x11E)
    }
}

SettingsFill(dc, left, top, right, bottom, color) {
    if right > left && bottom > top
        DllCall("FillRect", "Ptr", dc, "Ptr", SettingsRect(left, top, right, bottom),
            "Ptr", SettingsBrush(color))
}

SelectedSettingsTabRect(hwnd, item) {
    selected := DllCall("SendMessageW", "Ptr", hwnd, "UInt", 0x130B, "Ptr", 0, "Ptr", 0, "Ptr")
    return selected >= 0 && DllCall("SendMessageW", "Ptr", hwnd, "UInt", 0x130A, "Ptr", selected, "Ptr", item, "Ptr")
}

InitSettingsAppearance(tabs, pane) {
    global WT
    WT.uiHighContrast := SettingsHighContrast()
    WT.uiBrushes := Map()
    WT.uiCallback := CallbackCreate(SettingsPaint, , 6)
    SubclassSettingsControl(tabs, 1)
    SubclassSettingsControl(pane, 3)
    SetSettingsTabPadding(tabs.Hwnd)
    WT.uiTabLabels := ["窗口", "常规", "快捷键", "状态与诊断", "关于"]
    OnMessage(0x0015, SettingsSystemColorsChanged)
    OnMessage(0x031A, SettingsSystemColorsChanged)
}

SetSettingsTabPadding(hwnd) {
    ; 公共控件用当前字体测量文字。保留原生标签矩形作为绘制和命中测试的依据。
    SendMessage(0x132B, 0, SettingsScale(12) | (SettingsScale(4) << 16), hwnd)
    SendMessage(0x1331, 0, 0, hwnd)
}

AddSettingsGroup(gui, options, title) {
    SubclassSettingsControl(gui.AddGroupBox(options " +0x04000000", title), 8)
}

SubclassSettingsControl(control, kind, index := 0) {
    global WT
    DllCall("comctl32\SetWindowSubclass", "Ptr", control.Hwnd, "Ptr", WT.uiCallback, "UPtr", kind, "UPtr", index)
}

InvalidateSettingsControl(hwnd) => DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", 0)

SettingsSystemColorsChanged(*) {
    ; 在系统通知返回后应用配色，避免在原生控件绘制中切换画刷。
    SetTimer(RefreshSettingsContrast, -1)
}

RefreshSettingsContrast() {
    global WT
    if !IsSet(WT) || !WT.settings || !WT.list
        return
    high := SettingsHighContrast()
    WT.uiHighContrast := high
    WT.settings.BackColor := Format("{:06X}", SettingsSurfaceColor())
    RefreshManagerColors()
    UpdateStartupStatusColor()
    RefreshDiagnosticColors()
    if WT.tabs.Value = 4
        RefreshDiagnostics()
    DllCall("RedrawWindow", "Ptr", WT.settings.Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x85)
}

UpdateStartupStatusColor() {
    global WT
    SetSettingsTextColor(WT.startupStatus, WT.startupWarning ? WTColors.warning : WTColors.ink)
    SetSettingsTextColor(WT.startupNote, WTColors.muted)
}

SetSettingsTextColor(control, color) {
    global WT
    control.SetFont(WT.uiHighContrast ? "cDefault" : "c" Format("{:06X}", color))
}

RefreshDiagnosticColors() {
    global WT
    WT.diagnostics.Opt(WT.uiHighContrast ? "-Background" : "Background" Format("{:06X}", WTColors.white))
    SetSettingsTextColor(WT.diagnostics, WTColors.ink)
}

InitManagerAppearance() {
    global WT
    WT.listHeader := SendMessage(0x101F, 0, 0, WT.list.Hwnd)
    WT.listHeaderFont := DllCall("CreateFontW", "Int", -SettingsScale(12), "Int", 0, "Int", 0, "Int", 0, "Int", 600,
        "UInt", 0, "UInt", 0, "UInt", 0, "UInt", 1, "UInt", 0, "UInt", 0, "UInt", 5, "UInt", 0,
        "Str", "Microsoft YaHei UI", "Ptr")
    DllCall("comctl32\SetWindowSubclass", "Ptr", WT.listHeader, "Ptr", WT.uiCallback, "UPtr", 2, "UPtr", 0)
    RefreshManagerColors()
}

RefreshManagerColors() {
    global WT
    WT.list.Opt(WT.uiHighContrast ? "-Background" : "Background" Format("{:06X}", WTColors.white))
    bg := WT.uiHighContrast ? DllCall("GetSysColor", "Int", 5, "UInt") : SettingsColor(WTColors.white)
    fg := WT.uiHighContrast ? DllCall("GetSysColor", "Int", 8, "UInt") : SettingsColor(WTColors.ink)
    for spec in [[0x1001, bg], [0x1024, fg], [0x1026, bg]]
        SendMessage(spec[1], 0, spec[2], WT.list.Hwnd)
    WT.managerEmptyTitle.Opt(WT.uiHighContrast ? "-Background" : "BackgroundFFFFFF")
    WT.managerEmptyDetail.Opt(WT.uiHighContrast ? "-Background" : "BackgroundFFFFFF")
    WT.managerEmptyDetail.SetFont(WT.uiHighContrast ? "cDefault" : "c555555")
}

SettingsPaint(hwnd, msg, wp, lp, kind, ref) {
    global WT
    ; 进程销毁顶层窗口时，AHK 可能已经释放脚本全局变量。
    if !IsSet(WT) || !IsSet(WTColors)
        return DllCall("comctl32\DefSubclassProc", "Ptr", hwnd, "UInt", msg, "Ptr", wp, "Ptr", lp, "Ptr")
    if kind = 3 && msg = 0x84
        return -1
    if (kind = 3 || kind = 6 || !WT.uiHighContrast) && msg = 0xF {
        context := Buffer(72, 0)
        dc := DllCall("BeginPaint", "Ptr", hwnd, "Ptr", context, "Ptr")
        try {
            if kind = 1
                PaintSettingsTabs(hwnd, dc, WT.uiTabLabels)
            else if kind = 2
                PaintManagerHeader(hwnd, dc)
            else if kind = 3
                PaintSettingsPane(hwnd, dc)
            else if kind = 4
                PaintKeyField(WT.controls[ref], dc)
            else if kind = 5
                PaintKeyState(WT.controls[ref], dc)
            else if kind = 7
                PaintSettingsTabs(hwnd, dc, ["概况", "详细信息"], true)
            else if kind = 8
                PaintSettingsGroup(hwnd, dc)
            else if kind = 6
                PaintKeyHeading(hwnd, dc)
        }
        finally DllCall("EndPaint", "Ptr", hwnd, "Ptr", context)
        return 0
    }
    result := DllCall("comctl32\DefSubclassProc", "Ptr", hwnd, "UInt", msg, "Ptr", wp, "Ptr", lp, "Ptr")
    if (kind = 1 || kind = 4 || kind = 7) && (msg = 7 || msg = 8)
        InvalidateSettingsControl(hwnd)
    return result
}

PaintKeyHeading(hwnd, dc) {
    global WT
    rect := Buffer(16)
    DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rect)
    title := ControlGetText(hwnd), font := SettingsFont(hwnd)
    y := NumGet(rect, 12, "Int") // 2
    ink := WT.uiHighContrast ? SettingsColor(DllCall("GetSysColor", "Int", 18, "UInt")) : WTColors.ink
    DllCall("FillRect", "Ptr", dc, "Ptr", rect, "Ptr", SettingsBrush(SettingsSurfaceColor()))
    SettingsDrawText(dc, rect, title, ink, font)
    SettingsFill(dc, SettingsTextWidth(dc, title, font) + SettingsScale(6), y, NumGet(rect, 8, "Int"), y + 1,
        WT.uiHighContrast ? ink : WTColors.keyLine)
}

PaintSettingsGroup(hwnd, dc) {
    rect := Buffer(16)
    DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rect)
    width := NumGet(rect, 8, "Int"), bottom := NumGet(rect, 12, "Int")
    title := ControlGetText(hwnd), font := SettingsFont(hwnd)
    titleX := SettingsScale(6), gap := SettingsScale(3), ruleY := SettingsScale(8)
    titleEnd := titleX + SettingsTextWidth(dc, title, font)
    color := WTColors.groupBorder
    SettingsFill(dc, 0, ruleY, titleX - gap, ruleY + 1, color)
    SettingsFill(dc, titleEnd + gap, ruleY, width, ruleY + 1, color)
    SettingsFill(dc, 0, ruleY, 1, bottom, color)
    SettingsFill(dc, width - 1, ruleY, width, bottom, color)
    SettingsFill(dc, 1, bottom - 1, width - 1, bottom, color)
    SettingsDrawText(dc, SettingsRect(titleX, 0, width - gap, SettingsScale(16)), title, WTColors.ink, font)
}

PaintKeyField(c, dc) {
    global WT
    hwnd := c.display.Hwnd
    rect := Buffer(16)
    DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rect)
    recording := c.state.Text = "录制中"
    focused := DllCall("GetFocus", "Ptr") = hwnd
    hovered := WT.hoverControl = hwnd
    fill := recording ? WTColors.recording : c.enabled.Value ? (hovered ? WTColors.hover : WTColors.white)
        : (hovered ? WTColors.idleKeyHover : WTColors.idleKey)
    edge := recording || focused ? WTColors.accent : hovered ? WTColors.hoverBorder : WTColors.border
    ink := recording ? WTColors.accent : c.enabled.Value && c.key != "" ? WTColors.ink : WTColors.muted
    DllCall("FillRect", "Ptr", dc, "Ptr", rect, "Ptr", SettingsBrush(fill))
    DllCall("FrameRect", "Ptr", dc, "Ptr", rect, "Ptr", SettingsBrush(edge))
    w := NumGet(rect, 8, "Int"), h := NumGet(rect, 12, "Int")
    SettingsDrawText(dc, SettingsRect(4, 0, w - 4, h), c.display.Text, ink, SettingsFont(hwnd), true)
    if focused
        DllCall("DrawFocusRect", "Ptr", dc, "Ptr", SettingsRect(3, 3, w - 3, h - 3))
}

PaintKeyState(c, dc) {
    hwnd := c.state.Hwnd, rect := Buffer(16)
    DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rect)
    DllCall("FillRect", "Ptr", dc, "Ptr", rect, "Ptr", SettingsBrush(WTColors.panel))
    state := c.state.Text
    if state = "运行中" {
        d := SettingsScale(15), y := (NumGet(rect, 12, "Int") - d) // 2
        oldBrush := DllCall("SelectObject", "Ptr", dc, "Ptr", SettingsBrush(WTColors.ok), "Ptr")
        oldPen := DllCall("SelectObject", "Ptr", dc, "Ptr", DllCall("GetStockObject", "Int", 8, "Ptr"), "Ptr")
        DllCall("Ellipse", "Ptr", dc, "Int", 0, "Int", y, "Int", d, "Int", y + d)
        pen := DllCall("CreatePen", "Int", 0, "Int", Max(1, SettingsScale(2)), "UInt", 0xFFFFFF, "Ptr")
        if pen {
            DllCall("SelectObject", "Ptr", dc, "Ptr", pen)
            DllCall("MoveToEx", "Ptr", dc, "Int", SettingsScale(4), "Int", y + SettingsScale(8), "Ptr", 0)
            DllCall("LineTo", "Ptr", dc, "Int", SettingsScale(6), "Int", y + SettingsScale(10))
            DllCall("LineTo", "Ptr", dc, "Int", SettingsScale(11), "Int", y + SettingsScale(5))
        }
        DllCall("SelectObject", "Ptr", dc, "Ptr", oldPen)
        DllCall("SelectObject", "Ptr", dc, "Ptr", oldBrush)
        if pen
            DllCall("DeleteObject", "Ptr", pen)
    } else {
        ink := state = "录制中" ? WTColors.accent : InStr(state, "冲突") ? WTColors.conflict
            : SubStr(state, 1, 1) = "待" ? WTColors.warning : WTColors.muted
        SettingsDrawText(dc, rect, state, ink, SettingsFont(hwnd))
    }
}

PaintSettingsPane(hwnd, dc) {
    global WT
    rect := Buffer(16)
    DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rect)
    background := SettingsSurfaceColor()
    border := WT.uiHighContrast ? SettingsColor(DllCall("GetSysColor", "Int", 6, "UInt")) : WTColors.frame
    DllCall("FillRect", "Ptr", dc, "Ptr", rect, "Ptr", SettingsBrush(background))
    width := NumGet(rect, 8, "Int"), height := NumGet(rect, 12, "Int")
    SettingsFill(dc, 0, 0, 1, height, border)
    SettingsFill(dc, width - 1, 0, width, height, border)
    SettingsFill(dc, 1, height - 1, width - 1, height, border)
    ; 页框拥有整条内容区上沿。只在选中的平面标签内侧留一个开口。
    if !WT.uiHighContrast && WT.HasOwnProp("tabs")
        PaintSettingsTabDivider(dc, hwnd, WT.tabs.Hwnd, 1, 0, width - 1, border)
    else
        SettingsFill(dc, 1, 0, width - 1, 1, border)
    if WT.HasOwnProp("tabs") && (WT.tabs.Value = 2 || WT.tabs.Value = 3) {
        y := SettingsScale(SettingsFooterTop(WT.tabs.Value) - WTSettingsLayout.frameTop)
        SettingsFill(dc, SettingsScale(9), y, width - SettingsScale(9), y + 1,
            WT.uiHighContrast ? border : WTColors.line)
    }
}

PaintSettingsTabDivider(dc, surface, tabs, left, y, right, color) {
    item := Buffer(16)
    if !SelectedSettingsTabRect(tabs, item) {
        SettingsFill(dc, left, y, right, y + 1, color)
        return
    }
    if surface != tabs
        DllCall("MapWindowPoints", "Ptr", tabs, "Ptr", surface, "Ptr", item, "UInt", 2)
    gapLeft := Max(left, Min(right, NumGet(item, "Int") + 1))
    gapRight := Max(gapLeft, Min(right, NumGet(item, 8, "Int") - SettingsScale(2) - 1))
    SettingsFill(dc, left, y, gapLeft, y + 1, color)
    SettingsFill(dc, gapRight, y, right, y + 1, color)
}

PaintSettingsTabs(hwnd, dc, labels, divider := false) {
    client := Buffer(16)
    DllCall("GetClientRect", "Ptr", hwnd, "Ptr", client)
    DllCall("FillRect", "Ptr", dc, "Ptr", client, "Ptr", SettingsBrush(WTColors.panel))
    item := Buffer(16)
    edge := NumGet(client, 12, "Int")
    textEdge := edge - (divider ? 1 : 0)
    selected := DllCall("SendMessageW", "Ptr", hwnd, "UInt", 0x130B, "Ptr", 0, "Ptr", 0, "Ptr") + 1
    focused := DllCall("GetFocus", "Ptr") = hwnd
    font := SettingsFont(hwnd)
    for index, label in labels {
        if !DllCall("SendMessageW", "Ptr", hwnd, "UInt", 0x130A, "Ptr", index - 1, "Ptr", item, "Ptr")
            continue
        active := index = selected
        x := NumGet(item, 0, "Int"), right := NumGet(item, 8, "Int") - SettingsScale(2)
        y := NumGet(item, 4, "Int") + (active ? 0 : SettingsScale(2))
        color := active ? WTColors.frame : WTColors.border
        SettingsFill(dc, x, y, right, edge, active ? WTColors.panel : WTColors.tab)
        SettingsFill(dc, x, y, right, y + 1, color)
        SettingsFill(dc, x, y + 1, x + 1, edge, color)
        SettingsFill(dc, right - 1, y + 1, right, edge, color)
        SettingsDrawText(dc, SettingsRect(x, y, right, textEdge), label, active ? WTColors.ink : WTColors.muted, font, true)
        if active && focused
            DllCall("DrawFocusRect", "Ptr", dc, "Ptr", SettingsRect(x + 3, y + 3, right - 3, textEdge - 2))
    }
    if divider
        PaintSettingsTabDivider(dc, hwnd, hwnd, 0, edge - 1, NumGet(client, 8, "Int"), WTColors.frame)
}

PaintManagerHeader(hwnd, dc) {
    global WT
    static labels := ["窗口标题", "窗口句柄", "所属程序", "收起时间"]
    rect := Buffer(16)
    DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rect)
    DllCall("FillRect", "Ptr", dc, "Ptr", rect, "Ptr", SettingsBrush(WTColors.white))
    for index, label in labels {
        if !DllCall("SendMessageW", "Ptr", hwnd, "UInt", 0x1207, "Ptr", index - 1, "Ptr", rect, "Ptr")
            continue
        x := NumGet(rect, "Int"), y := NumGet(rect, 4, "Int")
        right := NumGet(rect, 8, "Int"), bottom := NumGet(rect, 12, "Int")
        if right <= x
            continue
        DllCall("FillRect", "Ptr", dc, "Ptr", rect, "Ptr", SettingsBrush(WTColors.header))
        DllCall("FillRect", "Ptr", dc, "Ptr", SettingsRect(right - 1, y, right, bottom), "Ptr", SettingsBrush(WTColors.line))
        DllCall("FillRect", "Ptr", dc, "Ptr", SettingsRect(x, bottom - 1, right, bottom), "Ptr", SettingsBrush(WTColors.border))
        SettingsDrawText(dc, SettingsRect(x + SettingsScale(6), y, right - 2, bottom), label, WTColors.ink, WT.listHeaderFont)
    }
}
