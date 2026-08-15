<#
.SYNOPSIS
  Publishes a release: writes both Windows update manifests and uploads them
  together with the Windows ZIP, Setup EXE, Android APK and Android AAB.

.DESCRIPTION
  Run AFTER building + zipping a release into dist\. Clients on an older build
  Build 144+ clients poll latest-v2.json while older clients poll latest.json.
  Both channels are updated atomically to the same verified Windows ZIP. Build
  the release with the build number baked in:

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
  [string]$ReleaseHistory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'assets\release_history.json'),
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

if (-not (Test-Path -LiteralPath $ReleaseHistory)) {
  throw "Release history not found: $ReleaseHistory"
}
$releaseHistoryJson = Get-Content -LiteralPath $ReleaseHistory -Raw
$releaseHistoryDocument = $releaseHistoryJson | ConvertFrom-Json
$releaseEntries = @($releaseHistoryDocument.releases)
$matchingEntries = @(
  $releaseEntries | Where-Object {
    $buildNumberProperty = $_.PSObject.Properties['buildNumber']
    $versionProperty = $_.PSObject.Properties['version']
    $null -ne $buildNumberProperty -and
      $null -ne $versionProperty -and
      [int]$buildNumberProperty.Value -eq $BuildNumber -and
      [string]$versionProperty.Value -eq $Version
  }
)
if ($matchingEntries.Count -ne 1) {
  throw "Release history must contain exactly one entry for $Version build $BuildNumber"
}
if ($releaseEntries.Count -eq 0 -or
    [int]$releaseEntries[0].buildNumber -ne $BuildNumber -or
    [string]$releaseEntries[0].version -ne $Version) {
  throw "Release history must start with the version being published: $Version"
}
if ([string]::IsNullOrWhiteSpace($Notes)) {
  $Notes = [string]$matchingEntries[0].summary
}
if ([string]::IsNullOrWhiteSpace($Notes)) {
  throw "Release notes must not be empty"
}

$pubspecPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'pubspec.yaml'
$pubspecVersionLine = Get-Content -LiteralPath $pubspecPath |
  Where-Object { $_ -match '^version:\s*' } |
  Select-Object -First 1
if ($pubspecVersionLine -notmatch ('^version:\s*' + [regex]::Escape($Version) + '\s*$')) {
  throw "pubspec.yaml version does not match the release: $Version"
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
$manifestNames = @('latest.json', 'latest-v2.json')
$releaseHistoryName = 'release-history.json'
$releaseHistoryOutputPath = Join-Path $Dist $releaseHistoryName
[System.IO.File]::WriteAllText(
  $releaseHistoryOutputPath,
  $releaseHistoryJson,
  (New-Object System.Text.UTF8Encoding($false))
)
$releaseArtifactNames = @(
  $zipName,
  "MagicMusicCRM-$verDash-Setup.exe",
  "MagicMusicCRM-$verDash.apk",
  "MagicMusicCRM-$verDash.aab",
  $releaseHistoryName
)

foreach ($artifactName in $releaseArtifactNames) {
  $artifactPath = Join-Path $Dist $artifactName
  if (-not (Test-Path -LiteralPath $artifactPath)) {
    throw "Release artifact not found: $artifactPath"
  }
}

foreach ($manifestName in $manifestNames) {
  $manifestPath = Join-Path $Dist $manifestName
  [System.IO.File]::WriteAllText(
    $manifestPath,
    $json,
    (New-Object System.Text.UTF8Encoding($false))
  )
}

Write-Host "SHA256: $hash"
Write-Host "Uploading release artifacts to $Remote ..."
foreach ($artifactName in $releaseArtifactNames) {
  $artifactPath = Join-Path $Dist $artifactName
  $remoteTemp = "$artifactName.tmp-$([Guid]::NewGuid().ToString('N'))"
  & scp -i $SshKey $artifactPath "$Remote`:$RemoteDir/$remoteTemp"
  Assert-NativeSuccess "Temporary artifact upload: $artifactName"
  & ssh -i $SshKey $Remote "mv -- '$RemoteDir/$remoteTemp' '$RemoteDir/$artifactName'"
  Assert-NativeSuccess "Atomic artifact publish: $artifactName"
}

foreach ($manifestName in $manifestNames) {
  $manifestPath = Join-Path $Dist $manifestName
  $remoteTemp = "$manifestName.tmp-$([Guid]::NewGuid().ToString('N'))"
  & scp -i $SshKey $manifestPath "$Remote`:$RemoteDir/$remoteTemp"
  Assert-NativeSuccess "Temporary manifest upload: $manifestName"
  & ssh -i $SshKey $Remote "mv -- '$RemoteDir/$remoteTemp' '$RemoteDir/$manifestName'"
  Assert-NativeSuccess "Atomic manifest publish: $manifestName"
}
Write-Host "Done. Clients below build $BuildNumber will see $Version after launch, resume, or the next background check."
