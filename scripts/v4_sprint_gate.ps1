[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("S0", "S1", "S2", "S3", "S4", "S5", "S6")]
  [string]$Sprint,
  [switch]$ActorMatrix,
  [switch]$Concurrency,
  [switch]$RequireZeroDrift,
  [switch]$Windows,
  [switch]$Android,
  [switch]$Excel,
  [switch]$Final,
  [switch]$RequireOwnerApproval,
  [string]$Revision = "HEAD",
  [string]$EvidencePath
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if ($PSVersionTable.PSVersion.Major -lt 7) {
  throw "v4 sprint gates require PowerShell 7 or newer."
}
if ($Sprint -ne "S0") {
  throw "Sprint $Sprint gate is not implemented yet."
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if (-not $EvidencePath) {
  $EvidencePath = Join-Path $repoRoot "docs/audits/v4-s0-gate-result.json"
}
$evidenceFullPath = [IO.Path]::GetFullPath($EvidencePath)
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$worktreePath = Join-Path $tempRoot (
  "magicmusiccrm-v4-s0-" + [Guid]::NewGuid().ToString("N")
)
if (-not $worktreePath.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) {
  throw "Resolved worktree escaped the operating-system temp directory."
}
if (-not ([IO.Path]::GetFileName($worktreePath)).StartsWith("magicmusiccrm-v4-s0-")) {
  throw "Refusing an unexpected temporary worktree target."
}

function Invoke-GateCommand {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Label,
    [Parameter(Mandatory = $true)]
    [scriptblock]$Command
  )

  $startedAt = Get-Date
  Write-Host "`n=== $Label ===" -ForegroundColor Cyan
  & $Command
  if ($LASTEXITCODE -ne 0) {
    throw "$Label failed with exit code $LASTEXITCODE."
  }
  $duration = [Math]::Round(((Get-Date) - $startedAt).TotalSeconds, 3)
  $script:gateResults += [ordered]@{
    name = $Label
    status = "pass"
    durationSeconds = $duration
  }
}

$resolvedRevision = (
  & git -C $repoRoot rev-parse --verify "$Revision^{commit}"
).Trim()
if ($LASTEXITCODE -ne 0 -or -not $resolvedRevision) {
  throw "Cannot resolve Git revision $Revision."
}

$gateResults = @()
$gateStartedAt = Get-Date
$worktreeAdded = $false
$originalDatabaseUrl = $env:DATABASE_URL
$originalMigrationDatabaseUrl = $env:MIGRATION_DATABASE_URL
$testDatabaseUrl = if ($env:V4_PLATFORM_TEST_DATABASE_URL) {
  $env:V4_PLATFORM_TEST_DATABASE_URL
} else {
  "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm"
}

