[CmdletBinding()]
param(
  [string] $RawPath = (Join-Path $PSScriptRoot "tier1-health-raw.json"),
  [string] $CoveragePath = (Join-Path $PSScriptRoot "tier1-coverage-status.json"),
  [string] $CompactPath = (Join-Path $PSScriptRoot "tier1-health.json"),
  [ValidateSet("Write", "Verify")]
  [string] $Mode = "Verify"
)

$ErrorActionPreference = "Stop"

$expectedCoverageSha = "e86b1f555da5892d66e9d850f1bccb203af57949"
$campaignBaseline = "9cb1f506a5c5418650926fe53b81fe2667ba9bd7"
$staleCoverageImpact = 1.56

$targets = @(
  "server/src/messenger/messenger.service.ts",
  "server/src/messenger/messenger-chat-access.service.ts",
  "server/src/messenger/messenger-system-chat.service.ts",
  "server/src/messenger/messenger-chat-query.service.ts",
  "server/src/messenger/messenger-chat-command.service.ts",
  "server/src/messenger/messenger-message-delivery.service.ts",
  "server/src/crm/payroll.service.ts",
  "server/src/crm/payroll/payroll-accrual-calculator.ts",
  "server/src/crm/payroll/payroll-read.repository.ts",
  "server/src/crm/payroll/teacher-payroll-query.service.ts",
  "server/src/crm/payroll/teacher-payroll-command.service.ts",
  "server/src/crm/payroll/teacher-stats-report.service.ts",
  "server/src/crm/payroll/teacher-stats-csv.service.ts",
  "server/src/crm/commerce/subscription-issue.service.ts",
  "server/src/crm/commerce/subscription-commercial-terms.service.ts",
  "server/src/crm/commerce/subscription-purchase-preview.service.ts",
  "server/src/crm/commerce/subscription-purchase-command.service.ts",
  "server/src/crm/commerce/subscription-grant-command.service.ts",
  "server/src/crm/commerce/subscription-issue-result.service.ts"
)

$facades = @(
  "server/src/messenger/messenger.service.ts",
  "server/src/crm/payroll.service.ts",
  "server/src/crm/commerce/subscription-issue.service.ts"
)

$coverageAdjustedTargets = @(
  "server/src/messenger/messenger-chat-query.service.ts",
  "server/src/crm/payroll/teacher-payroll-command.service.ts",
  "server/src/crm/commerce/subscription-purchase-preview.service.ts",
  "server/src/crm/commerce/subscription-purchase-command.service.ts"
)

