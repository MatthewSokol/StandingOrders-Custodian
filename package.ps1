# Builds dist\Faves-<version>.zip for uploading to CurseForge. The version comes from the vX.Y.Z tag on HEAD
# and fills the .toc's @project-version@ (the BigWigs packager does the same from the tag).
# The zip holds one top-level Faves\ folder, which is what players extract into Interface\AddOns.
# Test build from an untagged commit: -Version 1.2.3-test
param([string]$Version)
$src = Join-Path $PSScriptRoot "Faves"

$tag = $null
if (-not $Version) {
    $tag = git -C $PSScriptRoot describe --tags --exact-match 2>$null
    if (-not $tag) { Write-Error "HEAD has no release tag. Tag the release on main first (git tag vX.Y.Z), or pass -Version for a test build."; exit 1 }
    $Version = $tag -replace "^v", ""
}
$tocVersion = if ($tag) { $tag } else { $Version }

$dist = Join-Path $PSScriptRoot "dist"
New-Item -ItemType Directory -Force $dist | Out-Null
$zip = Join-Path $dist "Faves-$Version.zip"
if (Test-Path $zip) { Remove-Item $zip }

# Zip a staged copy so the .toc in the zip has the version filled in.
$stage = Join-Path ([IO.Path]::GetTempPath()) ("Faves-package-" + [guid]::NewGuid())
$staged = Join-Path $stage "Faves"
try {
    New-Item -ItemType Directory -Force $stage | Out-Null
    Copy-Item $src $staged -Recurse
    Get-ChildItem $staged -Filter *.toc | ForEach-Object {
        $text = [IO.File]::ReadAllText($_.FullName)
        [IO.File]::WriteAllText($_.FullName, $text.Replace("@project-version@", $tocVersion))
    }
    Compress-Archive -Path $staged -DestinationPath $zip
} finally { Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue }
Write-Host "Built $zip"
