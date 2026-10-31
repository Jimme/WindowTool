# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 JimmeYoumu
function Get-ProjectVersion([string]$ProjectRoot) {
    $entry = Get-Content -LiteralPath (Join-Path $ProjectRoot 'WindowTool.ahk') -Raw
    $numeric = [regex]::Match($entry, '(?m)^;@Ahk2Exe-SetVersion (\d+\.\d+\.\d+(?:\.\d+)?)\s*$').Groups[1].Value
    $display = [regex]::Match($entry, '(?m)^;@Ahk2Exe-SetProductVersion (\d+\.\d+\.\d+(?:-(?:alpha|beta|rc)\.[1-9]\d*)?)\s*$').Groups[1].Value
    if (!$display) { $display = $numeric }
    if ($display -notmatch '^(\d+\.\d+\.\d+)(?:-(?:alpha|beta|rc)\.([1-9]\d*))?$') { throw 'Invalid release version.' }
    $expected = $Matches[1]
    if ($Matches[2]) { $expected += '.' + $Matches[2] }
    if ($numeric -ne $expected) { throw 'Numeric metadata and display version must match.' }
    return $display
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
