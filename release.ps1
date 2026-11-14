# Builds the CurseForge upload: dist\StandingOrders_Quartermaster-<version>.zip with one top-level StandingOrders_Quartermaster\ folder (the addon files,
# which include LICENSE.txt), and dist\StandingOrders_Quartermaster-<version>-changelog.md, the release notes to paste.
# The version comes from the vX.Y.Z release tag on HEAD and fills the .toc's @project-version@, as the BigWigs
# packager does. Test build from an untagged commit: -Version 1.2.3-test
# Zip entries use forward slashes, which Compress-Archive on Windows PowerShell 5.1 doesn't (CurseForge and
# Mac/Linux unzip choke on backslashes). Every entry is dated 00:00 UTC of today, like the commits.
# RELEASING.md has the whole pipeline.
param([string]$Version)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

$name = "StandingOrders_Quartermaster"
$root = $PSScriptRoot
$src = Join-Path $root $name

# The release tag on HEAD gives the version (v1.2.3 -> 1.2.3). --match skips dev-routine's candidate/ tags on
# the same commit. git's stderr on an untagged commit must not stop the script.
$tag = $null
if (-not $Version) {
    $ErrorActionPreference = "Continue"
    $tag = git -C $root describe --tags --exact-match --match "v[0-9]*" 2>$null
    $ErrorActionPreference = "Stop"
    if (-not $tag) { throw "HEAD has no release tag. Tag the release on main first (git tag vX.Y.Z), or pass -Version for a test build." }
    $Version = $tag -replace '^v', ''
}
$tocVersion = if ($tag) { $tag } else { $Version }

# Release notes: every CHANGELOG.md entry from this version down to the previous release tag's (each merged
# change has its own candidate entry). A test build takes the top entry.
$changelog = [IO.File]::ReadAllText((Join-Path $root "CHANGELOG.md"))
$start = [regex]::Match($changelog, "(?m)^## \[" + [regex]::Escape($Version) + "\]")
if (-not $start.Success) { $start = [regex]::Match($changelog, "(?m)^## \[") }
$rest = $changelog.Substring($start.Index)
$prev = $null
if ($tag) {
    $ErrorActionPreference = "Continue"
    $prev = git -C $root describe --tags --abbrev=0 --match "v[0-9]*" "$tag^" 2>$null
    $ErrorActionPreference = "Stop"
}
$next = if ($prev) { "(?m)^## \[" + [regex]::Escape(($prev -replace '^v', '')) + "\]" } elseif ($tag) { "(?!)" } else { "(?m)(?<!\A)^## \[" }
$end = [regex]::Match($rest, $next)
$notes = if ($end.Success) { $rest.Substring(0, $end.Index) } else { $rest }

$dist = Join-Path $root "dist"
New-Item -ItemType Directory -Force $dist | Out-Null
$notesPath = Join-Path $dist "$name-$Version-changelog.md"
[IO.File]::WriteAllText($notesPath, $notes.Trim() + "`n")
$zipPath = Join-Path $dist "$name-$Version.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

$files = @(Get-ChildItem $src -Recurse -File | ForEach-Object {
    @{ Path = $_.FullName; Entry = "$name/" + $_.FullName.Substring($src.Length + 1).Replace('\', '/') }
})

$stamp = [DateTimeOffset]::new([DateTime]::UtcNow.Date, [TimeSpan]::Zero)
$zip = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($f in $files) {
        $entry = $zip.CreateEntry($f.Entry, [System.IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime = $stamp
        $out = $entry.Open()
        $in = [System.IO.File]::OpenRead($f.Path)
        try {
            if ($f.Path -like '*.toc') {
                $bytes = [Text.Encoding]::UTF8.GetBytes([IO.File]::ReadAllText($f.Path).Replace('@project-version@', $tocVersion))
                $out.Write($bytes, 0, $bytes.Length)
            } else { $in.CopyTo($out) }
        } finally { $in.Dispose(); $out.Dispose() }
    }
} finally { $zip.Dispose() }
Write-Host "Built $zipPath ($($files.Count) files)"
Write-Host "Release notes (paste into CurseForge): $notesPath"
