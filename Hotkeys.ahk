; SPDX-License-Identifier: GPL-2.0-or-later
; Copyright (C) 2026 JimmeYoumu
; 所有用户操作共用一份定义，供配置、托盘和设置界面使用。
Actions() {
    return [
        {name: "Hide", label: "收起当前窗口", key: "^+CapsLock"},
        {name: "Restore", label: "恢复最近窗口", key: "^!CapsLock"},
        {name: "Manager", label: "打开管理界面", key: "#F9"},
        {name: "Center", label: "窗口居中", key: "#F12"},
        {name: "Vertical", label: "窗口上 / 中 / 下", key: "#F11"},
        {name: "Horizontal", label: "窗口左 / 中 / 右", key: "#F10"},
        {name: "RestoreAll", label: "恢复全部窗口", key: ""},
        {name: "Settings", label: "打开快捷键设置", key: ""},
        {name: "RepairTray", label: "修复托盘图标", key: ""},
        {name: "Exit", label: "退出并恢复窗口", key: ""}]
}

DefaultKeys() {
    keys := []
    for action in Actions()
        keys.Push(action.key)
    return keys
}

LoadKeys() {
    global WT
    keys := []
    for action in Actions()
        keys.Push(IniRead(WT.ini, "Hotkeys", action.name, action.key))
    return keys
}

ParseKey(key) {
    key := Trim(key)
    modifiers := 0
    while StrLen(key) && InStr("^!+#", SubStr(key, 1, 1)) {
        ch := SubStr(key, 1, 1)
        modifiers |= ch = "^" ? 2 : ch = "!" ? 1 : ch = "+" ? 4 : 8
        key := SubStr(key, 2)
    }
    vk := GetKeyVK(key)
    if !modifiers || !vk || InStr(key, " ") || IsModifier(vk)
        throw ValueError("请录制带 Ctrl / Alt / Shift / Win 的组合键。")
    canonical := KeyFromVK(modifiers, vk)
    return {modifiers: modifiers, vk: vk, key: canonical, signature: modifiers ":" vk}
}

IsModifier(vk) {
    return vk = 0x10 || vk = 0x11 || vk = 0x12 || vk = 0x5B || vk = 0x5C
        || (vk >= 0xA0 && vk <= 0xA5)
}

KeyFromVK(modifiers, vk) {
    return ((modifiers & 2) ? "^" : "") ((modifiers & 1) ? "!" : "")
        . ((modifiers & 4) ? "+" : "") ((modifiers & 8) ? "#" : "")
        . GetKeyName(Format("vk{:02X}", vk))
}

KeyLabel(key) {
    if key = ""
        return "未启用"
    try {
        p := ParseKey(key)
        return ((p.modifiers & 2) ? "Ctrl + " : "") ((p.modifiers & 1) ? "Alt + " : "")
            . ((p.modifiers & 4) ? "Shift + " : "") ((p.modifiers & 8) ? "Win + " : "")
            . GetKeyName(Format("vk{:02X}", p.vk))
    }
    return key
}

; 在原注册仍然生效时取得新注册。失败只释放新取得的组合，不动旧组合。
StageKeys(keys) {
    global WT
    if keys.Length != Actions().Length
        throw ValueError("快捷键配置项数量不正确。")
    staged := {bindings: Map(), actions: Map(), added: []}
    try {
        for index, key in keys {
            if key = ""
                continue
            p := ParseKey(key), signature := p.signature
            if staged.actions.Has(signature)
                throw ValueError(Actions()[index].label " 与其他功能使用了同一个快捷键。")
            staged.actions[signature] := index
            if WT.bindings.Has(signature) {
                staged.bindings[signature] := WT.bindings[signature]
                continue
            }
            binding := {id: ++WT.nextKeyId, hook: "", action: index}
            if binding.id > 0xBFFF
                throw Error("快捷键注册编号已用尽，请退出后重新启动。")
            ; F12 被 Windows 留给调试器；CapsLock 用钩子抑制大小写切换。
            ; 其余键用 RegisterHotKey 取得系统级冲突反馈。
            if p.vk = 0x7B || p.vk = 0x14 {
                binding.hook := "$" p.key
                Hotkey(binding.hook, HookPressed.Bind(signature, p.vk), "On T1")
                if WT.hooksPaused
                    Hotkey(binding.hook, "Off")
            } else if !DllCall("RegisterHotKey", "Ptr", A_ScriptHwnd, "Int", binding.id,
                "UInt", p.modifiers | 0x4000, "UInt", p.vk) {
                throw Error(Actions()[index].label "：" KeyLabel(key)
                    " 注册失败，可能已被占用（Windows 错误 " A_LastError "）。")
            }
            staged.added.Push(binding)
            staged.bindings[signature] := binding
        }
        return staged
    } catch Error as e {
        DiscardKeys(staged)
        throw e
    }
}

