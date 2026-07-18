param(
  [string]$DeviceId = "",
  [string]$ApiBaseUrl = "https://api.magicmusiccrm.ru/api",
  [string]$EvidenceDir = ".supergoal/hollihop-crm-import-adaptation-loading-ux-Guw3IO/evidence",
  [switch]$SkipBuild,
  [switch]$RunIntegrationSmoke,
  [switch]$CheckOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$evidenceRoot = Join-Path $repoRoot $EvidenceDir
$timestamp = Get-Date -Format "yyyyMMddTHHmmss"
$apkPath = Join-Path $repoRoot "build/app/outputs/flutter-apk/app-debug.apk"

function Write-Step {
  param([string]$Message)
  Write-Host "==> $Message"
}

function Invoke-LoggedCommand {
  param(
    [string]$Name,
    [string]$LogPath,
    [string[]]$Command
  )

  Write-Step $Name
  $executable = $Command[0]
  $arguments = @()
  if ($Command.Length -gt 1) {
    $arguments = $Command[1..($Command.Length - 1)]
  }

  $output = & $executable @arguments 2>&1
  $exitCode = $LASTEXITCODE
  $output | Tee-Object -FilePath $LogPath

  if ($exitCode -ne 0) {
    throw "$Name failed with exit code $exitCode. See $LogPath"
  }
}

function Find-Adb {
  $candidates = @()
  if ($env:ANDROID_HOME) {
    $candidates += Join-Path $env:ANDROID_HOME "platform-tools/adb.exe"
  }
  if ($env:ANDROID_SDK_ROOT) {
    $candidates += Join-Path $env:ANDROID_SDK_ROOT "platform-tools/adb.exe"
  }
  if ($env:LOCALAPPDATA) {
    $candidates += Join-Path $env:LOCALAPPDATA "Android/Sdk/platform-tools/adb.exe"
  }

  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate) {
      return (Resolve-Path -LiteralPath $candidate).Path
    }
  }

  $pathAdb = Get-Command adb -ErrorAction SilentlyContinue
  if ($pathAdb) {
    return $pathAdb.Source
  }

  return $null
}

function Get-FlutterDevices {
  $devicesJson = & flutter devices --machine 2>&1
  if ($LASTEXITCODE -ne 0) {
    $devicesJson | Tee-Object -FilePath (Join-Path $evidenceRoot "android-real-device-devices-$timestamp.error.txt")
    throw "flutter devices --machine failed"
  }

  $devicesPath = Join-Path $evidenceRoot "android-real-device-devices-$timestamp.json"
  $devicesJson | Set-Content -LiteralPath $devicesPath
  return $devicesJson | ConvertFrom-Json
}

function Select-AndroidDevice {
  param([object[]]$Devices)

  $androidDevices = @(
    $Devices | Where-Object {
      ($_.targetPlatform -like "android*") -and
      ($_.id -ne "chrome") -and
      ($_.id -ne "edge") -and
      ($_.id -ne "windows")
    }
  )

  if ($DeviceId.Trim().Length -gt 0) {
    $selected = $androidDevices | Where-Object { $_.id -eq $DeviceId } | Select-Object -First 1
    if (-not $selected) {
      throw "Requested Android device '$DeviceId' was not found by flutter devices."
    }
    return $selected
  }

  $physicalDevices = @(
    $androidDevices | Where-Object {
      -not ($_.PSObject.Properties.Name -contains "emulator") -or
      $_.emulator -ne $true
    }
  )

  if ($physicalDevices.Count -eq 0) {
    throw "No physical Android device is connected. Connect a stable device and rerun this script."
  }
  if ($physicalDevices.Count -gt 1) {
    $ids = ($physicalDevices | ForEach-Object { $_.id }) -join ", "
    throw "Multiple physical Android devices detected ($ids). Rerun with -DeviceId <id>."
  }

  return $physicalDevices[0]
}

New-Item -ItemType Directory -Force -Path $evidenceRoot | Out-Null
Set-Location $repoRoot

Write-Step "Android real-device smoke helper"
Write-Host "Repo: $repoRoot"
Write-Host "Evidence: $evidenceRoot"
Write-Host "API base URL: $ApiBaseUrl"