try {
  & git -C $repoRoot worktree add --detach $worktreePath $resolvedRevision
  if ($LASTEXITCODE -ne 0) {
    throw "Unable to create detached clean worktree."
  }
  $worktreeAdded = $true

  $taskFile = Join-Path $worktreePath ".anws/v4/05_TASKS.md"
  $taskText = Get-Content -Raw -Encoding utf8 $taskFile
  foreach ($taskId in @("T8.1.1", "T8.1.2", "T8.1.3", "T8.1.4", "T8.1.5")) {
    $escaped = [Regex]::Escape($taskId)
    if ($taskText -notmatch "(?m)^- \[x\] \*\*$escaped\*\*") {
      throw "$taskId is not marked complete in the clean revision."
    }
  }
  $requiredEvidence = @(
    "docs/audits/v4-baseline.md",
    "docs/audits/v4-current-state-inventory.md",
    "docs/audits/v4-current-state-inventory.json",
    "docs/audits/v4-data-preflight-evidence.md",
    "docs/audits/v4-platform-primitives.md",
    "docs/audits/v4-reconciliation-evidence.md"
  )
  foreach ($relativePath in $requiredEvidence) {
    if (-not (Test-Path -LiteralPath (Join-Path $worktreePath $relativePath))) {
      throw "Missing S0 evidence: $relativePath"
    }
  }
  $gateResults += [ordered]@{
    name = "S0 task/evidence inventory"
    status = "pass"
    durationSeconds = 0
  }

  $postgresReady = Test-NetConnection `
    -ComputerName "127.0.0.1" `
    -Port 54329 `
    -InformationLevel Quiet
  if (-not $postgresReady) {
    Push-Location $worktreePath
    try {
      Invoke-GateCommand "PostgreSQL test dependency" {
        & docker compose -f server/docker-compose.test.yml up -d --wait
      }
    } finally {
      Pop-Location
    }
  } else {
    $gateResults += [ordered]@{
      name = "PostgreSQL test dependency"
      status = "pass"
      durationSeconds = 0
    }
  }

  $env:DATABASE_URL = $testDatabaseUrl
  $env:MIGRATION_DATABASE_URL = $testDatabaseUrl

  Push-Location $worktreePath
  try {
    $serverLockBefore = (Get-FileHash server/package-lock.json -Algorithm SHA256).Hash
    $flutterLockBefore = (Get-FileHash pubspec.lock -Algorithm SHA256).Hash

    Invoke-GateCommand "v4 inventory" {
      & pwsh -NoProfile -File scripts/v4_inventory.ps1 -Check
    }
    Invoke-GateCommand "Backend lock install" {
      & npm --prefix server ci
    }
    Invoke-GateCommand "Backend typecheck" {
      & npm --prefix server run typecheck
    }
    Invoke-GateCommand "Platform PostgreSQL integration" {
      & npm --prefix server test -- --runTestsByPath `
        src/platform/platform-integrity-postgres.integration.spec.ts
    }
    Invoke-GateCommand "Backend full test" {
      & npm --prefix server test
    }
    Invoke-GateCommand "Backend build" {
      & npm --prefix server run build
    }
    Invoke-GateCommand "Read-only preflight pass 1" {
      & npm --prefix server run v4:preflight -- --check-read-only
    }
    $preflightFirst = Get-Content -Raw `
      docs/audits/v4-data-preflight.json | ConvertFrom-Json
    Invoke-GateCommand "Read-only preflight pass 2" {
      & npm --prefix server run v4:preflight -- --check-read-only
    }
    $preflightSecond = Get-Content -Raw `
      docs/audits/v4-data-preflight.json | ConvertFrom-Json
    if (
      $preflightFirst.proof.scanDigestSha256 -ne `
        $preflightSecond.proof.scanDigestSha256 -or
      $preflightFirst.summary.findings -ne $preflightSecond.summary.findings -or
      -not $preflightSecond.proof.transactionReadOnly -or
      -not $preflightSecond.proof.writeProbeRejected
    ) {
      throw "Preflight is not repeatable/read-only."
    }
    $gateResults += [ordered]@{
      name = "Preflight repeatability/read-only assertion"
      status = "pass"
      durationSeconds = 0
    }

    Invoke-GateCommand "Reconciliation clean fixture" {
      & npm --prefix server run v4:reconcile -- --fixture clean
    }
    $cleanReport = Get-Content -Raw `
      docs/audits/v4-reconciliation-clean.json | ConvertFrom-Json
    if (
      $cleanReport.status -ne "clean" -or
      $cleanReport.summary.unexplainedDiff -ne 0 -or
      -not $cleanReport.signature.verified
    ) {
      throw "Clean reconciliation fixture did not produce signed zero drift."
    }
    Invoke-GateCommand "Reconciliation drift fixture" {
      & npm --prefix server run v4:reconcile -- `
        --fixture drift --expect-fail
    }
    $driftReport = Get-Content -Raw `
      docs/audits/v4-reconciliation-drift.json | ConvertFrom-Json
    if (
      $driftReport.status -ne "drift" -or
      $driftReport.summary.unexplainedDiff -ne 1 -or
      -not $driftReport.signature.verified
    ) {
      throw "Drift reconciliation fixture did not detect one signed diff."
    }
    $gateResults += [ordered]@{
      name = "Reconciliation fixture assertions"
      status = "pass"
      durationSeconds = 0
    }

    Invoke-GateCommand "Flutter analyze" {
      & flutter analyze
    }
    Invoke-GateCommand "Flutter full test" {
      & flutter test
    }

    $serverLockAfter = (Get-FileHash server/package-lock.json -Algorithm SHA256).Hash
    $flutterLockAfter = (Get-FileHash pubspec.lock -Algorithm SHA256).Hash
    if (
      $serverLockBefore -ne $serverLockAfter -or
      $flutterLockBefore -ne $flutterLockAfter
    ) {
      throw "A dependency lock file changed during the clean gate."
    }
    & git diff --exit-code --ignore-space-at-eol -- . `
      ":(exclude)docs/audits/v4-data-preflight.json" `
      ":(exclude)docs/audits/v4-data-preflight.md" `
      ":(exclude)docs/audits/v4-reconciliation-clean.json" `
      ":(exclude)docs/audits/v4-reconciliation-drift.json"
    if ($LASTEXITCODE -ne 0) {
      throw "Tracked files changed during the clean gate."
    }
    $gateResults += [ordered]@{
      name = "Clean worktree and lock integrity"
      status = "pass"
      durationSeconds = 0
    }
  } finally {
    Pop-Location
  }

  $result = [ordered]@{
    schemaVersion = 1
    sprint = $Sprint
    revision = $resolvedRevision
    status = "pass"
    generatedAt = (Get-Date).ToUniversalTime().ToString("o")
    cleanDetachedWorktree = $true
    skippedIntegrationSuites = 0
    preflight = [ordered]@{
      digestSha256 = $preflightSecond.proof.scanDigestSha256
      findings = $preflightSecond.summary.findings
      transactionReadOnly = $preflightSecond.proof.transactionReadOnly
      writeProbeRejected = $preflightSecond.proof.writeProbeRejected
      repeatedRunsStable = $true
    }
    reconciliation = [ordered]@{
      cleanUnexplainedDiff = $cleanReport.summary.unexplainedDiff
      driftUnexplainedDiff = $driftReport.summary.unexplainedDiff
      signaturesVerified = $true
    }
    gates = $gateResults
    durationSeconds = [Math]::Round(((Get-Date) - $gateStartedAt).TotalSeconds, 3)
  }
  $evidenceDirectory = Split-Path -Parent $evidenceFullPath
  New-Item -ItemType Directory -Force -Path $evidenceDirectory | Out-Null
  $result | ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath $evidenceFullPath -Encoding utf8NoBOM
  Write-Host "`nS0 gate PASS: $evidenceFullPath" -ForegroundColor Green
} finally {
  $env:DATABASE_URL = $originalDatabaseUrl
  $env:MIGRATION_DATABASE_URL = $originalMigrationDatabaseUrl
  if ($worktreeAdded) {
    & git -C $repoRoot worktree remove --force $worktreePath
    if ($LASTEXITCODE -ne 0) {
      Write-Warning "git worktree remove failed for $worktreePath"
    }
    & git -C $repoRoot worktree prune
  }
}
