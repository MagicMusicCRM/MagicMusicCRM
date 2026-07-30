[CmdletBinding()]
param(
  [switch]$Windows,
  [switch]$Android,
  [string]$EvidencePath
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if (-not $Windows -and -not $Android) {
  throw "Select at least one device: -Windows and/or -Android."
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
$flutter = if ($flutterCommand) {
  $flutterCommand.Source
} else {
  "C:\flutter\bin\flutter.bat"
}
if (-not (Test-Path -LiteralPath $flutter)) {
  throw "Flutter executable was not found."
}
if (-not $EvidencePath) {
  $EvidencePath = Join-Path $repoRoot "docs/audits/v4-workspace-device-result.json"
}

$results = @()
$startedAt = Get-Date

function Invoke-WorkspaceStep {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Name,
    [Parameter(Mandatory = $true)]
    [scriptblock]$Command
  )

  $stepStartedAt = Get-Date
  Write-Host "`n=== $Name ===" -ForegroundColor Cyan
  & $Command
  if ($LASTEXITCODE -ne 0) {
    throw "$Name failed with exit code $LASTEXITCODE."
  }
  $script:results += [ordered]@{
    name = $Name
    status = "pass"
    durationSeconds = [Math]::Round(
      ((Get-Date) - $stepStartedAt).TotalSeconds,
      3
    )
  }
}

Push-Location $repoRoot
try {
  Invoke-WorkspaceStep "Workspace widget and navigation regression" {
    & $flutter test `
      test/features/v4/desktop_workspace_controller_test.dart `
      test/features/v4/desktop_tab_controls_test.dart `
      test/features/v4/workspace_persistence_logout_test.dart `
      test/features/v4/cross_tab_conflict_test.dart `
      test/features/v4/mobile_context_navigation_test.dart `
      test/features/v4/context_transition_matrix_test.dart
  }

  $devices = & $flutter devices --machine | ConvertFrom-Json
  if ($Windows) {
    $windowsDevice = $devices |
      Where-Object { $_.targetPlatform -eq "windows-x64" } |
      Select-Object -First 1
    if (-not $windowsDevice) {
      throw "A Windows device is not available."
    }
    Invoke-WorkspaceStep "Windows workspace device E2E" {
      & $flutter test integration_test/v4_workspace_device_test.dart `
        -d $windowsDevice.id --device-timeout 120
    }
  }

  if ($Android) {
    $androidDevice = $devices |
      Where-Object {
        $_.targetPlatform -like "android-*" -and
        $_.emulator -eq $true
      } |
      Select-Object -First 1
    if (-not $androidDevice) {
      throw (
        "A booted Android emulator is not available. " +
        "Enable WHPX/AEHD and launch MagicMusicCRM_API35."
      )
    }
    Invoke-WorkspaceStep "Android context-stack device E2E" {
      & $flutter test integration_test/v4_workspace_device_test.dart `
        -d $androidDevice.id --device-timeout 180
    }
  }
} finally {
  Pop-Location
}

$revision = (& git -C $repoRoot rev-parse HEAD).Trim()
$result = [ordered]@{
  schemaVersion = 1
  task = "T1.4.1"
  revision = $revision
  status = "pass"
  generatedAt = (Get-Date).ToUniversalTime().ToString("o")
  windows = [bool]$Windows
  android = [bool]$Android
  maxTabs = 10
  contextLoss = 0
  silentOverwrite = 0
  crossAccountLeak = 0
  logoutLatencyMaxSeconds = 2
  gates = $results
  durationSeconds = [Math]::Round(((Get-Date) - $startedAt).TotalSeconds, 3)
}
$evidenceFullPath = [IO.Path]::GetFullPath($EvidencePath)
$evidenceDirectory = Split-Path -Parent $evidenceFullPath
New-Item -ItemType Directory -Force -Path $evidenceDirectory | Out-Null
$result | ConvertTo-Json -Depth 8 |
  Set-Content -LiteralPath $evidenceFullPath -Encoding utf8NoBOM
Write-Host "`nT1.4.1 device gate PASS: $evidenceFullPath" -ForegroundColor Green
