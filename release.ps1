# Builds the CurseForge upload: dist\Faves-<version>.zip with one top-level Faves\ folder (the addon files,
# which include LICENSE.txt). The version comes from the .toc. Zip entries use forward slashes, which Compress-Archive on
# Windows PowerShell 5.1 doesn't (CurseForge and Mac/Linux unzip choke on backslashes). Every entry is dated
# 00:00 UTC of today, like the commits, so the zip doesn't show when you worked.
# Run tools\green.js first: RELEASING.md has the whole pipeline.
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

$name = "Faves"
$root = $PSScriptRoot
$src = Join-Path $root $name
$toc = Get-Content (Join-Path $src "$name.toc")
$version = ($toc | Where-Object { $_ -match '^## Version:\s*(.+)$' } | ForEach-Object { $Matches[1].Trim() }) | Select-Object -First 1
if (-not $version) { throw "No '## Version:' line in the .toc" }

$dist = Join-Path $root "dist"
New-Item -ItemType Directory -Force $dist | Out-Null
$zipPath = Join-Path $dist "$name-$version.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

$files = @(Get-ChildItem $src -Recurse -File | ForEach-Object {
    @{ Path = $_.FullName; Entry = "$name/" + $_.FullName.Substring($src.Length + 1).Replace('\', '/') }
})
if (-not (Test-Path (Join-Path $src "LICENSE.txt"))) {
    $files += @{ Path = (Join-Path $root "LICENSE"); Entry = "$name/LICENSE" }
}

$stamp = [DateTimeOffset]::new([DateTime]::UtcNow.Date, [TimeSpan]::Zero)
$zip = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($f in $files) {
        $entry = $zip.CreateEntry($f.Entry, [System.IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime = $stamp
        $out = $entry.Open()
        $in = [System.IO.File]::OpenRead($f.Path)
        try { $in.CopyTo($out) } finally { $in.Dispose(); $out.Dispose() }
    }
} finally { $zip.Dispose() }
Write-Host "Built $zipPath ($($files.Count) files)"
