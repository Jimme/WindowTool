# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 JimmeYoumu
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$entryText = Get-Content -LiteralPath (Join-Path $projectRoot 'WindowTool.ahk') -Raw
$releaseVersion = [regex]::Match($entryText, '(?m)^;@Ahk2Exe-SetVersion (\d+\.\d+\.\d+)\s*$').Groups[1].Value
if (!$releaseVersion) { throw 'Version metadata missing.' }
$releaseDirectory = Join-Path $projectRoot "release\$releaseVersion"
$sourceDirectory = Join-Path $releaseDirectory 'sources'
$assetDirectory = Join-Path $projectRoot "release\assets\$releaseVersion"
$runtimeSourcePath = Join-Path $sourceDirectory 'AutoHotkey-v2.0.26-source.zip'
$expectedRuntimeSourceHash = '765ADA5AE0A543F470BCD30371A7B95438E59351B0A20508C516DF76A4F73CA4'
if (!(Test-Path -LiteralPath $runtimeSourcePath) -or
    (Get-FileHash -LiteralPath $runtimeSourcePath).Hash -ne $expectedRuntimeSourceHash) {
    throw 'The verified AutoHotkey v2.0.26 source archive must be present under release/<version>/sources. See docs/BUILD-PROVENANCE.md.'
}
$dirtyFiles = @(& git -C $projectRoot status --porcelain)
if ($LASTEXITCODE -ne 0) { throw 'Git repository is required.' }
if ($dirtyFiles.Count) { throw 'Commit the final source tree before packaging.' }
$sourceCommit = & git -C $projectRoot rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'Source commit missing.' }
$binaryPath = Join-Path $releaseDirectory 'WindowTool.exe'
if ((Get-Item -LiteralPath $binaryPath).VersionInfo.ProductVersion -ne $releaseVersion) {
    throw 'Compiled version does not match the source version.'
}
$binaryHash = (Get-FileHash -LiteralPath $binaryPath).Hash
$sourceHash = (Get-FileHash -LiteralPath $runtimeSourcePath).Hash
$manifest = @(
    "WindowTool $releaseVersion - Windows x64",
    "Source commit: $sourceCommit",
    'License: GPL-2.0-or-later',
    "WindowTool.exe SHA256: $binaryHash",
    'Runtime: AutoHotkey 2.0.26 x64 (unmodified official base)',
    "Runtime source SHA256: $sourceHash",
    'Runtime source: sources/AutoHotkey-v2.0.26-source.zip',
    "Project source: WindowTool-$releaseVersion-source.zip (same GitHub Release)",
    'Known limitations: docs/USAGE.md'
)
Set-Content -LiteralPath (Join-Path $releaseDirectory 'RELEASE-MANIFEST.txt') -Value $manifest -Encoding utf8
New-Item -ItemType Directory -Path $assetDirectory -Force | Out-Null
$projectSourceZip = Join-Path $assetDirectory "WindowTool-$releaseVersion-source.zip"
& git -C $projectRoot archive --format=zip "--prefix=WindowTool-$releaseVersion/" -o $projectSourceZip HEAD
if ($LASTEXITCODE -ne 0) { throw 'Project source archive failed.' }
$binaryZip = Join-Path $assetDirectory "WindowTool-$releaseVersion-windows-x64.zip"
Compress-Archive -Path (Join-Path $releaseDirectory '*') -DestinationPath $binaryZip -Force
$checksums = foreach ($asset in @($binaryZip, $projectSourceZip)) {
    '{0}  {1}' -f (Get-FileHash -LiteralPath $asset).Hash, (Split-Path $asset -Leaf)
}
Set-Content -LiteralPath (Join-Path $assetDirectory 'SHA256SUMS.txt') -Value $checksums -Encoding ascii
Get-ChildItem -LiteralPath $assetDirectory | Select-Object Name, Length
