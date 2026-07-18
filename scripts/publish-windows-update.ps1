<#
.SYNOPSIS
  Publishes a Windows self-update: writes downloads/latest-v2.json and uploads
  it plus the build zip to the prod server (served by Caddy at /downloads/).

.DESCRIPTION
  Run AFTER building + zipping a release into dist\. Clients on an older build
  Build 144+ clients poll
  https://api.magicmusiccrm.ru/downloads/latest-v2.json on launch and offer the
  update. The legacy latest.json channel is intentionally left untouched so a
  build with the old broken helper cannot receive another update. Build the
  release with the build number baked in:

    flutter build windows --release `
      --dart-define=MAGIC_API_BASE_URL=https://api.magicmusiccrm.ru/api `
      --dart-define=APP_BUILD_NUMBER=<buildNumber>

  then package dist\MagicMusicCRM-<x.y.z-build>-windows-x64.zip, then run this.

.EXAMPLE
  ./scripts/publish-windows-update.ps1 -BuildNumber 144 -Version "1.2.2+144" `
    -Notes "Что нового в этой версии"
#>
param(
  [Parameter(Mandatory = $true)][int]$BuildNumber,
  [Parameter(Mandatory = $true)][string]$Version,   # e.g. 1.2.2+144
  [string]$Notes = "",
  [string]$Dist = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist'),
  [string]$SshKey = "C:\Users\potyl\.ssh\mmcrm_proxy_ed25519",
  [string]$Remote = "magicdeploy@161.104.49.153",
  [string]$RemoteDir = "/opt/magicmusiccrm/downloads"
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-NativeSuccess([string]$Operation) {
  if ($LASTEXITCODE -ne 0) {
    throw "$Operation failed with exit code $LASTEXITCODE"
  }
}

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
$manifestName = 'latest-v2.json'
$manifestPath = Join-Path $Dist $manifestName
[System.IO.File]::WriteAllText($manifestPath, $json, (New-Object System.Text.UTF8Encoding($false)))
$remoteZipTemp = "$zipName.tmp-$([Guid]::NewGuid().ToString('N'))"
$remoteManifestTemp = "$manifestName.tmp-$([Guid]::NewGuid().ToString('N'))"

Write-Host "SHA256: $hash"
Write-Host "Uploading $zipName + $manifestName to $Remote ..."
& scp -i $SshKey $zipPath "$Remote`:$RemoteDir/$remoteZipTemp"
Assert-NativeSuccess "Temporary ZIP upload"
& ssh -i $SshKey $Remote "mv -- '$RemoteDir/$remoteZipTemp' '$RemoteDir/$zipName'"
Assert-NativeSuccess "Atomic ZIP publish"
& scp -i $SshKey $manifestPath "$Remote`:$RemoteDir/$remoteManifestTemp"
Assert-NativeSuccess "Temporary manifest upload"
& ssh -i $SshKey $Remote "mv -- '$RemoteDir/$remoteManifestTemp' '$RemoteDir/$manifestName'"
Assert-NativeSuccess "Atomic manifest publish"
Write-Host "Done. Clients below build $BuildNumber will be offered $Version on next launch."
