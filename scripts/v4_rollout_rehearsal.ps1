[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("staging")]
  [string]$Target,
  [switch]$Rollback,
  [string]$EvidencePath
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if ($PSVersionTable.PSVersion.Major -lt 7) {
  throw "The v4 rollout rehearsal requires PowerShell 7 or newer."
}
if (-not $Rollback) {
  throw "T8.4.2 rehearsal requires the -Rollback recovery path."
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if (-not $EvidencePath) {
  $EvidencePath = Join-Path $repoRoot "docs/audits/v4-rollout-rehearsal.json"
}
$releaseEvidencePath = Join-Path $repoRoot "docs/audits/v4-release-gate-result.json"
$readinessPath = Join-Path $repoRoot ".anws/v4/08_RELEASE_READINESS_REPORT.md"
if (-not (Test-Path -LiteralPath $releaseEvidencePath)) {
  throw "T8.4.1 release evidence is missing."
}
$releaseEvidence = Get-Content -Raw $releaseEvidencePath | ConvertFrom-Json
if (
  $releaseEvidence.status -notin @("pass", "pass_with_owner_exception") -or
  $releaseEvidence.task -ne "T8.4.1"
) {
  throw "T8.4.1 release evidence is not accepted."
}
if (-not (Test-Path -LiteralPath $readinessPath)) {
  throw "The v4 release readiness report is missing."
}

$toolchainRoot = Join-Path $env:LOCALAPPDATA "MagicMusicCRMToolchain"
$postgresBin = Join-Path $toolchainRoot "postgresql-17/bin"
$env:Path = @("C:\Program Files\nodejs", $postgresBin, $env:Path) -join ";"
$node = if (Test-Path "C:\Program Files\nodejs\node.exe") {
  "C:\Program Files\nodejs\node.exe"
} else { (Get-Command node -ErrorAction Stop).Source }
$npm = if (Test-Path "C:\Program Files\nodejs\npm.cmd") {
  "C:\Program Files\nodejs\npm.cmd"
} else { (Get-Command npm -ErrorAction Stop).Source }
$psql = Join-Path $postgresBin "psql.exe"
if (-not (Test-Path -LiteralPath $psql)) { throw "psql was not found." }

$stagingDatabase = "magiccrm_v4_s6_staging"
if ($releaseEvidence.operations.restoredDatabase -ne $stagingDatabase) {
  throw "Release evidence does not identify the approved staging restore."
}
$stagingUrl = "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/$stagingDatabase"
$originalDatabaseUrl = $env:DATABASE_URL
$originalMigrationDatabaseUrl = $env:MIGRATION_DATABASE_URL
$env:DATABASE_URL = $stagingUrl
$env:MIGRATION_DATABASE_URL = $stagingUrl
$results = @()
$startedAt = Get-Date

function Invoke-RehearsalStep {
  param([string]$Name, [scriptblock]$Command)
  $stepStartedAt = Get-Date
  Write-Host "`n=== $Name ===" -ForegroundColor Cyan
  & $Command
  if ($LASTEXITCODE -ne 0) {
    throw "$Name failed with exit code $LASTEXITCODE."
  }
  $script:results += [ordered]@{
    name = $Name
    status = "pass"
    durationSeconds = [Math]::Round(((Get-Date) - $stepStartedAt).TotalSeconds, 3)
  }
}

function Get-FactSignature {
  $value = (& $psql $stagingUrl -At -c @'
select json_build_object(
  'payments', (select count(*) from app.payments),
  'clientLessonFacts', (select count(*) from app.lesson_client_charge_facts),
  'teacherLessonFacts', (select count(*) from app.lesson_teacher_compensation_facts),
  'obligationFacts', (select count(*) from app.subscription_obligation_facts),
  'lifecycleFacts', (select count(*) from app.subscription_lifecycle_events)
)::text;
'@).Trim()
  if ($LASTEXITCODE -ne 0 -or -not $value) {
    throw "Unable to capture immutable fact signature."
  }
  return $value
}

function Get-RolloutState {
  param([string]$Mode, [bool]$KillSwitch, [int]$Unexplained)
  $kill = if ($KillSwitch) { "true" } else { "false" }
  $script = @"
const f = require('./server/dist/platform/v4-domain-flags.js');
const value = f.resolveV4DomainRollout('access', {
  V4_ACCESS_MODE: '$Mode',
  V4_ACCESS_KILL_SWITCH: '$kill'
}, $Unexplained);
process.stdout.write(JSON.stringify(value));
"@
  $value = (& $node -e $script).Trim()
  if ($LASTEXITCODE -ne 0 -or -not $value) {
    throw "Unable to resolve rollout state for $Mode/$kill."
  }
  return $value | ConvertFrom-Json
}

try {
  Push-Location $repoRoot
  try {
    $latestMigration = (& $psql $stagingUrl -At -c "select id from app_schema_migrations order by applied_at desc limit 1").Trim()
    if ($LASTEXITCODE -ne 0 -or $latestMigration -ne $releaseEvidence.operations.latestMigration) {
      throw "Staging restore is not at the release migration."
    }
    $beforeFacts = Get-FactSignature

    Invoke-RehearsalStep "Staging zero-blocker preflight" {
      & $npm --prefix server run v4:preflight -- --require-zero-blockers
    }

    $shadow = Get-RolloutState -Mode "shadow" -KillSwitch $false -Unexplained 0
    if ($shadow.effectivePath -ne "legacy" -or -not $shadow.shadowCompare) {
      throw "Shadow stage did not preserve the compatibility path."
    }
    $enabled = Get-RolloutState -Mode "v4" -KillSwitch $false -Unexplained 0
    if ($enabled.effectivePath -ne "v4" -or -not $enabled.enableAllowed) {
      throw "The zero-diff v4 stage could not be enabled."
    }
    $blocked = Get-RolloutState -Mode "v4" -KillSwitch $false -Unexplained 1
    if ($blocked.effectivePath -ne "legacy" -or $blocked.enableAllowed) {
      throw "Unexplained parity did not block the v4 stage."
    }

    Invoke-RehearsalStep "Health, auth, realtime and outbox smoke" {
      Push-Location server
      try {
        & $node --experimental-vm-modules node_modules/jest/bin/jest.js `
          --runInBand --runTestsByPath `
          src/health/health.service.spec.ts `
          src/auth/session.service.spec.ts `
          src/auth/auth.service.spec.ts `
          src/realtime/realtime-bus.spec.ts `
          src/messenger/realtime.gateway.spec.ts `
          src/platform/platform-integrity-postgres.integration.spec.ts
      } finally { Pop-Location }
    }

    $rollbackState = Get-RolloutState -Mode "v4" -KillSwitch $true -Unexplained 0
    if ($rollbackState.effectivePath -ne "legacy" -or -not $rollbackState.killSwitch) {
      throw "Kill-switch rollback did not select the compatibility path."
    }
    $forwardState = Get-RolloutState -Mode "v4" -KillSwitch $false -Unexplained 0
    if ($forwardState.effectivePath -ne "v4") {
      throw "Forward recovery did not restore the v4 path."
    }

    $metrics = (& $psql $stagingUrl -At -F '|' -c @'
select
  (select count(*) from app.platform_outbox_events where published_at is null and dead_lettered_at is null),
  (select count(*) from app.platform_outbox_events where dead_lettered_at is not null),
  (select count(*) from app.lesson_completion_work where state = 'poison');
'@).Trim() -split '\|'
    if ($LASTEXITCODE -ne 0 -or $metrics.Count -ne 3) {
      throw "Unable to verify outbox/worker drain state."
    }
    if ([int]$metrics[0] -ne 0 -or [int]$metrics[1] -ne 0 -or [int]$metrics[2] -ne 0) {
      throw "Staging rollback left pending/dead-letter outbox or poison work."
    }
    $afterFacts = Get-FactSignature
    if ($afterFacts -ne $beforeFacts) {
      throw "Rollback/forward rehearsal changed immutable financial facts."
    }

    $result = [ordered]@{
      schemaVersion = 1
      task = "T8.4.2"
      target = $Target
      revision = (& git -C $repoRoot rev-parse HEAD).Trim()
      status = "pass"
      productionApproved = [bool]$releaseEvidence.productionApproved
      releaseGateStatus = $releaseEvidence.status
      generatedAt = (Get-Date).ToUniversalTime().ToString("o")
      maintenance = "documented"
      backupRestoreEvidence = "docs/audits/v4-release-gate-result.json"
      rollout = [ordered]@{
        shadow = $shadow
        enabled = $enabled
        unexplainedDiffBlocked = $blocked
        rollback = $rollbackState
        forwardRecovery = $forwardState
      }
      operations = [ordered]@{
        workerPauseResume = "documented-and-safe"
        pendingOutbox = [int]$metrics[0]
        deadLetterOutbox = [int]$metrics[1]
        poisonWorker = [int]$metrics[2]
        immutableFactsPreserved = $true
        health = "pass"
        auth = "pass"
        realtime = "pass"
      }
      gates = $results
      durationSeconds = [Math]::Round(((Get-Date) - $startedAt).TotalSeconds, 3)
    }
    $evidenceFullPath = [IO.Path]::GetFullPath($EvidencePath)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $evidenceFullPath) | Out-Null
    $result | ConvertTo-Json -Depth 10 |
      Set-Content -LiteralPath $evidenceFullPath -Encoding utf8NoBOM
    Write-Host "`nT8.4.2 rollout rehearsal PASS: $evidenceFullPath" -ForegroundColor Green
  } finally { Pop-Location }
} finally {
  $env:DATABASE_URL = $originalDatabaseUrl
  $env:MIGRATION_DATABASE_URL = $originalMigrationDatabaseUrl
}
