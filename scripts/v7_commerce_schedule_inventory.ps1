[CmdletBinding()]
param([switch]$Check)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$jsonPath = Join-Path $repoRoot 'docs/audits/v7-commerce-schedule-inventory.json'
$markdownPath = Join-Path $repoRoot 'docs/audits/v7-commerce-schedule-inventory.md'

function Get-RelativePath([string]$Path) {
  [IO.Path]::GetRelativePath($repoRoot, $Path).Replace('\', '/')
}

function Get-LineNumber([string]$Text, [int]$Index) {
  if ($Index -le 0) { return 1 }
  [regex]::Matches($Text.Substring(0, $Index), "`n").Count + 1
}

function Get-Owner([string]$Path) {
  $value = $Path.ToLowerInvariant()
  if ($value -match '^server/src/access-control/') { return 'SYS-ACCESS-SCOPE' }
  if ($value -match '^server/src/crm/commerce/') { return 'SYS-COMMERCE-INTEGRITY' }
  if ($value -match '^server/src/crm/.*(?:schedule|lesson|room)') { return 'SYS-SCHEDULE' }
  if ($value -match '^server/src/(analytics/|crm/.*(?:finance|dashboard|payroll|section-views))') { return 'SYS-OPERATIONS' }
  if ($value -match '^server/src/crm/(clients/|crm\.service|leads\.service)') { return 'SYS-CRM-WORKSPACE' }
  if ($value -match '^server/src/crm/') { return 'SYS-COMMERCE-INTEGRITY' }
  if ($value -match '^server/src/(platform/|migration/|db/)') { return 'SYS-PLATFORM-QUALITY' }
  if ($value -match '^lib/core/services/') { return 'SYS-APP-EXPERIENCE' }
  if ($value -match '^lib/features/(crm|client)/') { return 'SYS-CRM-WORKSPACE' }
  if ($value -match '^lib/features/admin/.*schedule') { return 'SYS-SCHEDULE' }
  if ($value -match '^lib/features/(admin|manager)/') { return 'SYS-OPERATIONS' }
  if ($value -match '^lib/') { return 'SYS-APP-EXPERIENCE' }
  return $null
}

function Get-Operation([string]$Text, [int]$Index) {
  $start = [Math]::Max(0, $Index - 160)
  $prefix = $Text.Substring($start, $Index - $start).ToLowerInvariant()
  if ($prefix -match 'insert\s+into\s+$|update\s+$|delete\s+from\s+$') { return 'mutation' }
  if ($prefix -match '(from|join)\s+$') { return 'read' }
  return 'reference'
}

function Get-Digest([IO.FileInfo[]]$Files) {
  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    foreach ($file in ($Files | Sort-Object FullName -Unique)) {
      $relative = Get-RelativePath $file.FullName
      $content = [IO.File]::ReadAllText($file.FullName).Replace("`r`n", "`n")
      $bytes = [Text.Encoding]::UTF8.GetBytes("$relative`n$content`n")
      [void]$sha.TransformBlock($bytes, 0, $bytes.Length, $bytes, 0)
    }
    [void]$sha.TransformFinalBlock([byte[]]::new(0), 0, 0)
    [Convert]::ToHexString($sha.Hash).ToLowerInvariant()
  } finally {
    $sha.Dispose()
  }
}

$serverFiles = @(Get-ChildItem (Join-Path $repoRoot 'server/src') -Recurse -File -Filter '*.ts' |
  Where-Object { $_.Name -notlike '*.spec.ts' -and $_.Name -notlike '*.d.ts' })
$flutterFiles = @(Get-ChildItem (Join-Path $repoRoot 'lib') -Recurse -File -Filter '*.dart')
$sourceFiles = @($serverFiles + $flutterFiles)
$financeTables = 'app\.(?<table>payments|account_adjustments|subscription_obligation_facts|expected_payments)\b'
$financeWire = '(?i)(?<wire>/(?:[^''"\s]*/)?(?:payments?|finance|subscriptions?|account-adjustments)(?:/[^''"\s]*)?)'
$lessonWrite = '(?is)(?<statement>(?:update\s+app\.lessons\b|insert\s+into\s+app\.lessons\b).{0,900}?(?:scheduled_at|duration_minutes))'
$lessonWire = '(?i)(?<wire>/(?:[^''"\s]*/)?lessons?/(?:[^''"\s]*/)?(?:move|reschedule|transition)|\b(?:moveLesson|rescheduleLesson|updateLessonTime)\s*\()'

$financeSites = [Collections.Generic.List[object]]::new()
$lessonSites = [Collections.Generic.List[object]]::new()
$matchedFiles = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

