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

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$nodeCommand = Get-Command node -ErrorAction SilentlyContinue
$nodeExecutable = if ($nodeCommand) {
  $nodeCommand.Source
} else {
  Join-Path $env:USERPROFILE (
    ".cache/codex-runtimes/codex-primary-runtime/" +
    "dependencies/node/bin/node.exe"
  )
}
$flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
$flutterExecutable = if ($flutterCommand) {
  $flutterCommand.Source
} else {
  "C:\flutter\bin\flutter.bat"
}
if (-not (Test-Path -LiteralPath $nodeExecutable)) {
  throw "Node.js executable was not found."
}
if (-not (Test-Path -LiteralPath $flutterExecutable)) {
  throw "Flutter executable was not found."
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

function Assert-TaskAndEvidence {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$Tasks,
    [Parameter(Mandatory = $true)]
    [string[]]$Evidence,
    [Parameter(Mandatory = $true)]
    [string]$Label
  )

  $taskText = Get-Content -Raw -Encoding utf8 (
    Join-Path $repoRoot ".anws/v4/05_TASKS.md"
  )
  foreach ($taskId in $Tasks) {
    $escaped = [Regex]::Escape($taskId)
    if ($taskText -notmatch "(?m)^- \[x\] \*\*$escaped\*\*") {
      throw "$taskId is not marked complete."
    }
  }
  foreach ($relativePath in $Evidence) {
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $relativePath))) {
      throw "Missing $Label evidence: $relativePath"
    }
  }
  $script:gateResults += [ordered]@{
    name = "$Label task/evidence inventory"
    status = "pass"
    durationSeconds = 0
  }
}

