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
        MsgBox(StartupErrorText(e), "WindowTool", "Iconx")
        ExitApp(1)
    }
}

RefreshStartup() {
    global WT
    try {
        task := StartupTask(StartupFolder(), StartupName(StartupSID()))
        if task {
            StartupOwned(task)
            definition := task.Definition
            issues := StartupIssues(definition, A_ScriptFullPath)
            WT.startupStatus.Value := (!task.Enabled ? "任务已停用" : issues != "" ? "已配置，但需要处理：" : "已启用，配置检查正常")
                . "`r`n" issues "`r`n上次运行结果：" StartupResult(task.LastTaskResult)
                . "`r`n任务路径：" (definition.Actions.Count ? definition.Actions.Item(1).Path : "无执行程序")
        } else
            WT.startupStatus.Value := "未配置 WindowTool 管理员自启动任务。"
        WT.startupBaseline := !!task && task.Enabled
        WT.startupEnable.Value := WT.startupBaseline
        WT.startupEnable.Enabled := A_IsCompiled
        WT.startupRepair.Enabled := A_IsCompiled
        if !A_IsCompiled
            WT.startupStatus.Value .= "`r`n源码运行模式仅查看；请从正式安装的 EXE 设置。"
    } catch Error as e {
        WT.startupStatus.Text := "无法读取自启动状态：" e.Message
        WT.startupEnable.Enabled := false
        WT.startupRepair.Enabled := false
    }
}

ChangeStartup(enable) {
    global WT
    WT.startupEnable.Enabled := false
    WT.startupRepair.Enabled := false
    ok := false
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
        ok := true
    } catch Error as e {
        WT.lastError := StartupErrorText(e)
        MsgBox(WT.lastError, "WindowTool", "Icon!")
    }
    RefreshStartup()
    return ok
}

StartupIssues(definition, currentPath) {
    issues := ""
    if definition.Actions.Count != 1 || definition.Actions.Item(1).Type != 0
        issues .= "执行动作异常。`r`n"
    else {
        action := definition.Actions.Item(1)
        if !FileExist(action.Path)
            issues .= "启动程序不存在。`r`n"
        if StrLower(action.Path) != StrLower(currentPath)
            issues .= "任务指向其他安装路径，可更新为当前路径。`r`n"
        if action.Arguments != ""
            issues .= "启动参数与默认配置不同。`r`n"
        if !DirExist(action.WorkingDirectory)
            issues .= "工作目录不存在。`r`n"
    }
    if definition.Principal.RunLevel != 1 || definition.Principal.LogonType != 3
        issues .= "未使用交互会话的最高权限。`r`n"
    validLogon := false
    expectedSid := StartupSID()
    if AccountSID(definition.Principal.UserId) != expectedSid
        issues .= "任务账户不是当前用户。`r`n"
    for trigger in definition.Triggers {
        if trigger.Type = 9 && trigger.Enabled && AccountSID(trigger.UserId) = expectedSid
            validLogon := true
    }
    if !validLogon
        issues .= "缺少有效的用户登录触发器。`r`n"
    return issues
}

AccountSID(account) {
    if RegExMatch(account, "^S-1-\d+(-\d+)+$")
        return account
    if account = ""
        return ""
    sidSize := 0, domainSize := 0, use := 0
    DllCall("Advapi32\LookupAccountNameW", "Ptr", 0, "Str", account, "Ptr", 0,
        "UInt*", &sidSize, "Ptr", 0, "UInt*", &domainSize, "UInt*", &use)
    if !sidSize
        return ""
    sid := Buffer(sidSize), domain := Buffer(Max(2, domainSize * 2)), result := 0
    if !DllCall("Advapi32\LookupAccountNameW", "Ptr", 0, "Str", account, "Ptr", sid,
        "UInt*", &sidSize, "Ptr", domain, "UInt*", &domainSize, "UInt*", &use)
        return ""
    if !DllCall("Advapi32\ConvertSidToStringSidW", "Ptr", sid, "Ptr*", &result)
        return ""
    try return StrGet(result)
    finally DllCall("LocalFree", "Ptr", result)
}

StartupResult(code) {
    switch code {
        case 0: return "正常结束"
        case 0x41301: return "正在运行"
        case 0x41303: return "尚未运行"
        default: return Format("0x{:08X}（请检查任务计划程序与防护记录）", code & 0xFFFFFFFF)
    }
}

StartupErrorText(e) {
    code := HasProp(e, "Number") ? e.Number & 0xFFFF : 0
    hint := code = 1223 ? "管理员授权已取消。" : code = 5 || InStr(e.Message, "80070005")
        ? "权限不足，请使用当前账户的管理员授权。"
        : "请检查任务计划程序权限和安全软件的具体提示；若提示备份冲突，请先检查现有备份。"
    return "自启动设置未完成。`n" hint "`n`n详细信息：" e.Message
}