foreach ($file in $sourceFiles) {
  $relative = Get-RelativePath $file.FullName
  $text = [IO.File]::ReadAllText($file.FullName)
  foreach ($match in [regex]::Matches($text, $financeTables, [Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
    [void]$matchedFiles.Add($file.FullName)
    $financeSites.Add([ordered]@{
      kind = 'sql-table'
      subject = $match.Groups['table'].Value.ToLowerInvariant()
      operation = Get-Operation $text $match.Index
      owner = Get-Owner $relative
      file = $relative
      line = Get-LineNumber $text $match.Index
    })
  }
  foreach ($match in [regex]::Matches($text, $financeWire)) {
    [void]$matchedFiles.Add($file.FullName)
    $financeSites.Add([ordered]@{
      kind = 'wire'
      subject = $match.Groups['wire'].Value
      operation = 'call'
      owner = Get-Owner $relative
      file = $relative
      line = Get-LineNumber $text $match.Index
    })
  }
  foreach ($match in [regex]::Matches($text, $lessonWrite)) {
    [void]$matchedFiles.Add($file.FullName)
    $lessonSites.Add([ordered]@{
      kind = 'sql-temporal-write'
      subject = (($match.Groups['statement'].Value -replace '\s+', ' ').Trim()).Substring(0, [Math]::Min(180, (($match.Groups['statement'].Value -replace '\s+', ' ').Trim()).Length))
      owner = Get-Owner $relative
      file = $relative
      line = Get-LineNumber $text $match.Index
    })
  }
  foreach ($match in [regex]::Matches($text, $lessonWire)) {
    [void]$matchedFiles.Add($file.FullName)
    $lessonSites.Add([ordered]@{
      kind = 'wire-temporal-mutation'
      subject = $match.Groups['wire'].Value
      owner = Get-Owner $relative
      file = $relative
      line = Get-LineNumber $text $match.Index
    })
  }
}

$unowned = @($financeSites + $lessonSites | Where-Object { [string]::IsNullOrWhiteSpace($_.owner) })
if ($unowned.Count -ne 0) {
  $locations = ($unowned | Select-Object -First 10 | ForEach-Object { "$($_.file):$($_.line)" }) -join ', '
  throw "v7 inventory contains $($unowned.Count) unowned callsites: $locations"
}

$artifact = [ordered]@{
  schema_version = 1
  task = 'T1.1.1'
  source_digest = Get-Digest @($matchedFiles | ForEach-Object { Get-Item -LiteralPath $_ })
  summary = [ordered]@{
    matched_source_files = $matchedFiles.Count
    finance_callsites = $financeSites.Count
    ordinary_finance_reads = @($financeSites | Where-Object operation -eq 'read').Count
    lesson_temporal_mutations = $lessonSites.Count
    unowned = $unowned.Count
  }
  finance_callsites = @($financeSites | Sort-Object file, line, subject)
  lesson_temporal_mutations = @($lessonSites | Sort-Object file, line, subject)
}

$json = ($artifact | ConvertTo-Json -Depth 8).Replace("`r`n", "`n") + "`n"
$markdown = @"
# MagicMusicCRM v7 — Commerce & Schedule Mutation Inventory

**Task:** T1.1.1  
**Generation:** ``pwsh -File scripts/v7_commerce_schedule_inventory.ps1``  
**Stale check:** ``pwsh -File scripts/v7_commerce_schedule_inventory.ps1 -Check``

| Slice | Count |
|---|---:|
| Matched production source files | $($artifact.summary.matched_source_files) |
| Finance SQL/wire callsites | $($artifact.summary.finance_callsites) |
| Ordinary finance reads | $($artifact.summary.ordinary_finance_reads) |
| Protected lesson temporal mutations | $($artifact.summary.lesson_temporal_mutations) |
| Unowned | $($artifact.summary.unowned) |

The JSON companion is the authoritative deterministic baseline. A new matching
callsite changes the artifact; an unknown owner fails generation immediately.
"@.Replace("`r`n", "`n")
if (-not $markdown.EndsWith("`n")) { $markdown += "`n" }

if ($Check) {
  if (-not (Test-Path $jsonPath) -or -not (Test-Path $markdownPath)) { throw 'Missing v7 inventory baseline' }
  if ([IO.File]::ReadAllText($jsonPath).Replace("`r`n", "`n") -ne $json) { throw 'v7 commerce/schedule JSON inventory is stale' }
  if ([IO.File]::ReadAllText($markdownPath).Replace("`r`n", "`n") -ne $markdown) { throw 'v7 commerce/schedule Markdown inventory is stale' }
  Write-Output "v7 inventory PASS: finance=$($artifact.summary.finance_callsites), lessonWrites=$($artifact.summary.lesson_temporal_mutations), unowned=0"
  exit 0
}

[IO.File]::WriteAllText($jsonPath, $json, [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($markdownPath, $markdown, [Text.UTF8Encoding]::new($false))
Write-Output "Wrote $(Get-RelativePath $jsonPath)"
Write-Output "Wrote $(Get-RelativePath $markdownPath)"