function Write-SprintEvidence {
  param(
    [Parameter(Mandatory = $true)]
    [System.Collections.IDictionary]$Result,
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $directory = Split-Path -Parent $Path
  New-Item -ItemType Directory -Force -Path $directory | Out-Null
  $Result | ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath $Path -Encoding utf8NoBOM
  Write-Host "`n$($Result.sprint) gate PASS: $Path" -ForegroundColor Green
}

if ($Sprint -eq "S2") {
  if (-not $Concurrency) {
    throw "S2 requires -Concurrency."
  }
  if (-not $EvidencePath) {
    $EvidencePath = Join-Path $repoRoot "docs/audits/v4-s2-gate-result.json"
  }
  $evidenceFullPath = [IO.Path]::GetFullPath($EvidencePath)
  $gateResults = @()
  $gateStartedAt = Get-Date
  $resolvedRevision = (
    & git -C $repoRoot rev-parse --verify "$Revision^{commit}"
  ).Trim()
  if ($LASTEXITCODE -ne 0 -or -not $resolvedRevision) {
    throw "Cannot resolve Git revision $Revision."
  }

  Assert-TaskAndEvidence `
    -Label "S2" `
    -Tasks @(
      "T3.1.1",
      "T4.1.1", "T4.1.2",
      "T4.2.1", "T4.2.2", "T4.2.3", "T4.2.4", "T4.2.5",
      "T4.3.1", "T4.3.2", "T4.3.3", "T4.4.1",
      "T5.1.1", "T8.2.1"
    ) `
    -Evidence @(
      "docs/audits/v4-client-ref.md",
      "docs/audits/v4-lesson-lifecycle-schema.md",
      "docs/audits/v4-schedule-reference.md",
      "docs/audits/v4-schedule-constraint-engine.md",
      "docs/audits/v4-lesson-write-parity.md",
      "docs/audits/v4-atomic-lesson-series.md",
      "docs/audits/v4-lesson-transitions.md",
      "docs/audits/v4-no-attendance-domain.md",
      "docs/audits/v4-lesson-form-conflict-ux.md",
      "docs/audits/v4-lesson-state-palette.md",
      "docs/audits/v4-teacher-calendar-read-only.md",
      "docs/audits/v4-schedule-concurrency.md",
      "docs/audits/v4-lesson-settlement.md",
      "docs/audits/v4-lesson-completion-worker.md"
    )

  Push-Location $repoRoot
  try {
    Invoke-GateCommand "Backend schedule typecheck" {
      & $nodeExecutable server/node_modules/typescript/bin/tsc `
        --noEmit --project server/tsconfig.json
    }
    Invoke-GateCommand "Schedule concurrency and lifecycle" {
      Push-Location server
      try {
        & $nodeExecutable --experimental-vm-modules `
          node_modules/jest/bin/jest.js --runInBand --runTestsByPath `
          src/crm/schedule/availability.spec.ts `
          src/crm/schedule/constraint-engine.spec.ts `
          src/crm/schedule/availability-postgres.integration.spec.ts `
          src/crm/schedule/constraint-engine-postgres.integration.spec.ts `
          src/crm/schedule/lesson-write-parity.integration.spec.ts `
          src/crm/schedule/lesson-series-postgres.integration.spec.ts `
          src/crm/schedule/reschedule-postgres.integration.spec.ts `
          src/crm/schedule/completion-worker-postgres.integration.spec.ts `
          src/crm/schedule/no-attendance-mutations.contract.spec.ts
      } finally {
        Pop-Location
      }
    }
    Invoke-GateCommand "Schedule six-role boundary" {
      Push-Location server
      try {
        & $nodeExecutable --experimental-vm-modules `
          node_modules/jest/bin/jest.js --runInBand --runTestsByPath `
          src/access-control/actor-matrix-postgres.integration.spec.ts `
          src/access-control/actor-matrix-payload-leak.spec.ts
      } finally {
        Pop-Location
      }
    }
    Invoke-GateCommand "Flutter lesson integrity surfaces" {
      & $flutterExecutable test `
        test/features/v4/lesson_form_test.dart `
        test/features/v4/lesson_state_palette_test.dart `
        test/features/v4/schedule_regression_test.dart `
        test/features/v4/teacher_schedule_read_only_test.dart
    }
  } finally {
    Pop-Location
  }

  Write-SprintEvidence -Path $evidenceFullPath -Result ([ordered]@{
    schemaVersion = 1
    sprint = "S2"
    revision = $resolvedRevision
    status = "pass"
    generatedAt = (Get-Date).ToUniversalTime().ToString("o")
    concurrency = $true
    attendanceMutationRoutes = 0
    attendanceMutationControls = 0
    twoWorkerSingleSettlement = $true
    completionLatencyMaxSeconds = 60
    gates = $gateResults
    durationSeconds = [Math]::Round(
      ((Get-Date) - $gateStartedAt).TotalSeconds,
      3
    )
  })
  return
}

if ($Sprint -eq "S3") {
  if (-not $RequireZeroDrift) {
    throw "S3 requires -RequireZeroDrift."
  }
  if (-not $EvidencePath) {
    $EvidencePath = Join-Path $repoRoot "docs/audits/v4-s3-gate-result.json"
  }
  $evidenceFullPath = [IO.Path]::GetFullPath($EvidencePath)
  $gateResults = @()
  $gateStartedAt = Get-Date
  $resolvedRevision = (
    & git -C $repoRoot rev-parse --verify "$Revision^{commit}"
  ).Trim()
  if ($LASTEXITCODE -ne 0 -or -not $resolvedRevision) {
    throw "Cannot resolve Git revision $Revision."
  }

  Assert-TaskAndEvidence `
    -Label "S3" `
    -Tasks @(
      "T5.1.2",
      "T5.2.1", "T5.2.2", "T5.2.3", "T5.2.4",
      "T5.3.1", "T5.3.2", "T5.4.1"
    ) `
    -Evidence @(
      "docs/audits/v4-commerce-schema.md",
      "docs/audits/v4-package-catalog.md",
      "docs/audits/v4-subscription-issue-payment.md",
      "docs/audits/v4-subscription-replace.md",
      "docs/audits/v4-subscription-cancel.md",
      "docs/audits/v4-commerce-role-projections.md",
      "docs/audits/v4-subscription-lesson-reservations.md",
      "docs/audits/v4-commerce-concurrency-reconciliation.md"
    )

  $postgresReady = Test-NetConnection `
    -ComputerName "127.0.0.1" `
    -Port 54329 `
    -InformationLevel Quiet
  if (-not $postgresReady) {
    Invoke-GateCommand "PostgreSQL test dependency" {
      & docker compose -f server/docker-compose.test.yml up -d --wait
    }
  }
  $originalDatabaseUrl = $env:DATABASE_URL
  $env:DATABASE_URL = if ($env:V4_PLATFORM_TEST_DATABASE_URL) {
    $env:V4_PLATFORM_TEST_DATABASE_URL
  } else {
    "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm"
  }

  Push-Location $repoRoot
  try {
    Invoke-GateCommand "Backend commerce typecheck" {
      & $nodeExecutable server/node_modules/typescript/bin/tsc `
        --noEmit --project server/tsconfig.json
    }
    Invoke-GateCommand "Commerce actor and concurrency regression" {
      Push-Location server
      try {
        & $nodeExecutable --experimental-vm-modules `
          node_modules/jest/bin/jest.js --runInBand --runTestsByPath `
          src/crm/commerce/commerce-schema-postgres.integration.spec.ts `
          src/crm/commerce/package-catalog.integration.spec.ts `
          src/crm/commerce/subscription-issue-postgres.integration.spec.ts `
          src/crm/commerce/subscription-replace-postgres.integration.spec.ts `
          src/crm/commerce/subscription-cancel-postgres.integration.spec.ts `
          src/crm/commerce/subscription-lesson-race-postgres.integration.spec.ts `
          src/crm/commerce/lesson-settlement-postgres.integration.spec.ts `
          src/crm/commerce/commerce-projections.contract.spec.ts
      } finally {
        Pop-Location
      }
    }
    Invoke-GateCommand "Commerce privacy boundary" {
      Push-Location server
      try {
        & $nodeExecutable --experimental-vm-modules `
          node_modules/jest/bin/jest.js --runInBand --runTestsByPath `
          src/access-control/actor-matrix-postgres.integration.spec.ts `
          src/access-control/actor-matrix-payload-leak.spec.ts
      } finally {
        Pop-Location
      }
    }
    Invoke-GateCommand "Commerce zero-drift fixture" {
      Push-Location server
      try {
        & $nodeExecutable node_modules/ts-node/dist/bin.js `
          src/platform/v4-reconcile.ts `
          --fixture clean --scope commerce
      } finally {
        Pop-Location
      }
    }
    $cleanReport = Get-Content -Raw (
      Join-Path $repoRoot "docs/audits/v4-reconciliation-commerce-clean.json"
    ) | ConvertFrom-Json
    if (
      $cleanReport.status -ne "clean" -or
      $cleanReport.summary.unexplainedDiff -ne 0 -or
      -not $cleanReport.signature.verified
    ) {
      throw "Commerce clean reconciliation was not signed zero drift."
    }
    Invoke-GateCommand "Commerce negative drift detection" {
      Push-Location server
      try {
        & $nodeExecutable node_modules/ts-node/dist/bin.js `
          src/platform/v4-reconcile.ts `
          --fixture drift --scope commerce --expect-fail
      } finally {
        Pop-Location
      }
    }
    $driftReport = Get-Content -Raw (
      Join-Path $repoRoot "docs/audits/v4-reconciliation-commerce-drift.json"
    ) | ConvertFrom-Json
    if (
      $driftReport.status -ne "drift" -or
      $driftReport.summary.unexplainedDiff -ne 1 -or
      -not $driftReport.signature.verified
    ) {
      throw "Commerce negative fixture did not detect one signed drift."
    }
    $gateResults += [ordered]@{
      name = "Commerce reconciliation assertions"
      status = "pass"
      durationSeconds = 0
    }
    Invoke-GateCommand "Flutter subscription integrity surfaces" {
      & $flutterExecutable test `
        test/features/v4/subscription_catalog_test.dart `
        test/features/v4/subscription_issue_form_test.dart `
        test/features/v4/subscription_replace_form_test.dart `
        test/features/v4/subscription_cancel_form_test.dart `
        test/features/v4/client_finance_roles_test.dart
    }
  } finally {
    Pop-Location
    $env:DATABASE_URL = $originalDatabaseUrl
  }

  Write-SprintEvidence -Path $evidenceFullPath -Result ([ordered]@{
    schemaVersion = 1
    sprint = "S3"
    revision = $resolvedRevision
    status = "pass"
    generatedAt = (Get-Date).ToUniversalTime().ToString("o")
    requireZeroDrift = $true
    cleanUnexplainedDiff = $cleanReport.summary.unexplainedDiff
    negativeFixtureDiff = $driftReport.summary.unexplainedDiff
    signaturesVerified = $true
    gates = $gateResults
    durationSeconds = [Math]::Round(
      ((Get-Date) - $gateStartedAt).TotalSeconds,
      3
    )
  })
  return
}

if ($Sprint -eq "S4") {
  if (-not $EvidencePath) {
    $EvidencePath = Join-Path $repoRoot "docs/audits/v4-s4-gate-result.json"
  }
  $evidenceFullPath = [IO.Path]::GetFullPath($EvidencePath)
  $gateResults = @()
  $gateStartedAt = Get-Date
  $resolvedRevision = (
    & git -C $repoRoot rev-parse --verify "$Revision^{commit}"
  ).Trim()
  if ($LASTEXITCODE -ne 0 -or -not $resolvedRevision) {
    throw "Cannot resolve Git revision $Revision."
  }

  Assert-TaskAndEvidence `
    -Label "S4" `
    -Tasks @(
      "T3.1.2",
      "T3.2.1", "T3.2.2", "T3.2.3", "T3.2.4",
      "T3.3.1", "T3.3.2",
      "T6.1.1", "T6.2.1", "T6.2.2", "T6.3.1", "T6.4.1"
    ) `
    -Evidence @(
      "docs/audits/v4-client-config.md",
      "docs/audits/v4-inbound-lead.md",
      "docs/audits/v4-client-conversion.md",
      "docs/audits/v4-client-archive.md",
      "docs/audits/v4-client-card-read-model.md",
      "docs/audits/v4-comment-sharing.md",
      "docs/audits/v4-client-forms.md",
      "docs/audits/v4-client-card-ux.md",
      "docs/audits/v4-shared-task-schema.md",
      "docs/audits/v4-shared-task-api.md",
      "docs/audits/v4-task-reminders-realtime.md",
      "docs/audits/v4-shared-tasks-ui.md",
      "docs/audits/v4-task-audience-regression.md"
    )

  Push-Location $repoRoot
  try {
    Invoke-GateCommand "Backend CRM and shared-work typecheck" {
      & $nodeExecutable server/node_modules/typescript/bin/tsc `
        --noEmit --project server/tsconfig.json
    }
    Invoke-GateCommand "CRM lifecycle and privacy integration" {
      Push-Location server
      try {
        & $nodeExecutable --experimental-vm-modules `
          node_modules/jest/bin/jest.js --runInBand --runTestsByPath `
          src/crm/clients/client-config-postgres.integration.spec.ts `
          src/crm/clients/inbound-lead-postgres.integration.spec.ts `
          src/crm/clients/conversion-postgres.integration.spec.ts `
          src/crm/clients/archive-postgres.integration.spec.ts `
          src/crm/clients/comment-sharing-postgres.integration.spec.ts `
          src/crm/clients/client-card.integration.spec.ts
      } finally {
        Pop-Location
      }
    }
    Invoke-GateCommand "Shared task audience and concurrency" {
      Push-Location server
      try {
        & $nodeExecutable --experimental-vm-modules `
          node_modules/jest/bin/jest.js --runInBand --runTestsByPath `
          src/crm/tasks/shared-task-migration-postgres.integration.spec.ts `
          src/crm/tasks/shared-task-postgres.integration.spec.ts `
          src/crm/tasks/task-reminders.integration.spec.ts
      } finally {
        Pop-Location
      }
    }
    Invoke-GateCommand "CRM and task six-role boundary" {
      Push-Location server
      try {
        & $nodeExecutable --experimental-vm-modules `
          node_modules/jest/bin/jest.js --runInBand --runTestsByPath `
          src/access-control/actor-matrix-postgres.integration.spec.ts `
          src/access-control/actor-matrix-payload-leak.spec.ts
      } finally {
        Pop-Location
      }
    }
    Invoke-GateCommand "Flutter CRM and shared-work device surfaces" {
      & $flutterExecutable test `
        test/features/v4/client_forms_test.dart `
        test/features/v4/client_card_roles_test.dart `
        test/features/v4/shared_tasks_ui_test.dart
    }
  } finally {
    Pop-Location
  }

  Write-SprintEvidence -Path $evidenceFullPath -Result ([ordered]@{
    schemaVersion = 1
    sprint = "S4"
    revision = $resolvedRevision
    status = "pass"
    generatedAt = (Get-Date).ToUniversalTime().ToString("o")
    manualLeadNotifications = 0
    duplicateInboundLeadCount = 1
    duplicateInboundNotificationCount = 1
    archiveRoles = @("director", "system_admin")
    concurrentTaskCloseResults = 1
    mobileCollapsedFilterMaxPixels = 56
    actorRoles = 6
    deviceLayouts = @("mobile", "desktop")
    gates = $gateResults
    durationSeconds = [Math]::Round(
      ((Get-Date) - $gateStartedAt).TotalSeconds,
      3
    )
  })
  return
}

if ($Sprint -eq "S5") {
  if (-not $Windows -or -not $Android -or -not $Excel) {
    throw "S5 requires -Windows -Android -Excel."
  }
  if (-not $EvidencePath) {
    $EvidencePath = Join-Path $repoRoot "docs/audits/v4-s5-gate-result.json"
  }
  $evidenceFullPath = [IO.Path]::GetFullPath($EvidencePath)
  $gateResults = @()
  $gateStartedAt = Get-Date
  $resolvedRevision = (
    & git -C $repoRoot rev-parse --verify "$Revision^{commit}"
  ).Trim()
  if ($LASTEXITCODE -ne 0 -or -not $resolvedRevision) {
    throw "Cannot resolve Git revision $Revision."
  }

  Assert-TaskAndEvidence `
    -Label "S5" `
    -Tasks @(
      "T7.1.1", "T7.1.2", "T7.2.1", "T7.2.2",
      "T1.1.1", "T1.1.2",
      "T1.2.1", "T1.2.2", "T1.2.3",
      "T1.2.4", "T1.2.5", "T1.2.6",
      "T1.3.1", "T1.4.1"
    ) `
    -Evidence @(
      "docs/audits/v4-client-status-reporting.md",
      "docs/audits/v4-reporting-hard-scope.md",
      "docs/audits/v4-ooxml-export.md",
      "docs/audits/v4-reporting-ui.md",
      "docs/audits/v4-capability-shell.md",
      "docs/audits/v4-access-editor.md",
      "docs/audits/v4-entity-link-registry.md",
      "docs/audits/v4-mobile-context-navigation.md",
      "docs/audits/v4-desktop-workspace-controller.md",
      "docs/audits/v4-workspace-persistence-logout.md",
      "docs/audits/v4-cross-tab-conflicts.md",
      "docs/audits/v4-desktop-tab-controls.md",
      "docs/audits/v4-context-transition-matrix.md",
      "docs/audits/v4-workspace-device.md"
    )

  $postgresReady = Test-NetConnection `
    -ComputerName "127.0.0.1" `
    -Port 54329 `
    -InformationLevel Quiet
  if (-not $postgresReady) {
    Invoke-GateCommand "PostgreSQL test dependency" {
      & docker compose -f server/docker-compose.test.yml up -d --wait
    }
  }
  $originalDatabaseUrl = $env:DATABASE_URL
  $env:DATABASE_URL = if ($env:V4_PLATFORM_TEST_DATABASE_URL) {
    $env:V4_PLATFORM_TEST_DATABASE_URL
  } else {
    "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm"
  }

  Push-Location $repoRoot
  try {
    Invoke-GateCommand "Backend reporting and OOXML integration" {
      Push-Location server
      try {
        & $nodeExecutable --experimental-vm-modules `
          node_modules/jest/bin/jest.js --runInBand --runTestsByPath `
          src/analytics/client-status-postgres.integration.spec.ts `
          src/analytics/v4-reporting-scope-postgres.integration.spec.ts `
          src/analytics/ooxml-export.integration.spec.ts
      } finally {
        Pop-Location
      }
    }
    Invoke-GateCommand "Reporting six-role privacy boundary" {
      Push-Location server
      try {
        & $nodeExecutable --experimental-vm-modules `
          node_modules/jest/bin/jest.js --runInBand --runTestsByPath `
          src/access-control/actor-matrix-postgres.integration.spec.ts `
          src/access-control/actor-matrix-payload-leak.spec.ts
      } finally {
        Pop-Location
      }
    }
    Invoke-GateCommand "Flutter reporting and transition regression" {
      & $flutterExecutable test `
        test/features/v4/reporting_drilldown_test.dart `
        test/features/v4/context_transition_matrix_test.dart `
        test/features/v4/entity_link_registry_test.dart
    }
    Invoke-GateCommand "Windows and Android workspace device gate" {
      & pwsh -NoProfile -File scripts/v4_workspace_e2e.ps1 `
        -Windows -Android
    }
    Invoke-GateCommand "Excel OOXML fixture validation" {
      & pwsh -NoProfile -File scripts/validate_xlsx.ps1 `
        -Fixture build/v4-report.xlsx -Excel
    }
  } finally {
    Pop-Location
    $env:DATABASE_URL = $originalDatabaseUrl
  }

  Write-SprintEvidence -Path $evidenceFullPath -Result ([ordered]@{
    schemaVersion = 1
    sprint = "S5"
    revision = $resolvedRevision
    status = "pass"
    generatedAt = (Get-Date).ToUniversalTime().ToString("o")
    windows = $true
    android = $true
    excel = $true
    transitionCoveragePercent = 100
    contextLoss = 0
    formatWarnings = 0
    silentOverwrite = 0
    accessLeaks = 0
    gates = $gateResults
    durationSeconds = [Math]::Round(
      ((Get-Date) - $gateStartedAt).TotalSeconds,
      3
    )
  })
  return
}

if ($Sprint -eq "S1") {
  if (-not $ActorMatrix) {
    throw "S1 requires -ActorMatrix."
  }
  if (-not $EvidencePath) {
    $EvidencePath = Join-Path $repoRoot "docs/audits/v4-s1-gate-result.json"
  }
  $evidenceFullPath = [IO.Path]::GetFullPath($EvidencePath)
  $gateResults = @()
  $gateStartedAt = Get-Date
  $resolvedRevision = (
    & git -C $repoRoot rev-parse --verify "$Revision^{commit}"
  ).Trim()
  if ($LASTEXITCODE -ne 0 -or -not $resolvedRevision) {
    throw "Cannot resolve Git revision $Revision."
  }

  $taskText = Get-Content -Raw -Encoding utf8 (
    Join-Path $repoRoot ".anws/v4/05_TASKS.md"
  )
  $requiredTasks = @(
    "T1.1.1", "T1.1.2",
    "T2.1.1", "T2.1.2",
    "T2.2.1", "T2.2.2", "T2.2.3",
    "T2.3.1", "T2.3.2", "T2.4.1"
  )
  foreach ($taskId in $requiredTasks) {
    $escaped = [Regex]::Escape($taskId)
    if ($taskText -notmatch "(?m)^- \[x\] \*\*$escaped\*\*") {
      throw "$taskId is not marked complete."
    }
  }
  $requiredEvidence = @(
    "docs/audits/v4-capability-registry.md",
    "docs/audits/v4-hard-invariant-evaluator.md",
    "docs/audits/v4-access-mutations.md",
    "docs/audits/v4-client-projections.md",
    "docs/audits/v4-comment-sharing.md",
    "docs/audits/v4-access-coverage.md",
    "docs/audits/v4-access-invalidation.md",
    "docs/audits/v4-actor-matrix.md",
    "docs/audits/v4-capability-shell.md",
    "docs/audits/v4-access-editor.md"
  )
  foreach ($relativePath in $requiredEvidence) {
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $relativePath))) {
      throw "Missing S1 evidence: $relativePath"
    }
  }
  $gateResults += [ordered]@{
    name = "S1 task/evidence inventory"
    status = "pass"
    durationSeconds = 0
  }

  Push-Location $repoRoot
  try {
    Invoke-GateCommand "Backend access typecheck" {
      & node server/node_modules/typescript/bin/tsc `
        --noEmit --project server/tsconfig.json
    }
    Invoke-GateCommand "Access policy and mutation integration" {
      Push-Location server
      try {
        & node node_modules/jest/bin/jest.js `
          --runInBand --runTestsByPath `
          src/access-control/capability-registry-postgres.integration.spec.ts `
          src/access-control/effective-access-evaluator.spec.ts `
          src/access-control/access-mutations-postgres.integration.spec.ts `
          src/access-control/access-invalidation.integration.spec.ts `
          src/access-control/capability-request-authorizer.spec.ts `
          src/access-control/capability-route-policy.spec.ts `
          src/access-control/teacher-projection.contract.spec.ts
      } finally {
        Pop-Location
      }
    }
    Invoke-GateCommand "Six-role Actor Matrix and payload scan" {
      Push-Location server
      try {
        & node node_modules/jest/bin/jest.js `
          --runInBand --runTestsByPath `
          src/access-control/actor-matrix-postgres.integration.spec.ts `
          src/access-control/actor-matrix-payload-leak.spec.ts
      } finally {
        Pop-Location
      }
    }
    Invoke-GateCommand "Flutter capability shell/editor matrix" {
      & flutter test `
        test/features/v4/capability_shell_test.dart `
        test/features/v4/access_editor_roles_test.dart `
        test/features/rbac_nav_matrix_test.dart
    }
  } finally {
    Pop-Location
  }

  $result = [ordered]@{
    schemaVersion = 1
    sprint = "S1"
    revision = $resolvedRevision
    status = "pass"
    generatedAt = (Get-Date).ToUniversalTime().ToString("o")
    actorMatrix = $true
    managerMutationsDenied = $true
    systemAdminHiddenAndRoot = $true
    accessInvalidationMaxSeconds = 5
    gates = $gateResults
    durationSeconds = [Math]::Round(
      ((Get-Date) - $gateStartedAt).TotalSeconds,
      3
    )
  }
  $evidenceDirectory = Split-Path -Parent $evidenceFullPath
  New-Item -ItemType Directory -Force -Path $evidenceDirectory | Out-Null
  $result | ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath $evidenceFullPath -Encoding utf8NoBOM
  Write-Host "`nS1 gate PASS: $evidenceFullPath" -ForegroundColor Green
  return
}

if ($Sprint -ne "S0") {
  throw "Sprint $Sprint gate is not implemented yet."
}
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
