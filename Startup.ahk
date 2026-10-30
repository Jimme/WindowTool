; SPDX-License-Identifier: GPL-2.0-or-later
; Copyright (C) 2026 JimmeYoumu
; 当前用户的交互式管理员登录任务，不保存密码。
StartupSID() {
    token := 0
    if !DllCall("Advapi32\OpenProcessToken", "Ptr", DllCall("GetCurrentProcess", "Ptr"),
        "UInt", 8, "Ptr*", &token)
        throw OSError()
    try {
        size := 0
        DllCall("Advapi32\GetTokenInformation", "Ptr", token, "Int", 1, "Ptr", 0, "UInt", 0, "UInt*", &size)
        data := Buffer(size)
        if !DllCall("Advapi32\GetTokenInformation", "Ptr", token, "Int", 1, "Ptr", data, "UInt", size, "UInt*", &size)
            throw OSError()
        text := 0
        if !DllCall("Advapi32\ConvertSidToStringSidW", "Ptr", NumGet(data, 0, "Ptr"), "Ptr*", &text)
            throw OSError()
        try return StrGet(text)
        finally DllCall("LocalFree", "Ptr", text)
    } finally DllCall("CloseHandle", "Ptr", token)
}

StartupFolder() {
    service := ComObject("Schedule.Service")
    service.Connect()
    return service.GetFolder("\")
}

StartupName(sid) => "WindowTool.AdminStartup." sid
StartupMarker() => "WindowTool interactive startup v1"

StartupTask(folder, name) {
    ; 枚举包含隐藏任务，避免把“尚未创建”和 COM 访问失败混为一谈。
    for task in folder.GetTasks(1) {
        if StrLower(task.Name) = StrLower(name)
            return task
    }
    return 0
}

StartupOwned(task) {
    if task.Definition.RegistrationInfo.Source != StartupMarker()
        throw Error("同名任务不属于 WindowTool，未作修改。")
}

StartupDefinition(service, sid, path) {
    task := service.NewTask(0)
    task.RegistrationInfo.Source := StartupMarker()
    task.RegistrationInfo.Description := "当前用户登录后延迟 10 秒，以管理员权限运行 WindowTool。"
    task.Principal.UserId := sid
    task.Principal.LogonType := 3 ; TASK_LOGON_INTERACTIVE_TOKEN
    task.Principal.RunLevel := 1 ; TASK_RUNLEVEL_HIGHEST
    trigger := task.Triggers.Create(9) ; TASK_TRIGGER_LOGON
    trigger.UserId := sid
    trigger.Delay := "PT10S"
    action := task.Actions.Create(0)
    action.Path := path
    SplitPath(path, , &directory)
    action.WorkingDirectory := directory
    task.Settings.DisallowStartIfOnBatteries := false
    task.Settings.StopIfGoingOnBatteries := false
    task.Settings.ExecutionTimeLimit := "PT0S"
    task.Settings.MultipleInstances := 2 ; IGNORE_NEW
    task.Settings.AllowDemandStart := true
    task.Settings.Enabled := true
    return task
}

; 只迁移当前用户启动目录中、无参数且指向当前 EXE 的快捷方式。
StartupLinks(path) {
    links := []
    Loop Files A_Startup "\*.lnk" {
        FileGetShortcut(A_LoopFileFullPath, &target, , &args)
        if StrLower(target) = StrLower(path) && args = ""
            links.Push(A_LoopFileFullPath)
    }
    return links
}

ConfigureStartup(enable, sid, testName := "") {
    if !A_IsAdmin || StartupSID() != sid
        throw Error("请使用当前用户的管理员权限设置，不能改用另一个账户授权。")
    if !A_IsCompiled
        throw Error("请从准备长期使用的 WindowTool.exe 设置自启动。")
    ; 独立集成测试仅可使用测试命名空间，正常入口不传此参数。
    if testName != "" && !RegExMatch(testName, "^WindowTool\.Test\.Startup\.\d+$")
        throw Error("无效的测试任务名称。")
    folder := StartupFolder(), name := testName != "" ? testName : StartupName(sid)
    old := StartupTask(folder, name)
    if old
        StartupOwned(old)
    if !enable {
        if old
            folder.DeleteTask(name, 0)
        return
    }
    service := ComObject("Schedule.Service")
    service.Connect()
    definition := StartupDefinition(service, sid, A_ScriptFullPath)
    oldXML := old ? old.Xml : ""
    moved := [], taskWritten := false
    try {
        folder.RegisterTaskDefinition(name, definition, 6, sid, , 3)
        taskWritten := true
        registered := folder.GetTask(name)
        if !registered.Enabled || registered.Definition.Actions.Item(1).Path != A_ScriptFullPath
            throw Error("任务注册后校验失败。")
        for link in StartupLinks(A_ScriptFullPath) {
            backup := link ".WindowTool-disabled"
            if FileExist(backup)
                throw Error("已有快捷方式备份，请先检查：" backup)
            FileMove(link, backup)
            moved.Push({original: link, backup: backup})
        }
    } catch Error as e {
        rollback := ""
        for item in moved {
            try FileMove(item.backup, item.original)
            catch Error as restoreError
                rollback .= "`n快捷方式恢复失败：" restoreError.Message
        }
        try {
            if taskWritten {
                if oldXML != ""
                    folder.RegisterTask(name, oldXML, 6, sid, , 3)
                else
                    folder.DeleteTask(name, 0)
            }
        } catch Error as restoreError
            rollback .= "`n任务回滚失败：" restoreError.Message
        throw Error(e.Message rollback)
    }
}

StartupHelper() {
    if A_Args.Length != 2
        ExitApp(2)
    try {
        ConfigureStartup(A_Args[1] = "--startup-enable", A_Args[2])
        ExitApp(0)
    } catch Error as e {
        MsgBox("自启动设置失败：`n" e.Message, "WindowTool", "Iconx")
        ExitApp(1)
    }
}

ShowStartup(*) {
    global WT
    if HasProp(WT, "startupGui") && WT.startupGui {
        WT.startupGui.Show()
        RefreshStartup()
        return
    }
    g := Gui(, "管理员自启动 — v" WT.version)
    g.SetFont("s10", "Microsoft YaHei UI")
    WT.startupStatus := g.AddText("w600 r5", "")
    g.AddText("w600 r3", "当前程序：" A_ScriptFullPath "`n请从长期安装目录启用；移动程序后需重新启用。")
    g.AddText("w600 r3", "登录后延迟 10 秒启动。启用需管理员授权，不保存密码。`n匹配的旧启动快捷方式会保留为 .WindowTool-disabled 备份；关闭此选项不会恢复旧自启。")
    WT.startupEnable := g.AddButton("w170", "启用 / 更新启动路径")
    WT.startupEnable.OnEvent("Click", (*) => ChangeStartup(true))
    WT.startupDisable := g.AddButton("x+10 w130", "关闭自启动")
    WT.startupDisable.OnEvent("Click", (*) => ChangeStartup(false))
    g.AddButton("x+10 w100", "刷新").OnEvent("Click", (*) => RefreshStartup())
    g.OnEvent("Close", (*) => g.Hide())
    g.OnEvent("Escape", (*) => g.Hide())
    WT.startupGui := g
    RefreshStartup()
    g.Show()
}

RefreshStartup() {
    global WT
    try {
        task := StartupTask(StartupFolder(), StartupName(StartupSID()))
        if task {
            StartupOwned(task)
            definition := task.Definition
            WT.startupStatus.Text := (task.Enabled ? "已启用" : "任务已停用")
                . "`n任务启动路径：" definition.Actions.Item(1).Path
                . "`n管理员权限：" (definition.Principal.RunLevel = 1 ? "是" : "否")
                . "；当前桌面会话：" (definition.Principal.LogonType = 3 ? "是" : "否")
        } else
            WT.startupStatus.Text := "未配置 WindowTool 管理员自启动任务。"
        WT.startupEnable.Enabled := A_IsCompiled
        WT.startupDisable.Enabled := A_IsCompiled && !!task
        if !A_IsCompiled
            WT.startupStatus.Text .= "`n源码运行模式仅查看；请从正式安装的 EXE 设置。"
    } catch Error as e {
        WT.startupStatus.Text := "无法读取自启动状态：" e.Message
        WT.startupEnable.Enabled := false
        WT.startupDisable.Enabled := false
    }
}

ChangeStartup(enable) {
    global WT
    WT.startupEnable.Enabled := false
    WT.startupDisable.Enabled := false
    try {
        sid := StartupSID()
        if A_IsAdmin
            ConfigureStartup(enable, sid)
        else {
            command := '*RunAs "' A_ScriptFullPath '" --startup-' (enable ? "enable" : "disable") ' "' sid '"'
            code := RunWait(command, A_ScriptDir)
            if code != 0
                throw Error("未能完成设置（退出码 " code "）。")
        }
    } catch Error as e
        MsgBox("自启动设置未完成：`n" e.Message, "WindowTool", "Icon!")
    RefreshStartup()
}
