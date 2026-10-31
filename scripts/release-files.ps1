# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 JimmeYoumu
function Get-ReleaseFiles([string]$Directory) {
    $allowed = @('WindowTool.exe', 'BUILD-INPUTS.json', 'CHANGELOG.md', 'LICENSE', 'README.md',
        'RELEASE-MANIFEST.txt', 'SHA256.txt', 'THIRD_PARTY.md',
        'docs/BUILD-PROVENANCE.md', 'docs/DEVELOPMENT.md', 'docs/RELEASE-POLICY.md',
        'docs/REPOSITORY.md', 'docs/USAGE.md', 'third-party/AutoHotkey-LICENSE.txt',
        'sources/AutoHotkey-v2.0.26-source.zip')
    $root = (Resolve-Path -LiteralPath $Directory).Path.TrimEnd('\')
    foreach ($file in Get-ChildItem -LiteralPath $root -File -Recurse -Force) {
        $relative = $file.FullName.Substring($root.Length + 1).Replace('\', '/')
        if ($relative -notin $allowed) { throw "Unexpected release file: $relative. Move local data out before packaging." }
    }
    foreach ($relative in $allowed) {
        $path = Join-Path $root $relative
        if (!(Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing release file: $relative" }
        $path
    }
}

function New-ReleaseArchive([string]$Directory, [string]$Destination) {
    $files = @(Get-ReleaseFiles $Directory)
    $root = (Resolve-Path -LiteralPath $Directory).Path.TrimEnd('\')
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $stream = [IO.File]::Open($Destination, [IO.FileMode]::Create)
    try {
        $zip = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create, $true)
        try {
            foreach ($file in $files) {
                $entry = $file.Substring($root.Length + 1).Replace('\', '/')
                [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $file, $entry) | Out-Null
            }
        } finally { $zip.Dispose() }
    } finally { $stream.Dispose() }
}
