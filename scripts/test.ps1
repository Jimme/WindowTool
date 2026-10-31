# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 JimmeYoumu
[CmdletBinding()]
param(
    [switch]$Compiled,
    [string]$AhkPath = "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe",
    [string]$Executable
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
if (!(Test-Path -LiteralPath $AhkPath -PathType Leaf)) { throw "AutoHotkey v2 not found: $AhkPath" }
$entryPath = Join-Path $projectRoot 'WindowTool.ahk'
. (Join-Path $PSScriptRoot 'build-inputs.ps1')
$releaseVersion = Get-ProjectVersion $projectRoot
$checkDirectory = Join-Path $projectRoot "build-check\$releaseVersion"
New-Item -ItemType Directory -Path (Join-Path $checkDirectory 'tests') -Force | Out-Null
if ($Compiled) {
    if (!$Executable) { $Executable = Join-Path $projectRoot "release\$releaseVersion\WindowTool.exe" }
    $programPath = Join-Path $checkDirectory 'WindowTool.exe'
    Copy-Item -LiteralPath $Executable -Destination $programPath -Force
    Copy-Item -LiteralPath (Join-Path $projectRoot 'tests\Fixture.ahk') -Destination (Join-Path $checkDirectory 'tests') -Force
    $arguments = @('--test')
    $resultPath = Join-Path $checkDirectory 'tests\results.txt'
} else {
    $programPath = $AhkPath
    $arguments = @('/ErrorStdOut', ('"{0}"' -f $entryPath), '--test')
    $resultPath = Join-Path $projectRoot 'tests\results.txt'
}
$previousRuntime = $env:WINDOWTOOL_AHK
try {
    $env:WINDOWTOOL_AHK = $AhkPath
    $testProcess = Start-Process -FilePath $programPath -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru `
        -RedirectStandardOutput (Join-Path $checkDirectory 'stdout.txt') `
        -RedirectStandardError (Join-Path $checkDirectory 'stderr.txt')
    if ($testProcess.ExitCode -ne 0) {
        foreach ($diagnosticPath in @((Join-Path $checkDirectory 'stdout.txt'), (Join-Path $checkDirectory 'stderr.txt'), $resultPath)) {
            if (Test-Path -LiteralPath $diagnosticPath) { Get-Content -LiteralPath $diagnosticPath }
        }
        throw "Tests failed with exit code $($testProcess.ExitCode)."
    }
    if (!(Test-Path -LiteralPath $resultPath) -or (Get-Content -LiteralPath $resultPath -First 1) -notmatch '^PASS \d+ checks$') {
        throw 'Test process returned without a PASS result.'
    }
    Get-Content -LiteralPath $resultPath
} finally {
    $env:WINDOWTOOL_AHK = $previousRuntime
}
