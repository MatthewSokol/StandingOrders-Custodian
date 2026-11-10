# Builds dist\Faves-<version>.zip for uploading to CurseForge (version read from Faves.toc).
# The zip holds one top-level Faves\ folder, which is what players extract into Interface\AddOns.
$src = Join-Path $PSScriptRoot "Faves"
$toc = Get-Content (Join-Path $src "Faves.toc")
$version = ($toc | Select-String '^## Version:\s*(.+)$').Matches[0].Groups[1].Value.Trim()

$dist = Join-Path $PSScriptRoot "dist"
New-Item -ItemType Directory -Force $dist | Out-Null
$zip = Join-Path $dist "Faves-$version.zip"
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path $src -DestinationPath $zip
Write-Host "Built $zip"
