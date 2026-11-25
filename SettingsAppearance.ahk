; SPDX-License-Identifier: GPL-2.0-or-later
; Copyright (C) 2026 JimmeYoumu
; 用原生 Tab3 和 ListView 处理操作，仅绘制标签、表头及空状态。
global WTColors := {panel: 0xF0F0F0, tab: 0xE5E5E5, frame: 0xB6B6B6, border: 0xC8C8C8,
    line: 0xD0D0D0, ink: 0x222222, muted: 0x555555, white: 0xFFFFFF, header: 0xECECEC}

SettingsHighContrast() {
    high := Buffer(A_PtrSize = 8 ? 16 : 12, 0)
    NumPut("UInt", high.Size, high)
    return DllCall("SystemParametersInfoW", "UInt", 0x42, "UInt", high.Size, "Ptr", high, "UInt", 0)
        && (NumGet(high, 4, "UInt") & 1) != 0
}

SettingsScale(value) => Round(value * A_ScreenDPI / 96)
SettingsColor(rgb) => ((rgb & 255) << 16) | (rgb & 0xFF00) | ((rgb >> 16) & 255)
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
    DllCall("comctl32\SetWindowSubclass", "Ptr", tabs.Hwnd, "Ptr", WT.uiCallback, "UPtr", 1, "UPtr", 0)
    DllCall("comctl32\SetWindowSubclass", "Ptr", pane.Hwnd, "Ptr", WT.uiCallback, "UPtr", 3, "UPtr", 0)
    ; TCS_FIXEDWIDTH 和 TCM_SETITEMSIZE，保留 Tab3 的选择、键盘及无障碍接口。
    DllCall("SendMessageW", "Ptr", tabs.Hwnd, "UInt", 0x1329, "Ptr", 0,
        "Ptr", SettingsScale(76) | (SettingsScale(25) << 16), "Ptr")
    WT.uiTabLabels := ["窗口", "常规", "快捷键", "状态与诊断", "关于"]
    OnMessage(0x0015, SettingsSystemColorsChanged)
    OnMessage(0x031A, SettingsSystemColorsChanged)
}

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
    RefreshManagerColors()
    DllCall("RedrawWindow", "Ptr", WT.settings.Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x85)
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
    if (kind = 3 || !WT.uiHighContrast) && msg = 0xF {
        context := Buffer(72, 0)
        dc := DllCall("BeginPaint", "Ptr", hwnd, "Ptr", context, "Ptr")
        try {
            if kind = 1
                PaintSettingsTabs(hwnd, dc)
            else if kind = 2
                PaintManagerHeader(hwnd, dc)
            else
                PaintSettingsPane(hwnd, dc)
        }
        finally DllCall("EndPaint", "Ptr", hwnd, "Ptr", context)
        return 0
    }
    result := DllCall("comctl32\DefSubclassProc", "Ptr", hwnd, "UInt", msg, "Ptr", wp, "Ptr", lp, "Ptr")
    if kind = 1 && (msg = 7 || msg = 8)
        DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", 0)
    return result
}

PaintSettingsPane(hwnd, dc) {
    global WT
    rect := Buffer(16)
    DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rect)
    background := WT.uiHighContrast ? SettingsColor(DllCall("GetSysColor", "Int", 15, "UInt")) : WTColors.panel
    border := WT.uiHighContrast ? SettingsColor(DllCall("GetSysColor", "Int", 6, "UInt")) : WTColors.frame
    DllCall("FillRect", "Ptr", dc, "Ptr", rect, "Ptr", SettingsBrush(background))
    width := NumGet(rect, 8, "Int"), height := NumGet(rect, 12, "Int")
    SettingsFill(dc, 0, 0, 1, height, border)
    SettingsFill(dc, width - 1, 0, width, height, border)
    SettingsFill(dc, 1, height - 1, width - 1, height, border)
    ; 页框拥有整条内容区上沿。只在选中的平面标签内侧留一个开口。
    tabRect := Buffer(16)
    if !WT.uiHighContrast && WT.HasOwnProp("tabs") && SelectedSettingsTabRect(WT.tabs.Hwnd, tabRect) {
        DllCall("MapWindowPoints", "Ptr", WT.tabs.Hwnd, "Ptr", hwnd, "Ptr", tabRect, "UInt", 2)
        gapLeft := Max(1, Min(width - 1, NumGet(tabRect, "Int") + 1))
        gapRight := Max(gapLeft, Min(width - 1, NumGet(tabRect, 8, "Int") - SettingsScale(2) - 1))
        SettingsFill(dc, 1, 0, gapLeft, 1, border)
        SettingsFill(dc, gapRight, 0, width - 1, 1, border)
    } else {
        SettingsFill(dc, 1, 0, width - 1, 1, border)
    }
}

PaintSettingsTabs(hwnd, dc) {
    global WT
    client := Buffer(16)
    DllCall("GetClientRect", "Ptr", hwnd, "Ptr", client)
    DllCall("FillRect", "Ptr", dc, "Ptr", client, "Ptr", SettingsBrush(WTColors.panel))
    item := Buffer(16)
    edge := NumGet(client, 12, "Int")
    selected := DllCall("SendMessageW", "Ptr", hwnd, "UInt", 0x130B, "Ptr", 0, "Ptr", 0, "Ptr") + 1
    focused := DllCall("GetFocus", "Ptr") = hwnd
    font := SettingsFont(hwnd)
    for index, label in WT.uiTabLabels {
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
        SettingsDrawText(dc, SettingsRect(x, y, right, edge), label, active ? WTColors.ink : WTColors.muted, font, true)
        if active && focused
            DllCall("DrawFocusRect", "Ptr", dc, "Ptr", SettingsRect(x + 3, y + 3, right - 3, edge - 2))
    }
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
