# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 JimmeYoumu
function Get-ProjectVersionInfo([string]$ProjectRoot) {
    $entry = Get-Content -LiteralPath (Join-Path $ProjectRoot 'WindowTool.ahk') -Raw
    $numeric = [regex]::Match($entry, '(?m)^;@Ahk2Exe-SetVersion (\d+\.\d+\.\d+(?:\.\d+)?)\s*$').Groups[1].Value
    $display = [regex]::Match($entry, '(?m)^;@Ahk2Exe-SetProductVersion (\d+\.\d+\.\d+(?:-(?:alpha|beta|rc)\.[1-9]\d*)?)\s*$').Groups[1].Value
    if (!$display) { $display = $numeric }
    if ($display -notmatch '^(\d+\.\d+\.\d+)(?:-(?:alpha|beta|rc)\.([1-9]\d*))?$') { throw 'Invalid release version.' }
    $expected = $Matches[1]
    $isPrerelease = $display.Contains('-')
    $fileVersion = [version]$numeric
    if ($fileVersion.ToString(3) -ne $expected) { throw 'The first three file version components must match the product version.' }
    if ($fileVersion.Revision -lt 0) { $fileVersion = [version]"$numeric.0" }
    if (($fileVersion.ToString().Split('.') | Where-Object { [int]$_ -gt 65535 })) { throw 'Windows file version component exceeds 65535.' }

    $changes = Get-Content -LiteralPath (Join-Path $ProjectRoot 'CHANGELOG.md') -Raw -Encoding utf8
    $heading = '^## (?<product>\d+\.\d+\.\d+(?:-(?:alpha|beta|rc)\.\d+)?)(?=[\s（(]|$)'
    $fileLine = '(?m)^Windows 文件版本：`(?<file>\d+\.\d+\.\d+\.\d+)`[ \t]*\r?$'
    $currentCount = 0
    $lastRevision = -1
    foreach ($section in [regex]::Split($changes, '(?m)(?=^## )')) {
        if ($section -notmatch $heading) { continue }
        $product = $Matches['product']
        if ($product.Split('-')[0] -ne $expected) { continue }
        if ($section -notmatch $fileLine) { throw "Missing Windows file version for $product." }
        $recorded = [version]$Matches['file']
        if ($recorded.ToString(3) -ne $expected) { throw "Invalid file version for $product." }
        if ($product -eq $display) {
            $currentCount++
            if ($recorded -ne $fileVersion) { throw 'File version differs from the changelog.' }
        } else {
            $lastRevision = [Math]::Max($lastRevision, $recorded.Revision)
        }
    }
    if ($currentCount -ne 1) { throw 'Expected one changelog record for the current product and Windows file version.' }
    $nextRevision = if ($lastRevision -ge 0) { $lastRevision + 1 } elseif ($isPrerelease) { 1 } else { 0 }
    if ($fileVersion.Revision -ne $nextRevision) { throw "Expected Windows file revision $nextRevision for $display." }
    return [pscustomobject]@{ Product = $display; File = $fileVersion }
}

function Get-ProjectVersion([string]$ProjectRoot) {
    return (Get-ProjectVersionInfo $ProjectRoot).Product
}

function Assert-ExecutableVersion([string]$Path, $Expected) {
    $info = (Get-Item -LiteralPath $Path).VersionInfo
    $fixed = [version]::new($info.FileMajorPart, $info.FileMinorPart, $info.FileBuildPart, $info.FilePrivatePart)
    if ($info.ProductVersion -ne $Expected.Product -or $fixed -ne $Expected.File) {
        throw "Unexpected EXE versions: $($info.ProductVersion) / $fixed."
    }
}

function Get-BuildInputs([string]$ProjectRoot) {
    $paths = @(Get-ChildItem -LiteralPath $ProjectRoot -Filter '*.ahk' -File)
    $paths += @(Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'tests') -Filter '*.ahk' -File)
    $paths += @(Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'scripts') -Filter '*.ps1' -File)
    $paths += @(Get-Item -LiteralPath (Join-Path $ProjectRoot 'LICENSE'))
    $inputs = [ordered]@{}
    foreach ($file in ($paths | Sort-Object FullName)) {
        $relative = $file.FullName.Substring($ProjectRoot.TrimEnd('\').Length + 1).Replace('\', '/')
        $normalized = [IO.File]::ReadAllText($file.FullName).Replace("`r`n", "`n")
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $inputs[$relative] = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($normalized))).Replace('-', '') }
        finally { $sha.Dispose() }
    }
    return $inputs
}

function Assert-BuildInputs([string]$ProjectRoot, [string]$ReleaseDirectory) {
    $recordPath = Join-Path $ReleaseDirectory 'BUILD-INPUTS.json'
    if (!(Test-Path -LiteralPath $recordPath)) { throw 'Build record missing; rebuild before packaging.' }
    $record = Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json
    $current = Get-BuildInputs $ProjectRoot
    if (@($record.inputs.PSObject.Properties).Count -ne $current.Count) { throw 'Build input list changed; rebuild before packaging.' }
    foreach ($path in $current.Keys) {
        if ($record.inputs.$path -ne $current[$path]) { throw "Build input changed: $path. Rebuild before packaging." }
    }
    if ($record.binarySHA256 -ne (Get-FileHash -LiteralPath (Join-Path $ReleaseDirectory 'WindowTool.exe')).Hash) {
        throw 'Executable differs from the recorded build.'
    }
}