if ($ApiBaseUrl -notmatch "^https://") {
  throw "ApiBaseUrl must be HTTPS."
}
if ($ApiBaseUrl -match "HOLLIHOP|MIGRATION|DATABASE|PASSWORD|TOKEN|SECRET") {
  throw "ApiBaseUrl looks like a secret-bearing value. Refusing to continue."
}

$flutter = Get-Command flutter -ErrorAction Stop
Write-Host "Flutter: $($flutter.Source)"

if ($CheckOnly) {
  Write-Step "CheckOnly completed"
  Write-Host "The script is loadable. Device/build steps were intentionally skipped."
  exit 0
}

$devices = @(Get-FlutterDevices)
$device = Select-AndroidDevice -Devices $devices
$deviceId = $device.id
Write-Host "Selected device: $($device.name) [$deviceId] target=$($device.targetPlatform)"

if (-not $SkipBuild) {
  Invoke-LoggedCommand `
    -Name "Build debug APK" `
    -LogPath (Join-Path $evidenceRoot "android-real-device-build-$timestamp.log") `
    -Command @("flutter", "build", "apk", "--debug", "--dart-define=MAGIC_API_BASE_URL=$ApiBaseUrl")
}

if (-not (Test-Path -LiteralPath $apkPath)) {
  throw "Debug APK not found at $apkPath"
}

$apkHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $apkPath).Hash
$summaryPath = Join-Path $evidenceRoot "android-real-device-summary-$timestamp.md"
@(
  "# Android Real-Device Smoke Summary"
  ""
  "- Timestamp: ``$timestamp``"
  "- Device id: ``$deviceId``"
  "- Device name: ``$($device.name)``"
  "- Target platform: ``$($device.targetPlatform)``"
  "- API base URL: ``$ApiBaseUrl``"
  "- APK: ``$apkPath``"
  "- APK SHA-256: ``$apkHash``"
) | Set-Content -LiteralPath $summaryPath

if ($RunIntegrationSmoke) {
  Invoke-LoggedCommand `
    -Name "Run integration smoke on Android device" `
    -LogPath (Join-Path $evidenceRoot "android-real-device-integration-$timestamp.log") `
    -Command @("flutter", "test", "integration_test/app_launch_smoke_test.dart", "-d", $deviceId, "--dart-define=MAGIC_API_BASE_URL=$ApiBaseUrl")
}

Invoke-LoggedCommand `
  -Name "Install debug APK" `
  -LogPath (Join-Path $evidenceRoot "android-real-device-install-$timestamp.log") `
  -Command @("flutter", "install", "-d", $deviceId, "--use-application-binary", $apkPath)

$adb = Find-Adb
if ($adb) {
  Write-Step "Launch app and capture logcat"
  & $adb -s $deviceId shell logcat -c | Out-Null
  & $adb -s $deviceId shell am start -n "magic.crm/com.magicmusiccrm.magic_music_crm.MainActivity" | Out-Null
  Start-Sleep -Seconds 20

  $logcatPath = Join-Path $evidenceRoot "android-real-device-logcat-$timestamp.txt"
  & $adb -s $deviceId shell logcat -d | Set-Content -LiteralPath $logcatPath
  Add-Content -LiteralPath $summaryPath -Value "- Logcat: ``$logcatPath``"

  $fatalMatches = Select-String -LiteralPath $logcatPath -Pattern "FATAL EXCEPTION|FlutterError|Dart Error" -AllMatches
  if ($fatalMatches) {
    $fatalPath = Join-Path $evidenceRoot "android-real-device-logcat-fatal-$timestamp.txt"
    $fatalMatches | ForEach-Object { $_.Line } | Set-Content -LiteralPath $fatalPath
    throw "Fatal Flutter/Dart/native markers found. See $fatalPath"
  }
  Add-Content -LiteralPath $summaryPath -Value "- Log review: no FATAL EXCEPTION, FlutterError or Dart Error markers."
} else {
  Add-Content -LiteralPath $summaryPath -Value "- Logcat: not captured because adb was not found."
  Write-Warning "adb was not found. Manual log capture is still required by docs/runbooks/android-real-device-smoke.md."
}

Write-Step "Smoke helper completed"
Write-Host "Summary: $summaryPath"
Write-Host "Continue manual UI checklist in docs/runbooks/android-real-device-smoke.md and record cleanup evidence."
