[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$reportDirectory = $PSScriptRoot
$validatorPath = Join-Path $reportDirectory "validate-tier1-health.ps1"
$rawPath = Join-Path $reportDirectory "tier1-health-raw.json"
$coveragePath = Join-Path $reportDirectory "tier1-coverage-status.json"

if (-not (Test-Path -LiteralPath $validatorPath)) {
  throw "Validator missing: $validatorPath"
}

$target = "server/src/messenger/messenger.service.ts"
$adjustedTarget = "server/src/messenger/messenger-chat-query.service.ts"
$tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$tempDirectory = [System.IO.Path]::GetFullPath(
  (Join-Path $tempRoot ("tier1-health-tests-" + [guid]::NewGuid()))
)
if (-not $tempDirectory.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw "Unsafe temporary directory: $tempDirectory"
}
$null = New-Item -ItemType Directory -Path $tempDirectory

function Write-TestJson {
  param(
    [Parameter(Mandatory)] $Value,
    [Parameter(Mandatory)] [string] $Path
  )

  $Value | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $Path -Encoding utf8NoBOM
}

function Invoke-ValidatorFailure {
  param(
    [Parameter(Mandatory)] [string] $FixturePath,
    [Parameter(Mandatory)] [string] $ExpectedMessage,
    [Parameter(Mandatory)] [string] $Name,
    [string] $FixtureCoveragePath = $coveragePath
  )

  $compactPath = Join-Path $tempDirectory "$Name-compact.json"
  $output = & (Join-Path $PSHOME "pwsh.exe") -NoProfile -File $validatorPath `
    -RawPath $FixturePath `
    -CoveragePath $FixtureCoveragePath `
    -CompactPath $compactPath `
    -Mode Write 2>&1
  $exitCode = $LASTEXITCODE
  if ($exitCode -eq 0) {
    throw "$Name unexpectedly passed"
  }
  if (($output -join "`n") -notmatch [regex]::Escape($ExpectedMessage)) {
    throw "$Name failed for the wrong reason: $($output -join ' | ')"
  }
  Write-Output "PASS $Name"
}

try {
  $raw = Get-Content -Raw -LiteralPath $rawPath | ConvertFrom-Json

  $missing = Get-Content -Raw -LiteralPath $rawPath | ConvertFrom-Json
  $missing.metrics = @($missing.metrics | Where-Object { $_.file_path -ne $target })
  $missingPath = Join-Path $tempDirectory "missing.json"
  Write-TestJson -Value $missing -Path $missingPath
  Invoke-ValidatorFailure -FixturePath $missingPath -ExpectedMessage "Expected exactly one metric row for $target; got 0" -Name "missing-target"

  $duplicate = Get-Content -Raw -LiteralPath $rawPath | ConvertFrom-Json
  $duplicate.metrics = @($duplicate.metrics) + @($duplicate.metrics | Where-Object { $_.file_path -eq $target })
  $duplicatePath = Join-Path $tempDirectory "duplicate.json"
  Write-TestJson -Value $duplicate -Path $duplicatePath
  Invoke-ValidatorFailure -FixturePath $duplicatePath -ExpectedMessage "Expected exactly one metric row for $target; got 2" -Name "duplicate-target"

  $badImpact = Get-Content -Raw -LiteralPath $rawPath | ConvertFrom-Json
  $impactFinding = @($badImpact.findings | Where-Object {
      $_.file_path -eq $adjustedTarget -and $_.biomarker_type -eq "untested_hotspot"
    })[0]
  $impactFinding.health_impact = 1.55
  $badImpactPath = Join-Path $tempDirectory "bad-impact.json"
  Write-TestJson -Value $badImpact -Path $badImpactPath
  Invoke-ValidatorFailure -FixturePath $badImpactPath -ExpectedMessage "Expected exactly one untested_hotspot impact 1.56 for $adjustedTarget" -Name "bad-impact"

  $badCoverage = Get-Content -Raw -LiteralPath $coveragePath | ConvertFrom-Json
  $badCoverage.coverage.ingested_commit_sha = "0000000000000000000000000000000000000000"
  $badCoveragePath = Join-Path $tempDirectory "bad-coverage.json"
  Write-TestJson -Value $badCoverage -Path $badCoveragePath
  Invoke-ValidatorFailure -FixturePath $rawPath -FixtureCoveragePath $badCoveragePath -ExpectedMessage "Coverage SHA does not match the approved stale snapshot" -Name "bad-coverage"

  $compactPath = Join-Path $tempDirectory "valid-compact.json"
  & (Join-Path $PSHOME "pwsh.exe") -NoProfile -File $validatorPath -RawPath $rawPath -CoveragePath $coveragePath -CompactPath $compactPath -Mode Write
  if ($LASTEXITCODE -ne 0) { throw "valid-write failed" }
  & (Join-Path $PSHOME "pwsh.exe") -NoProfile -File $validatorPath -RawPath $rawPath -CoveragePath $coveragePath -CompactPath $compactPath -Mode Verify
  if ($LASTEXITCODE -ne 0) { throw "valid-verify failed" }
  Write-Output "PASS valid-write-and-verify"
} finally {
  if ($tempDirectory.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    Remove-Item -LiteralPath $tempDirectory -Recurse -Force -ErrorAction SilentlyContinue
  }
}
