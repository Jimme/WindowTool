; SPDX-License-Identifier: GPL-2.0-or-later
; Copyright (C) 2026 JimmeYoumu
#Requires AutoHotkey v2.0
#SingleInstance Off
global WT := {}
#Include ../Startup.ahk
output := A_ScriptDir "\startup-results.txt"
childOutput := A_ScriptDir "\startup-child.txt"
if A_Args.Length && A_Args[1] = "--child" {
    FileAppend(A_IsAdmin "|" StartupSID(), childOutput, "UTF-8")
    ExitApp()
}
folder := 0, created := false, link := "", failed := false
name := "WindowTool.Test.Startup." DllCall("GetCurrentProcessId")
FileOpen(output, "w", "UTF-8").Write("RUNNING: SID`n")
try {
    sid := StartupSID()
    FileAppend("RUNNING: COM`n", output, "UTF-8")
    service := ComObject("Schedule.Service")
    service.Connect()
    folder := service.GetFolder("\")
    FileAppend("RUNNING: lookup`n", output, "UTF-8")
    if StartupTask(folder, name)
        throw Error("测试任务名称已占用")
    definition := StartupDefinition(service, sid, A_IsCompiled ? A_ScriptFullPath : A_AhkPath)
    FileAppend("RUNNING: register`n", output, "UTF-8")
    definition.Actions.Item(1).Arguments := A_IsCompiled ? "--child" : '/ErrorStdOut "' A_ScriptFullPath '" --child'
    definition.Actions.Item(1).WorkingDirectory := A_ScriptDir
    folder.RegisterTaskDefinition(name, definition, 2, sid, , 3)
    created := true
    task := folder.GetTask(name)
    StartupOwned(task)
    actual := task.Definition
    if actual.Principal.RunLevel != 1 || actual.Principal.LogonType != 3
        throw Error("权限或交互会话错误")
    triggerUser := actual.Triggers.Item(1).UserId
    if triggerUser = "" || actual.Triggers.Item(1).Delay != "PT10S"
        throw Error("登录触发条件错误：" triggerUser " / " actual.Triggers.Item(1).Delay)
    if actual.Settings.DisallowStartIfOnBatteries || actual.Settings.StopIfGoingOnBatteries
        || actual.Settings.ExecutionTimeLimit != "PT0S" || actual.Settings.MultipleInstances != 2
        throw Error("常驻运行条件错误")
    if FileExist(childOutput)
        FileDelete(childOutput)
    task.Run("")
    Loop 100 {
        if FileExist(childOutput)
            break
        Sleep(100)
    }
    if !FileExist(childOutput) || FileRead(childOutput, "UTF-8") != "1|" sid
        throw Error("任务未能在同一用户下提权运行")
    ; 仅操作独立测试链接，目标是唯一不存在的测试 EXE，绝不启动它。
    link := A_Startup "\WindowTool-Test-" DllCall("GetCurrentProcessId") ".lnk"
    target := A_ScriptDir "\WindowTool-Test-" DllCall("GetCurrentProcessId") ".exe"
    FileCreateShortcut(target, link)
    links := StartupLinks(target)
    if links.Length != 1 || links[1] != link
        throw Error("快捷方式匹配失败")
    FileDelete(link)
    Sleep(200)
    FileCreateShortcut(target, link, , "--other")
    if StartupLinks(target).Length != 0
        throw Error("不应迁移带参数快捷方式")
    definition.RegistrationInfo.Source := "foreign task"
    rejected := false
    try StartupOwned({Definition: definition})
    catch
        rejected := true
    if !rejected
        throw Error("没有拒绝非自有任务")
    if A_IsCompiled {
        folder.DeleteTask(name, 0)
        created := false
        FileDelete(link)
        Sleep(200)
        FileCreateShortcut(A_ScriptFullPath, link)
        ConfigureStartup(true, sid, name)
        created := true
        backup := link ".WindowTool-disabled"
        if FileExist(link) || !FileExist(backup) || !StartupTask(folder, name)
            throw Error("启用与迁移失败")
        ConfigureStartup(true, sid, name)
        oldXML := folder.GetTask(name).Xml
        FileCreateShortcut(A_ScriptFullPath, link)
        rejected := false
        try ConfigureStartup(true, sid, name)
        catch
            rejected := true
        if !rejected || folder.GetTask(name).Xml != oldXML || !FileExist(link)
            throw Error("更新失败没有恢复原任务和快捷方式")
        FileDelete(link)
        ConfigureStartup(false, sid, name)
        created := false
        if StartupTask(folder, name) || FileExist(link) || !FileExist(backup)
            throw Error("关闭任务错误地恢复了旧快捷方式")
        FileCreateShortcut(A_ScriptFullPath, link)
        rejected := false
        try ConfigureStartup(true, sid, name)
        catch
            rejected := true
        if !rejected || StartupTask(folder, name) || !FileExist(link) || !FileExist(backup)
            throw Error("备份冲突没有安全回滚")
    }
    FileOpen(output, "w", "UTF-8").Write("PASS: task registration, interactive elevation, trigger/settings, shortcut matching, ownership guard"
        . (A_IsCompiled ? ", enable/update/disable, migration and rollback" : "") "`n")
} catch Error as e {
    FileAppend("FAIL: " e.Message "`n" e.Stack, output, "UTF-8")
    failed := true
} finally {
    if created
        folder.DeleteTask(name, 0)
    if link != "" && FileExist(link)
        FileDelete(link)
    if IsSet(backup) && FileExist(backup)
        FileDelete(backup)
}
ExitApp(failed ? 1 : 0)
