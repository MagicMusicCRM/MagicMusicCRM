<#
.SYNOPSIS
  Publishes a Windows self-update: writes downloads/latest.json and uploads it
  plus the build zip to the prod server (served by Caddy at /downloads/).

.DESCRIPTION
  Run AFTER building + zipping a release into dist\. Clients on an older build
  poll https://api.magicmusiccrm.ru/downloads/latest.json on launch and offer
  the update. Build the release with the build number baked in:

    flutter build windows --release `
      --dart-define=MAGIC_API_BASE_URL=https://api.magicmusiccrm.ru/api `
      --dart-define=APP_BUILD_NUMBER=<buildNumber>

  then package dist\MagicMusicCRM-<x.y.z-build>-windows-x64.zip, then run this.

.EXAMPLE
  ./scripts/publish-windows-update.ps1 -BuildNumber 143 -Version "1.2.1+143" `
    -Notes "Что нового в этой версии"
#>
param(
  [Parameter(Mandatory = $true)][int]$BuildNumber,
  [Parameter(Mandatory = $true)][string]$Version,   # e.g. 1.2.1+143
  [string]$Notes = "",
  [string]$Dist = "D:\Projects\MagicMusicCRM\dist",
  [string]$SshKey = "C:\Users\potyl\.ssh\mmcrm_proxy_ed25519",
  [string]$Remote = "magicdeploy@161.104.49.153",
  [string]$RemoteDir = "/opt/magicmusiccrm/downloads"
)
$ErrorActionPreference = 'Stop'

$verDash = $Version.Replace('+', '-')
$zipName = "MagicMusicCRM-$verDash-windows-x64.zip"
$zipPath = Join-Path $Dist $zipName
if (-not (Test-Path $zipPath)) { throw "Zip not found: $zipPath (build + package first)" }

$hash = (Get-FileHash -Algorithm SHA256 -Path $zipPath).Hash
$manifest = [ordered]@{
  buildNumber = $BuildNumber
  version     = $Version
  url         = "https://api.magicmusiccrm.ru/downloads/$zipName"
  sha256      = $hash
  notes       = $Notes
}
# UTF-8 without BOM so Cyrillic notes render correctly in the app.
$json = $manifest | ConvertTo-Json -Depth 4
$manifestPath = Join-Path $Dist "latest.json"
[System.IO.File]::WriteAllText($manifestPath, $json, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "SHA256: $hash"
Write-Host "Uploading $zipName + latest.json to $Remote ..."
& scp -i $SshKey $zipPath "$Remote`:$RemoteDir/$zipName"
& scp -i $SshKey $manifestPath "$Remote`:$RemoteDir/latest.json"
Write-Host "Done. Clients below build $BuildNumber will be offered $Version on next launch."
