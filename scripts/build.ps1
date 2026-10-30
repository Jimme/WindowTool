# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 JimmeYoumu
[CmdletBinding()]
param(
    [string]$AhkPath = "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe",
    [string]$CompilerPath = "$env:ProgramFiles\AutoHotkey\v2\Ahk2Exe.exe"
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$entryPath = Join-Path $projectRoot 'WindowTool.ahk'
$entryText = Get-Content -LiteralPath $entryPath -Raw
$runtimeText = Get-Content -LiteralPath (Join-Path $projectRoot 'TrayManager.ahk') -Raw
$metadataMatch = [regex]::Match($entryText, '(?m)^;@Ahk2Exe-SetVersion (\d+\.\d+\.\d+)\s*$')
$runtimeMatch = [regex]::Match($runtimeText, 'version: "(\d+\.\d+\.\d+)"')
if (!$metadataMatch.Success -or !$runtimeMatch.Success -or $metadataMatch.Groups[1].Value -ne $runtimeMatch.Groups[1].Value) {
    throw 'Compiler metadata and runtime version must match.'
}
$releaseVersion = $metadataMatch.Groups[1].Value
foreach ($toolPath in @($AhkPath, $CompilerPath)) {
    if (!(Test-Path -LiteralPath $toolPath -PathType Leaf)) { throw "Tool not found: $toolPath" }
}
$releaseDirectory = Join-Path $projectRoot "release\$releaseVersion"
New-Item -ItemType Directory -Path $releaseDirectory -Force | Out-Null
$outputPath = Join-Path $releaseDirectory 'WindowTool.exe'
$arguments = @('/in', ('"{0}"' -f $entryPath), '/out', ('"{0}"' -f $outputPath),
    '/base', ('"{0}"' -f $AhkPath), '/compress', '0', '/silent', 'verbose')
$compilerProcess = Start-Process -FilePath $CompilerPath -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru
if ($compilerProcess.ExitCode -ne 0 -or !(Test-Path -LiteralPath $outputPath)) { throw 'Build failed.' }
$actualVersion = (Get-Item -LiteralPath $outputPath).VersionInfo.ProductVersion
if ($actualVersion -ne $releaseVersion) { throw "Unexpected compiled version: $actualVersion" }
Copy-Item -LiteralPath (Join-Path $projectRoot 'README.md') -Destination (Join-Path $releaseDirectory 'README.md')
Copy-Item -LiteralPath (Join-Path $projectRoot 'LICENSE') -Destination $releaseDirectory
Copy-Item -LiteralPath (Join-Path $projectRoot 'docs') -Destination $releaseDirectory -Recurse -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'CHANGELOG.md') -Destination $releaseDirectory
Copy-Item -LiteralPath (Join-Path $projectRoot 'THIRD_PARTY.md') -Destination $releaseDirectory
Copy-Item -LiteralPath (Join-Path $projectRoot 'third-party') -Destination $releaseDirectory -Recurse -Force
$binaryHash = (Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash
Set-Content -LiteralPath (Join-Path $releaseDirectory 'SHA256.txt') -Value "$binaryHash  WindowTool.exe" -Encoding ascii
Write-Output "Built $releaseVersion : $outputPath"
