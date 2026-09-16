[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$baseRevision = '0a7b6e1742f9456099e3023298ad84883e51a8e2'
$runId = [guid]::NewGuid().ToString('N')
$snapshot = Join-Path $repoRoot "dist/recovery-images/$runId"
New-Item -ItemType Directory -Path $snapshot | Out-Null
# Export a reviewed historical tree, never switch or overwrite the working tree.
& git -C $repoRoot archive --format=tar --output="$snapshot/base.tar" $baseRevision server
if ($LASTEXITCODE -ne 0) { throw 'Historical source export failed.' }
& tar -xf "$snapshot/base.tar" -C $snapshot
if ($LASTEXITCODE -ne 0) { throw 'Historical source extraction failed.' }
$backports = @(
  'server/src/crm/commerce/lesson-settlement.port.ts',
  'server/src/crm/commerce/lesson-settlement.service.ts',
  'server/src/crm/crm-configuration-baseline.ts',
  'server/src/crm/schedule/lesson-draft.contracts.ts',
  'server/src/crm/schedule/lesson-required-field.validator.ts',
  'server/src/crm/schedule/lesson-reschedule-financial-preparation.ts',
  'server/src/crm/schedule/lesson-transition-preparation.service.ts',
  # Updated clients send branchId even outside the new report window.
  'server/src/crm/dto/lesson.query.ts',
  'server/src/crm/schedule/schedule-read.service.ts',
  # Full compatibility includes filtered totals, units, and the shared export path.
  'server/src/crm/dto/teacher-stats.query.ts',
  'server/src/crm/payroll/teacher-stats-report.service.ts',
  'server/db/migrations/0156_trial_lesson_catalog.up.sql',
  'server/db/migrations/0156_trial_lesson_catalog.down.sql'
)
$manifest = foreach ($relative in $backports) {
  $source = Join-Path $repoRoot $relative
  Copy-Item -LiteralPath $source -Destination (Join-Path $snapshot $relative)
  [ordered]@{ path = $relative; sha256 = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant() }
}
$manifestJson = $manifest | ConvertTo-Json -Compress
$hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($manifestJson))).ToLowerInvariant()
$version = "221-recovery-0156-$($hash.Substring(0,12))"
$tag = "magicmusiccrm-server:$version"
& docker build --pull=false --tag $tag `
  --label "org.opencontainers.image.revision=$baseRevision" `
  --label "org.opencontainers.image.version=$version" `
  --label 'com.magicmusiccrm.dirty=true' `
  --label "com.magicmusiccrm.compatibility-backports-sha256=$hash" `
  (Join-Path $snapshot 'server')
if ($LASTEXITCODE -ne 0) { throw 'Recovery image build failed.' }
$image = (& docker image inspect $tag | ConvertFrom-Json)[0]
if ($LASTEXITCODE -ne 0) { throw 'Recovery image inspection failed.' }
[ordered]@{
  baseRevision = $baseRevision; backports = $manifest; backportsSha256 = $hash
  image = $tag; imageId = $image.Id; createdAt = (Get-Date).ToUniversalTime().ToString('o')
  status = 'BUILT_NOT_VERIFIED'; limitations = @('Financial safeguards and report filtering are shared with the candidate, not an independent fix for defects in those shared changes.')
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $snapshot 'manifest.json') -Encoding utf8NoBOM
Write-Output "Recovery image: $tag"
Write-Output "Evidence: $snapshot/manifest.json"
