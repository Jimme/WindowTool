; SPDX-License-Identifier: GPL-2.0-or-later
; Copyright (C) 2026 JimmeYoumu
; 仅在用户点击时联网；异步检查，不下载或执行更新。
CheckForUpdates(*) {
    global WT
    if HasProp(WT, "updateRequest") && WT.updateRequest
        return
    WT.updateButton.Enabled := false
    WT.releaseButton.Visible := false
    WT.updateStatus.Text := "正在检查…"
    WT.updateRequest := 0
    try {
        request := ComObject("WinHttp.WinHttpRequest.5.1")
        WT.updateRequest := request
        request.SetTimeouts(4000, 4000, 4000, 6000)
        request.Open("GET", "https://api.github.com/repos/Jimme/WindowTool/releases/latest", true)
        request.SetRequestHeader("Accept", "application/vnd.github+json")
        request.SetRequestHeader("User-Agent", "WindowTool/" WT.version)
        SetTimer(UpdateTimedOut, -15000)
        request.Send()
        SetTimer(PollUpdateCheck, 100)
    } catch Error as e {
        FinishUpdateCheck("检查失败：" e.Message)
    }
}

PollUpdateCheck() {
    global WT
    if !WT.updateRequest
        return
    try {
        if WT.updateRequest.WaitForResponse(0)
            FinishUpdateCheck()
    } catch {
        FinishUpdateCheck("无法连接 GitHub，请检查网络后重试。")
    }
}

UpdateTimedOut() {
    FinishUpdateCheck("检查超时，请稍后重试。")
}

LatestReleaseVersion(body) {
    if !RegExMatch(body, '"tag_name"\s*:\s*"v?(\d+\.\d+\.\d+)"', &match)
        throw ValueError("无效的版本响应")
    return match[1]
}

IsNewerVersion(latest, current) {
    left := UpdateVersionParts(latest), right := UpdateVersionParts(current)
    Loop 3 {
        if Integer(left.core[A_Index]) != Integer(right.core[A_Index])
            return Integer(left.core[A_Index]) > Integer(right.core[A_Index])
    }
    if !left.pre.Length || !right.pre.Length
        return !left.pre.Length && !!right.pre.Length
    Loop Min(left.pre.Length, right.pre.Length) {
        a := left.pre[A_Index], b := right.pre[A_Index]
        if a == b
            continue
        an := RegExMatch(a, "^\d+$"), bn := RegExMatch(b, "^\d+$")
        return an && bn ? Integer(a) > Integer(b) : an != bn ? !an : StrCompare(a, b, true) > 0
    }
    return left.pre.Length > right.pre.Length
}

UpdateVersionParts(value) {
    if !RegExMatch(value, "^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$", &m)
        throw ValueError("无效的版本号")
    pre := m[4] = "" ? [] : StrSplit(m[4], ".")
    for part in pre
        if RegExMatch(part, "^0\d+$")
            throw ValueError("无效的先行版本号")
    return {core: [m[1], m[2], m[3]], pre: pre}
}

FinishUpdateCheck(errorText := "") {
    global WT
    if (!HasProp(WT, "updateRequest") || !WT.updateRequest) && errorText = ""
        return
    request := HasProp(WT, "updateRequest") ? WT.updateRequest : 0
    WT.updateRequest := 0
    SetTimer(UpdateTimedOut, 0)
    SetTimer(PollUpdateCheck, 0)
    text := errorText
    try {
        if text = "" {
            if request.Status != 200
                text := UpdateHttpError(request)
            else {
                latest := LatestReleaseVersion(request.ResponseText)
                newer := IsNewerVersion(latest, WT.version)
                text := newer ? "发现新版本 " latest "，当前为 " WT.version "。"
                    : InStr(WT.version, "-") ? "当前为测试版 " WT.version "；最新正式版 " latest "。"
                    : "当前已是最新版本（" WT.version "）。"
            }
        }
    } catch {
        text := "无法读取版本信息，请打开发布页查看。"
    }
    try request.Abort()
    WT.updateButton.Enabled := true
    WT.updateStatus.Text := text
    WT.releaseButton.Visible := true
}

UpdateHttpError(request) {
    limited := request.Status = 429
    if request.Status = 403 {
        try limited := request.GetResponseHeader("X-RateLimit-Remaining") = "0"
        try limited := limited || request.GetResponseHeader("Retry-After") != ""
        try limited := limited || RegExMatch(request.ResponseText, "i)rate.limit")
    }
    return limited ? "请求过于频繁，请稍后重试。"
        : request.Status = 403 ? "GitHub 拒绝访问（HTTP 403），请检查网络或打开发布页。"
        : "检查失败（HTTP " request.Status "），请稍后重试。"
}
