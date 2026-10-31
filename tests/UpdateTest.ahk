; SPDX-License-Identifier: GPL-2.0-or-later
; Copyright (C) 2026 JimmeYoumu
#Requires AutoHotkey v2.0
#Include ../Updates.ahk
g := Gui()
global WT := {version: "0.0.0", updateButton: g.AddButton(, "检查更新"),
    releaseButton: g.AddButton(, "发布页"), updateStatus: g.AddText("w500", "")}
output := A_ScriptDir "\update-results.txt"
try {
    for pair in [["0.1.3", "0.1.2"], ["0.1.10", "0.1.9"], ["0.2.0", "0.1.99"], ["1.0.0", "0.99.99"]]
        if !IsNewerVersion(pair[1], pair[2]) || IsNewerVersion(pair[2], pair[1])
            throw Error("版本比较失败")
    if IsNewerVersion("0.1.2", "0.1.2") || LatestReleaseVersion('{"tag_name":"v0.1.2"}') != "0.1.2"
        throw Error("相同版本或版本解析失败")
    for pair in [["0.1.3", "0.1.3-alpha.1"], ["0.1.3-alpha.2", "0.1.3-alpha.1"],
        ["0.1.3-alpha.10", "0.1.3-alpha.2"], ["0.1.3-rc.1", "0.1.3-alpha.9"], ["0.1.3-alpha.1", "0.1.2"]]
        if !IsNewerVersion(pair[1], pair[2]) || IsNewerVersion(pair[2], pair[1])
            throw Error("先行版比较失败")
    if IsNewerVersion("0.1.3+build.2", "0.1.3+build.1")
        throw Error("构建元数据不应改变排序")
    rejected := false
    try LatestReleaseVersion('{"tag_name":"v0.1.3-beta"}')
    catch
        rejected := true
    if !rejected
        throw Error("应拒绝预发布或无效版本")
    CheckForUpdates()
    if WT.updateButton.Enabled
        throw Error("检查期间没有禁用重复操作：" WT.updateStatus.Text)
    deadline := A_TickCount + 18000
    while WT.updateRequest && A_TickCount < deadline
        Sleep(50)
    if WT.updateRequest || !WT.updateButton.Enabled || !InStr(WT.updateStatus.Text, "发现新版本")
        throw Error("实时异步检查失败：" WT.updateStatus.Text)
    live := WT.updateStatus.Text
    WT.version := "0.1.2"
    WT.updateRequest := {Status: 200, ResponseText: '{"tag_name":"v0.1.2"}'}
    FinishUpdateCheck()
    if !InStr(WT.updateStatus.Text, "已是最新版本")
        throw Error("相同版本提示错误")
    WT.version := "0.1.3-alpha.1"
    WT.updateRequest := {Status: 200, ResponseText: '{"tag_name":"v0.1.2"}'}
    FinishUpdateCheck()
    if !InStr(WT.updateStatus.Text, "测试版") || !InStr(WT.updateStatus.Text, "最新正式版 0.1.2")
        throw Error("测试版与正式版提示不明确")
    WT.updateRequest := {Status: 403, ResponseText: "API rate limit exceeded"}
    FinishUpdateCheck()
    if !InStr(WT.updateStatus.Text, "频繁")
        throw Error("限流提示错误")
    WT.updateRequest := {Status: 403, ResponseText: "Forbidden"}
    FinishUpdateCheck()
    if !InStr(WT.updateStatus.Text, "拒绝访问") || InStr(WT.updateStatus.Text, "频繁")
        throw Error("普通 403 不应误报限流")
    WT.updateRequest := {Status: 200, ResponseText: "invalid response"}
    FinishUpdateCheck()
    if !InStr(WT.updateStatus.Text, "无法读取")
        throw Error("异常响应没有提示")
    CheckForUpdates()
    UpdateTimedOut()
    if WT.updateRequest || !WT.updateButton.Enabled || !InStr(WT.updateStatus.Text, "超时")
        throw Error("超时清理失败")
    CheckForUpdates()
    FinishUpdateCheck("测试连接失败")
    if WT.updateRequest || !WT.updateButton.Enabled || WT.updateStatus.Text != "测试连接失败"
        throw Error("失败后重试状态错误")
    FileOpen(output, "w", "UTF-8").Write("PASS: numeric versions, parsing, async live request, timeout and error recovery`n" live)
} catch Error as e {
    FileOpen(output, "w", "UTF-8").Write("FAIL: " e.Message "`n" e.Stack)
    ExitApp(1)
}
ExitApp()
