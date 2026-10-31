# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 JimmeYoumu
function Get-BuildInputs([string]$ProjectRoot) {
    $paths = @(Get-ChildItem -LiteralPath $ProjectRoot -Filter '*.ahk' -File)
    $paths += @(Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'tests') -Filter '*.ahk' -File)
    $paths += @(Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'scripts') -Filter '*.ps1' -File)
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