ReleaseBinding(binding) {
    if binding.hook != "" {
        try Hotkey(binding.hook, "Off")
    } else
        DllCall("UnregisterHotKey", "Ptr", A_ScriptHwnd, "Int", binding.id)
}

DiscardKeys(staged) {
    for binding in staged.added
        ReleaseBinding(binding)
}

CommitKeys(keys, staged) {
    global WT
    for signature, binding in WT.bindings {
        if !staged.bindings.Has(signature)
            ReleaseBinding(binding)
    }
    for signature, binding in staged.bindings
        binding.action := staged.actions[signature]
    WT.bindings := staged.bindings
    WT.keys := keys.Clone()
}

RegisterKeys(keys) {
    previousCritical := A_IsCritical
    Critical("On")
    try CommitKeys(keys, StageKeys(keys))
    finally Critical(previousCritical)
}

UnregisterKeys() {
    global WT
    for , binding in WT.bindings
        ReleaseBinding(binding)
    WT.bindings := Map()
    SetTimer(ResumeHooks, 0)
    WT.hooksPaused := false
}

StartKeys(requested := unset) {
    global WT
    if !IsSet(requested)
        requested := LoadKeys()
    WT.keys := []
    Loop Actions().Length
        WT.keys.Push("")
    ; 一项错误不应使其他所有快捷键失效，也不覆盖磁盘上的用户配置。
    for index, key in requested {
        candidate := WT.keys.Clone(), candidate[index] := key
        try RegisterKeys(candidate)
        catch Error as e {
            WT.warnings .= e.Message "`n"
            WTLog("快捷键停用: " e.Message)
        }
    }
}

HandleHotkey(id, *) {
    global WT
    if WT.recorder
        return
    for , binding in WT.bindings {
        if binding.hook = "" && binding.id = id {
            ExecuteAction(binding.action)
            return
        }
    }
}

HookPressed(signature, vk, *) {
    global WT
    if !WT.recorder && WT.bindings.Has(signature)
        ExecuteAction(WT.bindings[signature].action)
    KeyWait(Format("vk{:02X}", vk))
}

ExecuteAction(index) {
    switch index {
        case 1: HideWindow(WinExist("A"))
        case 2: RestoreLatest()
        case 3: ShowManager()
        case 4: PositionWindow(WinExist("A"), "center")
        case 5: PositionWindow(WinExist("A"), "vertical")
        case 6: PositionWindow(WinExist("A"), "horizontal")
        case 7: RestoreAll()
        case 8: ShowSettings()
        case 9: StartTrayRecovery()
        case 10: ExitApp()
    }
}

SaveSettings(controls, status) {
    global WT
    CancelRecording()
    keys := []
    for c in controls {
        if c.enabled.Value && c.key = "" {
            status.Text := "启用的功能需要先录制快捷键。"
            return false
        }
        keys.Push(c.enabled.Value ? c.key : "")
    }
    previousCritical := A_IsCritical
    Critical("On")
    staged := 0
    try {
        staged := StageKeys(keys)
        ; 保留其他 INI 段，只更新快捷键；写入失败时原注册、原配置均保留。
        temp := WT.ini ".tmp"
        if FileExist(WT.ini)
            FileCopy(WT.ini, temp, true)
        else if FileExist(temp)
            FileDelete(temp)
        for index, action in Actions()
            IniWrite(keys[index], temp, "Hotkeys", action.name)
        FileMove(temp, WT.ini, true)
        CommitKeys(keys, staged)
        WT.warnings := WT.recoveryBlocked ? "恢复记录读取失败，暂不允许收起新窗口；请保留原记录并检查日志。" : ""
        status.Text := "已保存并生效。"
        UpdateSummary()
        return true
    } catch Error as e {
        if IsObject(staged)
            DiscardKeys(staged)
        status.Text := e.Message
        return false
    } finally {
        Critical(previousCritical)
    }
}

ShowSettings(*) {
    global WT
    if !WT.gui
        ShowManager()
    if !WT.settings {
        g := Gui("+Owner" WT.gui.Hwnd, "快捷键设置 — v" WT.version)
        g.SetFont("s10", "Microsoft YaHei UI")
        g.AddText("w620", "点“录制”后按组合键，支持 Tab、CapsLock 和 Win。Esc 取消录制。")
        controls := []
        for index, action in Actions() {
            enabled := g.AddCheckbox("xm w180", action.label)
            display := g.AddEdit("x+8 w300 ReadOnly", "")
            button := g.AddButton("x+8 w110", "录制…")
            c := {enabled: enabled, display: display, button: button, key: ""}
            controls.Push(c)
            button.OnEvent("Click", StartRecording.Bind(c))
        }
        status := g.AddText("xm w620 r3", "")
        g.AddButton("xm w110 Default", "保存").OnEvent("Click", (*) => SaveSettings(controls, status))
        g.AddButton("x+10 w130", "恢复默认（未保存）").OnEvent("Click", (*) => FillSettings(DefaultKeys()))
        g.AddButton("x+10 w110", "取消录制").OnEvent("Click", (*) => CancelRecording())
        g.AddButton("x+10 w150", "管理员自启动…").OnEvent("Click", ShowStartup)
        g.OnEvent("Close", (*) => CloseSettings())
        g.OnEvent("Escape", (*) => CloseSettings())
        WT.settings := g, WT.controls := controls, WT.keyStatus := status
    }
    CancelRecording()
    FillSettings(WT.keys)
    WT.keyStatus.Text := "勾选启用，取消勾选则停用。修改后请保存。`n"
        . "CapsLock / F12 无法完整检测其他键盘钩子的冲突。"
    WT.settings.Show()
}