function Get-ArtifactPath {
  param([Parameter(Mandatory)] [System.IO.FileInfo] $Item)

  return [System.IO.Path]::GetRelativePath((Get-Location).Path, $Item.FullName).Replace("\", "/")
}

$rawItem = Get-Item -LiteralPath $RawPath
$coverageItem = Get-Item -LiteralPath $CoveragePath
$raw = Get-Content -Raw -LiteralPath $rawItem.FullName | ConvertFrom-Json
$coverage = Get-Content -Raw -LiteralPath $coverageItem.FullName | ConvertFrom-Json

if (-not $coverage.indexed -or $coverage.coverage.source_format -ne "lcov") {
  throw "Coverage provenance must be an indexed LCOV snapshot"
}
if ($coverage.coverage.ingested_commit_sha -ne $expectedCoverageSha) {
  throw "Coverage SHA does not match the approved stale snapshot: expected $expectedCoverageSha, got $($coverage.coverage.ingested_commit_sha)"
}

$targetRows = foreach ($target in $targets) {
  $metricMatches = @($raw.metrics | Where-Object { $_.file_path -eq $target })
  if ($metricMatches.Count -ne 1) {
    throw "Expected exactly one metric row for $target; got $($metricMatches.Count)"
  }

  $metric = $metricMatches[0]
  $findings = @($raw.findings | Where-Object { $_.file_path -eq $target })
  $godOrBrain = @($findings | Where-Object {
      $_.biomarker_type -in @("god_class", "brain_method")
    })
  if ($godOrBrain.Count -ne 0) {
    throw "Forbidden god/brain finding for $target"
  }
  if ([int]$metric.max_ccn -gt 10) {
    throw "Max CCN exceeds 10 for ${target}: $($metric.max_ccn)"
  }

  $rawScore = [math]::Round([double]$metric.score, 2)
  $weightedDeficit = [math]::Round([math]::Max(0.0, 8.0 - $rawScore) * [math]::Max(1, [int]$metric.nloc))
  $row = [ordered]@{
    file_path = $target
    raw_score = $rawScore
    nloc = [int]$metric.nloc
    max_ccn = [int]$metric.max_ccn
    weighted_deficit = $weightedDeficit
    findings = @($findings | ForEach-Object {
        [ordered]@{
          biomarker_type = $_.biomarker_type
          severity = [string]$_.severity
          health_impact = [double]$_.health_impact
          function_name = $_.function_name
          reason = $_.reason
        }
      })
  }

  if ($target -in $coverageAdjustedTargets) {
    $eligibleFindings = @($findings | Where-Object {
        $_.biomarker_type -eq "untested_hotspot" -and
        [double]$_.health_impact -eq $staleCoverageImpact
      })
    if ($eligibleFindings.Count -ne 1) {
      throw "Expected exactly one untested_hotspot impact 1.56 for $target; got $($eligibleFindings.Count)"
    }
    $row.coverage_adjustment = $staleCoverageImpact
    $row.coverage_adjusted_score = [math]::Round($rawScore + $staleCoverageImpact, 2)
    if ($row.coverage_adjusted_score -lt 7.0) {
      throw "Coverage-adjusted score remains below 7.0 for ${target}: $($row.coverage_adjusted_score)"
    }
  } elseif ($target -notin $facades -and $rawScore -lt 7.0) {
    throw "New owner raw score below 7.0 without an approved stale-coverage adjustment: $target = $rawScore"
  }

  [pscustomobject]$row
}

$rawHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $rawItem.FullName).Hash.ToLowerInvariant()
$coverageHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $coverageItem.FullName).Hash.ToLowerInvariant()
$result = [ordered]@{
  schema_version = 1
  acceptance = "PASS — COVERAGE DEFERRED"
  campaign_baseline = $campaignBaseline
  raw_artifact = [ordered]@{
    command = "repowise health --format json > .superpowers/campaign12/reports/tier1-health-raw.json"
    path = Get-ArtifactPath -Item $rawItem
    size_bytes = [int64]$rawItem.Length
    sha256 = $rawHash
  }
  coverage_provenance = [ordered]@{
    command = "repowise coverage status --format json > .superpowers/campaign12/reports/tier1-coverage-status.json"
    path = Get-ArtifactPath -Item $coverageItem
    size_bytes = [int64]$coverageItem.Length
    sha256 = $coverageHash
    source_format = $coverage.coverage.source_format
    ingested_at = $coverage.coverage.ingested_at
    ingested_commit_sha = $coverage.coverage.ingested_commit_sha
    test_map_ingested_commit_sha = $coverage.test_map.ingested_commit_sha
  }
  extraction = [ordered]@{
    write_command = "pwsh -NoProfile -File .superpowers/campaign12/reports/validate-tier1-health.ps1 -Mode Write"
    verify_command = "pwsh -NoProfile -File .superpowers/campaign12/reports/validate-tier1-health.ps1 -Mode Verify"
    exact_target_count = $targetRows.Count
    stale_coverage_biomarker = "untested_hotspot"
    stale_coverage_impact = $staleCoverageImpact
    adjusted_target_count = $coverageAdjustedTargets.Count
  }
  final_gate_blocker = "Ingest fresh LCOV containing every new owner; the stale penalty must disappear through real coverage evidence and every new owner raw score must be >= 7.0."
  metrics = @($targetRows)
}

$json = $result | ConvertTo-Json -Depth 20
if ($Mode -eq "Write") {
  [System.IO.File]::WriteAllText(
    [System.IO.Path]::GetFullPath($CompactPath),
    $json + [Environment]::NewLine,
    [System.Text.UTF8Encoding]::new($false)
  )
  Write-Output "PASS wrote $($targetRows.Count) exact target rows; adjusted $($coverageAdjustedTargets.Count); raw sha256=$rawHash"
  exit 0
}

$existing = Get-Content -Raw -LiteralPath $CompactPath
if ($existing.TrimEnd() -cne $json.TrimEnd()) {
  throw "Compact artifact does not match deterministic extraction: $CompactPath"
}
Write-Output "PASS verified $($targetRows.Count) exact target rows; adjusted $($coverageAdjustedTargets.Count); raw sha256=$rawHash"
