[CmdletBinding()]
param([switch]$Check)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$libRoot = Join-Path $repoRoot 'lib'
$auditRoot = Join-Path $repoRoot 'docs/audits'
$appRouterPath = Join-Path $libRoot 'core/router/app_router.dart'

function Get-RelativePath([string]$Path) {
  [IO.Path]::GetRelativePath($repoRoot, $Path).Replace('\', '/')
}

function Get-LineNumber([string]$Text, [int]$Index) {
  if ($Index -le 0) { return 1 }
  ([regex]::Matches($Text.Substring(0, $Index), "`n").Count + 1)
}

function Get-Owner([string]$RelativePath) {
  $path = $RelativePath.ToLowerInvariant()
  if ($path -match 'navigation|router|workspace|dashboard|messenger') { return 'SYS-APP-EXPERIENCE' }
  if ($path -match 'theme|widgets/v7|accessib|scroll') { return 'SYS-UI-FOUNDATION' }
  if ($path -match 'security|capability|access|auth') { return 'SYS-ACCESS-SCOPE' }
  if ($path -match 'schedule|lesson|room|teacher') { return 'SYS-SCHEDULE' }
  if ($path -match 'client|student|lead|crm') { return 'SYS-CRM-WORKSPACE' }
  if ($path -match 'task|report|finance|payment|subscription|settings|users') { return 'SYS-OPERATIONS' }
  return 'SYS-PLATFORM-QUALITY'
}

function Get-DartImportTarget([IO.FileInfo]$Source, [string]$Uri) {
  if ($Uri.StartsWith('package:magic_music_crm/')) {
    $suffix = $Uri.Substring('package:magic_music_crm/'.Length).Replace('/', [IO.Path]::DirectorySeparatorChar)
    return Join-Path $libRoot $suffix
  }
  if ($Uri.StartsWith('dart:') -or $Uri.StartsWith('package:')) { return $null }
  if ($Uri.Contains(':')) { return $null }
  return Join-Path $Source.DirectoryName $Uri.Replace('/', [IO.Path]::DirectorySeparatorChar)
}

function Get-ReachableDartFiles {
  $queue = [Collections.Generic.Queue[string]]::new()
  $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  $queue.Enqueue((Join-Path $libRoot 'main.dart'))
  while ($queue.Count -gt 0) {
    $candidate = $queue.Dequeue()
    if (-not (Test-Path -LiteralPath $candidate)) { continue }
    $full = (Resolve-Path -LiteralPath $candidate).Path
    if (-not $seen.Add($full)) { continue }
    $file = Get-Item -LiteralPath $full
    $text = [IO.File]::ReadAllText($full)
    foreach ($match in [regex]::Matches($text, '(?m)^\s*(?:import|export|part)\s+[''"](?<uri>[^''"]+)[''"]')) {
      $target = Get-DartImportTarget $file $match.Groups['uri'].Value
      if ($null -ne $target) { $queue.Enqueue($target) }
    }
  }
  @($seen | Sort-Object | ForEach-Object { Get-Item -LiteralPath $_ })
}

function Get-FileStateEvidence([string]$Text) {
  [ordered]@{
    loading = [bool]($Text -match '(?i)loading|skeleton|shimmer|progressindicator')
    empty = [bool]($Text -match '(?i)\.isEmpty|empty state|пуст|нет данных|ничего не найдено')
    error = [bool]($Text -match '(?i)error:|hasError|ошибк|failure')
    forbidden = [bool]($Text -match '(?i)forbidden|access denied|нет доступа|недоступ')
    retry = [bool]($Text -match '(?i)retry|повторить|обновить|invalidate\(')
  }
}

function New-Artifact([string]$BaseName, [object]$Value, [string]$Markdown) {
  $jsonPath = Join-Path $auditRoot "$BaseName.json"
  $markdownPath = Join-Path $auditRoot "$BaseName.md"
  $json = ($Value | ConvertTo-Json -Depth 14).Replace("`r`n", "`n") + "`n"
  $md = $Markdown.Replace("`r`n", "`n")
  if (-not $md.EndsWith("`n")) { $md += "`n" }

  if ($Check) {
    if (-not (Test-Path $jsonPath) -or -not (Test-Path $markdownPath)) {
      throw "Missing v6 inventory artifact for $BaseName"
    }
    if ([IO.File]::ReadAllText($jsonPath).Replace("`r`n", "`n") -ne $json) {
      throw "$BaseName.json is stale; regenerate scripts/v6_ux_inventory.ps1"
    }
    if ([IO.File]::ReadAllText($markdownPath).Replace("`r`n", "`n") -ne $md) {
      throw "$BaseName.md is stale; regenerate scripts/v6_ux_inventory.ps1"
    }
    return
  }

  if (-not (Test-Path $auditRoot)) { [void](New-Item -ItemType Directory -Path $auditRoot) }
  [IO.File]::WriteAllText($jsonPath, $json, [Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText($markdownPath, $md, [Text.UTF8Encoding]::new($false))
  Write-Output "Wrote $(Get-RelativePath $jsonPath)"
  Write-Output "Wrote $(Get-RelativePath $markdownPath)"
}

$allDartFiles = @(Get-ChildItem $libRoot -Recurse -File -Filter '*.dart')
$reachableFiles = @(Get-ReachableDartFiles)
$reachableSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($file in $reachableFiles) { [void]$reachableSet.Add($file.FullName) }

$routes = [Collections.Generic.List[object]]::new()
$routerText = [IO.File]::ReadAllText($appRouterPath)
foreach ($match in [regex]::Matches($routerText, "(?s)GoRoute\s*\(\s*path:\s*'(?<path>[^']+)'")) {
  $routes.Add([ordered]@{
    path = $match.Groups['path'].Value
    owner = 'SYS-APP-EXPERIENCE'
    status = 'production-mounted'
    file = Get-RelativePath $appRouterPath
    line = Get-LineNumber $routerText $match.Index
  })
}

$screens = [Collections.Generic.List[object]]::new()
$surfaces = [Collections.Generic.List[object]]::new()
$surfacePattern = '(?<call>showDialog|showGeneralDialog|showModalBottomSheet|showMagicSheet|showMagicDrawer|DraggableScrollableSheet)\s*(?:<[^>]+>)?\s*\('

foreach ($file in $allDartFiles) {
  $relative = Get-RelativePath $file.FullName
  $text = [IO.File]::ReadAllText($file.FullName)
  $reachable = $reachableSet.Contains($file.FullName)
  $states = Get-FileStateEvidence $text

  foreach ($match in [regex]::Matches($text, 'class\s+(?<name>[A-Za-z_][A-Za-z0-9_]*(?:Screen|Page))\s+extends\s+')) {
    $screens.Add([ordered]@{
      name = $match.Groups['name'].Value
      owner = Get-Owner $relative
      production_reachable = $reachable
      status = if ($reachable) { 'production-reachable' } else { 'isolated-or-dead' }
      primary_action_evidence = [bool]($text -match 'FloatingActionButton|FilledButton|ElevatedButton|primaryAction')
      states = $states
      file = $relative
      line = Get-LineNumber $text $match.Index
    })
  }

  foreach ($match in [regex]::Matches($text, $surfacePattern)) {
    $call = $match.Groups['call'].Value
    $kind = switch ($call) {
      'showDialog' { 'dialog' }
      'showGeneralDialog' { 'dialog' }
      'showModalBottomSheet' { 'bottom-sheet' }
      'showMagicSheet' { 'magic-sheet' }
      'showMagicDrawer' { 'drawer' }
      default { 'draggable-sheet' }
    }
    $surfaces.Add([ordered]@{
      kind = $kind
      call = $call
      owner = Get-Owner $relative
      production_reachable = $reachable
      status = if ($reachable) { 'production-callsite' } else { 'isolated-or-dead' }
      states = $states
      file = $relative
      line = Get-LineNumber $text $match.Index
    })
  }
}

$routeSurfaceGaps = @(
  $screens | Where-Object {
    $_.production_reachable -and
    (-not $_.states.loading -or -not $_.states.error -or -not $_.states.retry)
  }
)
$routeSurfaceInventory = [ordered]@{
  schema_version = 1
  task = 'V6-001'
  generated_from = 'lib/main.dart import graph + GoRouter + presentation callsites'
  summary = [ordered]@{
    dart_files = $allDartFiles.Count
    production_reachable_files = $reachableFiles.Count
    go_routes = $routes.Count
    screens = $screens.Count
    production_screens = @($screens | Where-Object production_reachable).Count
    isolated_screens = @($screens | Where-Object { -not $_.production_reachable }).Count
    modal_surface_calls = $surfaces.Count
    production_surface_calls = @($surfaces | Where-Object production_reachable).Count
    screen_state_gaps = $routeSurfaceGaps.Count
    unowned = @($screens + $surfaces | Where-Object { [string]::IsNullOrWhiteSpace($_.owner) }).Count
  }
  routes = @($routes)
  screens = @($screens | Sort-Object file, line)
  surfaces = @($surfaces | Sort-Object file, line)
  gaps = @($routeSurfaceGaps | Select-Object name, file, line, states)
}

$routeMd = @"
# MagicMusicCRM v6 — Production Route & Surface Inventory

**Task:** V6-001  
**Generation:** `pwsh -File scripts/v6_ux_inventory.ps1`  
**Validation:** machine-readable companion JSON, stale check supported.

## Coverage

| Slice | Count |
|---|---:|
| Dart files | $($routeSurfaceInventory.summary.dart_files) |
| Files reachable from `main.dart` | $($routeSurfaceInventory.summary.production_reachable_files) |
| GoRouter routes | $($routeSurfaceInventory.summary.go_routes) |
| Screen/Page classes | $($routeSurfaceInventory.summary.screens) |
| Production-reachable screens | $($routeSurfaceInventory.summary.production_screens) |
| Isolated/unreachable screens | $($routeSurfaceInventory.summary.isolated_screens) |
| Modal/sheet/drawer callsites | $($routeSurfaceInventory.summary.modal_surface_calls) |
| Reachable surface callsites | $($routeSurfaceInventory.summary.production_surface_calls) |
| Screens missing loading/error/retry evidence | $($routeSurfaceInventory.summary.screen_state_gaps) |
| Unowned items | $($routeSurfaceInventory.summary.unowned) |

`production_reachable` means the file is reachable through static Dart imports from `lib/main.dart`; it is stronger than “file exists”, but runtime role/scope acceptance remains a later device gate. Every gap remains explicit in the JSON and is not treated as implemented.
"@

$navigationSites = [Collections.Generic.List[object]]::new()
$displayNameRouteCandidates = [Collections.Generic.List[object]]::new()
$navigationPattern = '(?<kind>openEntityLink|EntityRouteRegistry\s*\(|DesktopWorkspaceShell\s*\(|WorkspaceController\s*\(|context\.(?:go|push|replace|goNamed|pushNamed)\s*\(|Navigator(?:\.of)?\s*\(|Navigator\.(?:push|pop|maybePop|canPop)\s*\()'
foreach ($file in $allDartFiles) {
  $relative = Get-RelativePath $file.FullName
  $text = [IO.File]::ReadAllText($file.FullName)
  foreach ($match in [regex]::Matches($text, $navigationPattern)) {
    $raw = $match.Groups['kind'].Value
    $kind = if ($raw -match 'EntityRouteRegistry|openEntityLink') { 'typed-entity' }
      elseif ($raw -match 'DesktopWorkspaceShell|WorkspaceController') { 'workspace' }
      elseif ($raw -match '^context\.') { 'go-router' }
      else { 'navigator' }
    $isDefinition = $relative.StartsWith('lib/core/workspace/') -or $relative -eq 'lib/core/navigation/entity_route_registry.dart'
    $navigationSites.Add([ordered]@{
      kind = $kind
      expression = $match.Value.Trim()
      owner = 'SYS-APP-EXPERIENCE'
      production_reachable = $reachableSet.Contains($file.FullName)
      definition_only = $isDefinition
      status = if ($isDefinition) { 'foundation-definition' }
        elseif ($kind -eq 'typed-entity') { 'typed-context' }
        elseif ($kind -eq 'workspace') { 'production-workspace-usage' }
        elseif ($kind -eq 'go-router') { 'route-navigation-review' }
        else { 'overlay-or-local-navigation-review' }
      file = $relative
      line = Get-LineNumber $text $match.Index
    })
  }
  $lines = [IO.File]::ReadAllLines($file.FullName)
  for ($lineIndex = 0; $lineIndex -lt $lines.Length; $lineIndex++) {
    $line = $lines[$lineIndex]
    if ($line -match '(?i)(context\.(?:go|push)|Navigator\.(?:push|pushNamed)|EntityLink)' -and
        $line -match '(?i)(displayName|fullName|\bname\b|\btitle\b|\blabel\b)') {
      $displayNameRouteCandidates.Add([ordered]@{
        expression = ($line -replace '\s+', ' ').Trim()
        owner = 'SYS-APP-EXPERIENCE'
        production_reachable = $reachableSet.Contains($file.FullName)
        status = 'display-name-route-review'
        file = $relative
        line = $lineIndex + 1
      })
    }
  }
}

$entityTypes = [Collections.Generic.List[string]]::new()
$entityPath = Join-Path $libRoot 'core/navigation/entity_link.dart'
$entityText = [IO.File]::ReadAllText($entityPath)
$enumMatch = [regex]::Match($entityText, '(?s)enum\s+EntityLinkType\s*\{(?<body>.*?)\}')
if ($enumMatch.Success) {
  foreach ($value in ($enumMatch.Groups['body'].Value -split ',')) {
    $name = ($value -replace '//.*', '').Trim()
    if ($name -match '^[A-Za-z_][A-Za-z0-9_]*$') { $entityTypes.Add($name) }
  }
}

$workspaceUsages = @($navigationSites | Where-Object { $_.kind -eq 'workspace' -and -not $_.definition_only -and $_.production_reachable })
$typedUsages = @($navigationSites | Where-Object { $_.kind -eq 'typed-entity' -and -not $_.definition_only -and $_.production_reachable })
$navigationInventory = [ordered]@{
  schema_version = 1
  task = 'V6-002'
  summary = [ordered]@{
    navigation_sites = $navigationSites.Count
    production_navigation_sites = @($navigationSites | Where-Object production_reachable).Count
    typed_entity_usages = $typedUsages.Count
    workspace_production_usages = $workspaceUsages.Count
    entity_link_types = $entityTypes.Count
    pending_direct_sites = @($navigationSites | Where-Object { $_.production_reachable -and $_.status -match 'review$' }).Count
    display_name_route_candidates = @($displayNameRouteCandidates | Where-Object production_reachable).Count
    unowned = @($navigationSites | Where-Object { [string]::IsNullOrWhiteSpace($_.owner) }).Count
  }
  entity_link_types = @($entityTypes)
  navigation_sites = @($navigationSites | Sort-Object file, line)
  display_name_route_candidates = @($displayNameRouteCandidates | Sort-Object file, line)
  production_workspace_usages = $workspaceUsages
}

$navigationMd = @"
# MagicMusicCRM v6 — Navigation Inventory

**Task:** V6-002

| Slice | Count |
|---|---:|
| Navigation callsites | $($navigationInventory.summary.navigation_sites) |
| Production-reachable callsites | $($navigationInventory.summary.production_navigation_sites) |
| Typed entity usages | $($navigationInventory.summary.typed_entity_usages) |
| Production workspace usages outside definitions | $($navigationInventory.summary.workspace_production_usages) |
| EntityLink types | $($navigationInventory.summary.entity_link_types) |
| Direct sites requiring classification/migration | $($navigationInventory.summary.pending_direct_sites) |
| Display-name route candidates | $($navigationInventory.summary.display_name_route_candidates) |
| Unowned | $($navigationInventory.summary.unowned) |

The key production gap is explicit: workspace foundations do not count as mounted until `production_workspace_usages > 0`. Direct Navigator calls include legitimate overlay exits and therefore remain review items rather than automatic defects.
"@

$scrollSites = [Collections.Generic.List[object]]::new()
$backSites = [Collections.Generic.List[object]]::new()
$scrollPattern = '(?<kind>RawScrollbar|Scrollbar|SingleChildScrollView|ListView(?:\.[A-Za-z]+)?|GridView(?:\.[A-Za-z]+)?|CustomScrollView|DraggableScrollableSheet)\s*\('
$backPattern = '(?<kind>PopScope|WillPopScope|NavigatorPopHandler|Form)\s*(?:<[^>]+>)?\s*\(|(?<exit>Navigator\.(?:pop|maybePop)|context\.pop)\s*\('
foreach ($file in $allDartFiles) {
  $relative = Get-RelativePath $file.FullName
  $text = [IO.File]::ReadAllText($file.FullName)
  $hasController = $text -match 'ScrollController\s*\('
  $hasScrollbar = $text -match '(?:Raw)?Scrollbar\s*\('
  $hasThumbVisibility = $text -match 'thumbVisibility\s*:\s*true'
  foreach ($match in [regex]::Matches($text, $scrollPattern)) {
    $kind = $match.Groups['kind'].Value
    $scrollSites.Add([ordered]@{
      kind = $kind
      owner = Get-Owner $relative
      production_reachable = $reachableSet.Contains($file.FullName)
      controller_evidence = $hasController
      scrollbar_evidence = $hasScrollbar
      visible_thumb_evidence = $hasThumbVisibility
      status = if ($kind -match 'Scrollbar') { 'explicit-scrollbar' } else { 'scroll-owner-review' }
      file = $relative
      line = Get-LineNumber $text $match.Index
    })
  }
  foreach ($match in [regex]::Matches($text, $backPattern)) {
    $kind = if ($match.Groups['kind'].Success) { $match.Groups['kind'].Value } else { 'imperative-exit' }
    $backSites.Add([ordered]@{
      kind = $kind
      owner = Get-Owner $relative
      production_reachable = $reachableSet.Contains($file.FullName)
      ahead_of_time = $kind -in @('PopScope', 'NavigatorPopHandler', 'Form')
      status = if ($kind -in @('PopScope', 'NavigatorPopHandler', 'Form')) { 'predictive-back-capable' }
        elseif ($kind -eq 'WillPopScope') { 'legacy-back' }
        else { 'exit-review' }
      file = $relative
      line = Get-LineNumber $text $match.Index
    })
  }
}

$inputBackInventory = [ordered]@{
  schema_version = 1
  task = 'V6-003'
  summary = [ordered]@{
    scroll_sites = $scrollSites.Count
    production_scroll_sites = @($scrollSites | Where-Object production_reachable).Count
    explicit_scrollbars = @($scrollSites | Where-Object { $_.production_reachable -and $_.kind -match 'Scrollbar' }).Count
    visible_thumb_sites = @($scrollSites | Where-Object { $_.production_reachable -and $_.visible_thumb_evidence }).Count
    scroll_sites_without_file_controller_evidence = @($scrollSites | Where-Object { $_.production_reachable -and -not $_.controller_evidence -and $_.kind -notmatch 'Scrollbar' }).Count
    back_exit_sites = $backSites.Count
    production_back_exit_sites = @($backSites | Where-Object production_reachable).Count
    predictive_back_sites = @($backSites | Where-Object { $_.production_reachable -and $_.ahead_of_time }).Count
    legacy_back_sites = @($backSites | Where-Object { $_.production_reachable -and $_.kind -eq 'WillPopScope' }).Count
    unowned = @($scrollSites + $backSites | Where-Object { [string]::IsNullOrWhiteSpace($_.owner) }).Count
  }
  scroll_sites = @($scrollSites | Sort-Object file, line)
  back_sites = @($backSites | Sort-Object file, line)
}

$inputMd = @"
# MagicMusicCRM v6 — Input, Scroll & Back Inventory

**Task:** V6-003

| Slice | Count |
|---|---:|
| Production scroll sites | $($inputBackInventory.summary.production_scroll_sites) |
| Explicit scrollbar callsites | $($inputBackInventory.summary.explicit_scrollbars) |
| Files with visible-thumb evidence | $($inputBackInventory.summary.visible_thumb_sites) |
| Scroll sites without file-level controller evidence | $($inputBackInventory.summary.scroll_sites_without_file_controller_evidence) |
| Production Back/exit sites | $($inputBackInventory.summary.production_back_exit_sites) |
| Ahead-of-time predictive Back sites | $($inputBackInventory.summary.predictive_back_sites) |
| Legacy WillPopScope sites | $($inputBackInventory.summary.legacy_back_sites) |
| Unowned | $($inputBackInventory.summary.unowned) |

File-level evidence is intentionally conservative: it locates ownership gaps but does not claim a controller is correctly attached. Windows mouse-only and Android predictive-Back device tests remain mandatory integration evidence.
"@

$wireSites = [Collections.Generic.List[object]]::new()
$serviceFiles = @($allDartFiles | Where-Object { $_.FullName -match '[\\/](services?|api)[\\/]' -or $_.Name -match '(service|api)\.dart$' })
$wirePattern = '\.(?<verb>postIdempotent|postBytes|downloadBytes|get|post|put|patch|delete|request)\s*(?:<[^\r\n(]+>)?\s*\('
foreach ($file in $serviceFiles) {
  $relative = Get-RelativePath $file.FullName
  $text = [IO.File]::ReadAllText($file.FullName)
  foreach ($match in [regex]::Matches($text, $wirePattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
    $lineStart = $text.LastIndexOf("`n", [Math]::Max(0, $match.Index - 1)) + 1
    $lineEnd = $text.IndexOf("`n", $match.Index)
    if ($lineEnd -lt 0) { $lineEnd = $text.Length }
    $wireSites.Add([ordered]@{
      verb = $match.Groups['verb'].Value.ToUpperInvariant()
      expression = ($text.Substring($lineStart, $lineEnd - $lineStart) -replace '\s+', ' ').Trim()
      owner = Get-Owner $relative
      production_reachable = $reachableSet.Contains($file.FullName)
      status = 'static-wire-baseline'
      file = $relative
      line = Get-LineNumber $text $match.Index
    })
  }
}

$processRoots = @(
  [ordered]@{ process = 'Flutter client'; entry = 'lib/main.dart'; protocol = 'HTTPS/JSON + Socket.IO'; status = 'typed-services-over-json' },
  [ordered]@{ process = 'NestJS server'; entry = 'server/src/main.ts'; protocol = 'HTTP/JSON + Socket.IO'; status = 'DTO/OpenAPI/policy-contract' }
)
$spawnSites = [Collections.Generic.List[object]]::new()
foreach ($file in @($allDartFiles + (Get-ChildItem (Join-Path $repoRoot 'server/src') -Recurse -File -Filter '*.ts'))) {
  $relative = Get-RelativePath $file.FullName
  $text = [IO.File]::ReadAllText($file.FullName)
  foreach ($match in [regex]::Matches($text, 'Process\.(?:start|run)\s*\(|spawnSync\s*\(|spawn\s*\(')) {
    $spawnSites.Add([ordered]@{
      owner = 'SYS-PLATFORM-QUALITY'
      status = 'runtime-lifecycle-review'
      file = $relative
      line = Get-LineNumber $text $match.Index
      expression = $match.Value.Trim()
    })
  }
}

$wireInventory = [ordered]@{
  schema_version = 1
  task = 'V6-005'
  evidence_level = 'static call inventory + seeded actor/payload and Flutter service-contract baseline; see v6-s0-baseline.md'
  summary = [ordered]@{
    service_files = $serviceFiles.Count
    wire_calls = $wireSites.Count
    production_wire_calls = @($wireSites | Where-Object production_reachable).Count
    process_roots = $processRoots.Count
    spawn_sites = $spawnSites.Count
    unowned = @($wireSites | Where-Object { [string]::IsNullOrWhiteSpace($_.owner) }).Count
  }
  process_roots = $processRoots
  spawn_sites = @($spawnSites | Sort-Object file, line)
  wire_calls = @($wireSites | Sort-Object file, line)
}

$wireMd = @"
# MagicMusicCRM v6 — Wire-to-Service Baseline

**Task:** V6-005  
**Evidence level:** static call inventory + seeded actor/payload and Flutter service-contract baseline recorded in `v6-s0-baseline.md`.

| Slice | Count |
|---|---:|
| Service/API files | $($wireInventory.summary.service_files) |
| HTTP-like callsites | $($wireInventory.summary.wire_calls) |
| Production-reachable callsites | $($wireInventory.summary.production_wire_calls) |
| Process roots | $($wireInventory.summary.process_roots) |
| Spawn sites | $($wireInventory.summary.spawn_sites) |
| Unowned | $($wireInventory.summary.unowned) |

## Runtime boundaries

- Flutter process: HTTPS/JSON and Socket.IO to the NestJS API.
- NestJS process: HTTP/JSON + Socket.IO, DTO/policy contracts, PostgreSQL persistence.
- Local child-process sites are lifecycle-reviewed separately in the JSON; they are not part of CRM request routing.

The checked companion baseline records the seeded actor/payload matrix and representative Schedule, Client, Payment, Tasks, Dashboard and configuration contract tests. Real-account acceptance remains an S7 gate.
"@

if ($routes.Count -eq 0 -or $reachableFiles.Count -eq 0) { throw 'Route/import inventory is empty' }
if ($routeSurfaceInventory.summary.unowned -ne 0 -or $navigationInventory.summary.unowned -ne 0 -or $inputBackInventory.summary.unowned -ne 0 -or $wireInventory.summary.unowned -ne 0) {
  throw 'One or more v6 inventory items are unowned'
}

New-Artifact 'v6-route-surface-inventory' $routeSurfaceInventory $routeMd
New-Artifact 'v6-navigation-inventory' $navigationInventory $navigationMd
New-Artifact 'v6-input-back-inventory' $inputBackInventory $inputMd
New-Artifact 'v6-wire-service-baseline' $wireInventory $wireMd

if ($Check) {
  Write-Output "v6 UX inventory PASS: routes=$($routes.Count), reachable=$($reachableFiles.Count), workspaceProduction=$($workspaceUsages.Count), unowned=0"
}