FillSettings(keys) {
    global WT
    CancelRecording()
    for index, c in WT.controls {
        c.key := keys[index]
        c.enabled.Value := c.key != ""
        c.display.Value := KeyLabel(c.key)
    }
}

CloseSettings() {
    global WT
    CancelRecording()
    WT.settings.Hide()
}

StartRecording(c, *) {
    global WT
    CancelRecording()
    for , binding in WT.bindings {
        if binding.hook != ""
            Hotkey(binding.hook, "Off")
    }
    WT.hooksPaused := true
    ih := InputHook("L0 T15")
    ih.KeyOpt("{All}", "NS")
    ; 新按下的修饰键也被抑制，避免录制 Win 组合时打开开始菜单。
    ih.OnKeyDown := RecordKey
    ih.OnKeyUp := RecordKeyUp
    ih.OnEnd := RecordingEnded
    down := Map()
    for name in ["LControl", "RControl", "LShift", "RShift", "LAlt", "RAlt", "LWin", "RWin"] {
        if GetKeyState(name, "P") {
            down[GetKeyVK(name)] := true
            ; 开始录制前已传给系统的键，必须允许其释放，避免粘住修饰键。
            ih.KeyOpt("{" name "}", "-S")
        }
    }
    WT.recorder := {hook: ih, control: c, down: down}
    WT.keyStatus.Text := "正在录制：请按组合键。Esc 取消，15 秒后自动取消。"
    ih.Start()
    SetTimer(WatchRecording, 100)
}

RecordKey(ih, vk, sc) {
    global WT
    if !WT.recorder || WT.recorder.hook != ih
        return
    if IsModifier(vk) {
        WT.recorder.down[vk] := true
        return
    }
    if vk = 0x1B {
        CancelRecording()
        return
    }
    modifiers := 0
    for modifierVK in WT.recorder.down
        modifiers |= (modifierVK = 0x11 || modifierVK = 0xA2 || modifierVK = 0xA3) ? 2
            : (modifierVK = 0x12 || modifierVK = 0xA4 || modifierVK = 0xA5) ? 1
            : (modifierVK = 0x10 || modifierVK = 0xA0 || modifierVK = 0xA1) ? 4 : 8
    if !modifiers {
        WT.keyStatus.Text := "需要带 Ctrl / Alt / Shift / Win，请继续录制。"
        return
    }
    c := WT.recorder.control
    c.key := KeyFromVK(modifiers, vk)
    c.enabled.Value := true
    c.display.Value := KeyLabel(c.key)
    CancelRecording()
    WT.keyStatus.Text := "已录入 " KeyLabel(c.key) "，点击保存后生效。"
}

RecordKeyUp(ih, vk, sc) {
    global WT
    if WT.recorder && WT.recorder.hook = ih && WT.recorder.down.Has(vk)
        WT.recorder.down.Delete(vk)
}

RecordingEnded(ih) {
    global WT
    if WT.recorder && WT.recorder.hook = ih {
        WT.recorder := 0
        SetTimer(WatchRecording, 0)
        SetTimer(ResumeHooks, 50)
        WT.keyStatus.Text := "录制已结束，未修改快捷键。"
    }
}

CancelRecording() {
    global WT
    if WT.recorder {
        ih := WT.recorder.hook
        WT.recorder := 0
        SetTimer(WatchRecording, 0)
        ih.Stop()
        SetTimer(ResumeHooks, 50)
    }
}

WatchRecording() {
    global WT
    if WT.recorder && (!WT.settings || !WinActive("ahk_id " WT.settings.Hwnd)) {
        CancelRecording()
        WT.keyStatus.Text := "已离开设置窗口，录制自动取消。"
    }
}

ResumeHooks() {
    global WT
    if WT.recorder
        return
    for name in ["Ctrl", "Shift", "Alt", "LWin", "RWin", "CapsLock", "F12"] {
        if GetKeyState(name, "P")
            return
    }
    for , binding in WT.bindings {
        if binding.hook != ""
            Hotkey(binding.hook, "On")
    }
    WT.hooksPaused := false
    SetTimer(ResumeHooks, 0)
}
