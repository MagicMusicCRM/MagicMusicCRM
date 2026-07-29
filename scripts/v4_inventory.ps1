[CmdletBinding()]
param(
  [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$serverRoot = Join-Path $repoRoot 'server/src'
$flutterRoot = Join-Path $repoRoot 'lib'
$migrationRoot = Join-Path $repoRoot 'server/db/migrations'
$jsonPath = Join-Path $repoRoot 'docs/audits/v4-current-state-inventory.json'
$markdownPath = Join-Path $repoRoot 'docs/audits/v4-current-state-inventory.md'

$systems = @(
  'SYS-APP',
  'SYS-ACCESS',
  'SYS-CRM',
  'SYS-SCHEDULE',
  'SYS-COMMERCE',
  'SYS-WORKFLOW',
  'SYS-REPORTING',
  'SYS-PLATFORM'
)

function Get-RelativePath {
  param([Parameter(Mandatory)][string]$Path)

  return [IO.Path]::GetRelativePath($repoRoot, $Path).Replace('\', '/')
}

function Get-Owner {
  param(
    [Parameter(Mandatory)][string]$RelativePath,
    [string]$Subject = ''
  )

  $value = "$RelativePath $Subject".ToLowerInvariant()
  if ($RelativePath -like 'lib/*') { return 'SYS-APP' }
  if ($value -match 'analytics|report|export|forecast|data-quality') {
    return 'SYS-REPORTING'
  }
  if ($value -match 'lesson|schedule|attendance|room|availability') {
    return 'SYS-SCHEDULE'
  }
  if ($value -match 'payment|finance|subscription|expense|payroll|payout|teacher-rate|adjustment|transfer') {
    return 'SYS-COMMERCE'
  }
  if ($value -match 'task|notification|reminder') {
    return 'SYS-WORKFLOW'
  }
  if ($value -match 'auth|profile|legal|security|role|permission|admin-staff') {
    return 'SYS-ACCESS'
  }
  if ($value -match 'lead|student|client|branch|group|crm|settings') {
    return 'SYS-CRM'
  }
  return 'SYS-PLATFORM'
}

function Get-LineNumber {
  param(
    [Parameter(Mandatory)][string]$Text,
    [Parameter(Mandatory)][int]$Index
  )

  if ($Index -le 0) { return 1 }
  return ([regex]::Matches($Text.Substring(0, $Index), "`n").Count + 1)
}

function Normalize-Snippet {
  param([AllowEmptyString()][string]$Value)

  if ($null -eq $Value) { return '' }
  return (($Value -replace '\s+', ' ').Trim())
}

function Escape-Markdown {
  param([AllowEmptyString()][string]$Value)

  if ($null -eq $Value) { return '' }
  return ($Value.Replace('|', '\|').Replace("`r", '').Replace("`n", '<br>'))
}

function Get-RoleValues {
  param([AllowEmptyString()][string]$Expression)

  $values = @(
    [regex]::Matches($Expression, "['`"](?<role>[a-z_]+)['`"]") |
      ForEach-Object { $_.Groups['role'].Value }
  )
  return @($values | Sort-Object -Unique)
}

function Get-SourceDigest {
  param([Parameter(Mandatory)][IO.FileInfo[]]$Files)

  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    foreach ($file in ($Files | Sort-Object FullName -Unique)) {
      $relative = Get-RelativePath $file.FullName
      $content = [IO.File]::ReadAllText($file.FullName).Replace("`r`n", "`n")
      $bytes = [Text.Encoding]::UTF8.GetBytes("$relative`n$content`n")
      [void]$sha.TransformBlock($bytes, 0, $bytes.Length, $bytes, 0)
    }
    [void]$sha.TransformFinalBlock([byte[]]::new(0), 0, 0)
    return ([Convert]::ToHexString($sha.Hash).ToLowerInvariant())
  } finally {
    $sha.Dispose()
  }
}

function Join-Route {
  param(
    [AllowEmptyString()][string]$Controller,
    [AllowEmptyString()][string]$Route
  )

  $parts = @(
    @($Controller, $Route) |
      ForEach-Object { $_.Trim().Trim('/') } |
      Where-Object { $_ -ne '' }
  )
  if ($parts.Count -eq 0) { return '/' }
  return '/' + ($parts -join '/')
}

$serverFiles = @(
  Get-ChildItem -Path $serverRoot -Recurse -File -Filter '*.ts' |
    Where-Object {
      $_.Name -notlike '*.spec.ts' -and
      $_.Name -notlike '*.d.ts'
    }
)
$controllerFiles = @($serverFiles | Where-Object { $_.Name -like '*.controller.ts' })
$dtoFiles = @($serverFiles | Where-Object { $_.FullName -match '[\\/]dto[\\/]' })
$flutterFiles = @(Get-ChildItem -Path $flutterRoot -Recurse -File -Filter '*.dart')
$migrationFiles = @(
  Get-ChildItem -Path $migrationRoot -File -Filter '*.up.sql' |
    Sort-Object Name
)
$digestFiles = @($serverFiles + $flutterFiles + $migrationFiles)

$backendRoutes = [Collections.Generic.List[object]]::new()
$routeDecoratorCount = 0

foreach ($file in $controllerFiles) {
  $relative = Get-RelativePath $file.FullName
  $text = [IO.File]::ReadAllText($file.FullName)
  $controllerMatch = [regex]::Match(
    $text,
    '@Controller\s*\(\s*(?:[''"](?<path>[^''"]*)[''"])?\s*\)',
    [Text.RegularExpressions.RegexOptions]::Multiline
  )
  $controllerPath = if ($controllerMatch.Success) {
    $controllerMatch.Groups['path'].Value
  } else {
    ''
  }

  $routeMatches = [regex]::Matches(
    $text,
    '(?m)^[ \t]*@(?<verb>Get|Post|Patch|Put|Delete)\s*\(\s*(?:[''"](?<path>[^''"]*)[''"])?\s*\)'
  )
  $routeDecoratorCount += $routeMatches.Count

  for ($index = 0; $index -lt $routeMatches.Count; $index++) {
    $match = $routeMatches[$index]
    $segmentEnd = if ($index + 1 -lt $routeMatches.Count) {
      $routeMatches[$index + 1].Index
    } else {
      $text.Length
    }
    $segment = $text.Substring($match.Index, $segmentEnd - $match.Index)
    $methodMatch = [regex]::Match(
      $segment,
      '(?m)^[ \t]*(?:public\s+|private\s+|protected\s+)?(?:async\s+)?(?<name>[A-Za-z_][A-Za-z0-9_]*)\s*\('
    )
    $rolesExpression = (
      [regex]::Matches(
        $segment,
        '@Roles\s*\((?<roles>.*?)\)',
        [Text.RegularExpressions.RegexOptions]::Singleline
      ) |
        ForEach-Object { $_.Groups['roles'].Value }
    ) -join ','
    $route = Join-Route $controllerPath $match.Groups['path'].Value
    $owner = Get-Owner $relative $route

    $backendRoutes.Add([ordered]@{
      id = "$($match.Groups['verb'].Value.ToUpperInvariant()) $route"
      verb = $match.Groups['verb'].Value.ToUpperInvariant()
      route = $route
      controller = if ($methodMatch.Success) { $methodMatch.Groups['name'].Value } else { '<unresolved>' }
      roles = @(Get-RoleValues $rolesExpression)
      owner = $owner
      status = 'compatibility-facade'
      file = $relative
      line = Get-LineNumber $text $match.Index
    })
  }
}

$guardSites = [Collections.Generic.List[object]]::new()
$policySites = [Collections.Generic.List[object]]::new()

foreach ($file in $serverFiles) {
  $relative = Get-RelativePath $file.FullName
  $text = [IO.File]::ReadAllText($file.FullName)

  foreach ($match in [regex]::Matches(
    $text,
    '@Roles\s*\((?<roles>.*?)\)',
    [Text.RegularExpressions.RegexOptions]::Singleline
  )) {
    $guardSites.Add([ordered]@{
      kind = '@Roles'
      expression = Normalize-Snippet $match.Value
      roles = @(Get-RoleValues $match.Groups['roles'].Value)
      owner = Get-Owner $relative $match.Value
      status = 'legacy-review-required'
      file = $relative
      line = Get-LineNumber $text $match.Index
    })
  }

  foreach ($match in [regex]::Matches(
    $text,
    '(?<receiver>(?:this\.)?(?:[A-Za-z_][A-Za-z0-9_]*)?policy)\.(?<call>assert[A-Za-z0-9_]+|can[A-Za-z0-9_]+)\s*\(',
    [Text.RegularExpressions.RegexOptions]::IgnoreCase
  )) {
    $policySites.Add([ordered]@{
      kind = 'policy-call'
      receiver = $match.Groups['receiver'].Value
      call = $match.Groups['call'].Value
      owner = Get-Owner $relative $match.Groups['call'].Value
      status = 'policy-protected'
      file = $relative
      line = Get-LineNumber $text $match.Index
    })
  }
}

$dtoFields = [Collections.Generic.List[object]]::new()

foreach ($file in $dtoFiles) {
  $relative = Get-RelativePath $file.FullName
  $lines = [IO.File]::ReadAllLines($file.FullName)
  $currentClass = $null
  $braceDepth = 0
  $decorators = [Collections.Generic.List[string]]::new()

  for ($lineIndex = 0; $lineIndex -lt $lines.Length; $lineIndex++) {
    $line = $lines[$lineIndex]
    if ($null -eq $currentClass) {
      $classMatch = [regex]::Match(
        $line,
        '^\s*export\s+class\s+(?<name>[A-Za-z_][A-Za-z0-9_]*)'
      )
      if ($classMatch.Success) {
        $currentClass = $classMatch.Groups['name'].Value
        $braceDepth = (
          [regex]::Matches($line, '\{').Count -
          [regex]::Matches($line, '\}').Count
        )
      }
      continue
    }

    $trimmed = $line.Trim()
    if ($trimmed.StartsWith('@')) {
      $decoratorMatch = [regex]::Match($trimmed, '^@(?<name>[A-Za-z_][A-Za-z0-9_]*)')
      if ($decoratorMatch.Success) {
        $decorators.Add($decoratorMatch.Groups['name'].Value)
      }
    }

    $propertyMatch = [regex]::Match(
      $line,
      '^\s*(?:(?:public|private|protected)\s+)?(?:readonly\s+)?(?<field>[A-Za-z_][A-Za-z0-9_]*)[!?]?\s*:\s*(?<type>[^;=]+)[;=]'
    )
    if ($propertyMatch.Success) {
      $field = $propertyMatch.Groups['field'].Value
      $dtoFields.Add([ordered]@{
        dto = $currentClass
        field = $field
        type = Normalize-Snippet $propertyMatch.Groups['type'].Value
        decorators = @($decorators | Sort-Object -Unique)
        owner = Get-Owner $relative "$currentClass $field"
        status = 'current-contract'
        file = $relative
        line = $lineIndex + 1
      })
      $decorators.Clear()
    }

    $braceDepth += (
      [regex]::Matches($line, '\{').Count -
      [regex]::Matches($line, '\}').Count
    )
    if ($braceDepth -le 0) {
      $currentClass = $null
      $braceDepth = 0
      $decorators.Clear()
    }
  }
}

$flutterRoleChecks = [Collections.Generic.List[object]]::new()
$flutterNavigationSources = [Collections.Generic.List[object]]::new()
$flutterScheduleEntries = [Collections.Generic.List[object]]::new()

$rolePattern = '(?i)(?:\brole\b.*(?:==|!=|\bswitch\b|\.contains\s*\()|crmHas[A-Za-z0-9_]*|canAssignRole|showInboxFolders|visibleTabs|has[A-Za-z0-9_]*Access)'
$navigationPattern = '(?:context\.(?:go|push|replace|goNamed|pushNamed)\s*\(|GoRoute\s*\(|GoRouter\s*\(|Navigator(?:\.of)?|navigateTo\s*\(|NavigationRequest|navigationProvider)'
$schedulePattern = '(?:createLesson|updateLesson|deleteLesson|getLessons|saveLessonAttendance|getLessonAttendance|createScheduleSeries|updateScheduleSeries|rescheduleLesson|cancelLesson)\s*\('

foreach ($file in $flutterFiles) {
  $relative = Get-RelativePath $file.FullName
  $lines = [IO.File]::ReadAllLines($file.FullName)
  for ($lineIndex = 0; $lineIndex -lt $lines.Length; $lineIndex++) {
    $line = $lines[$lineIndex]
    $trimmed = $line.Trim()
    if ($trimmed.StartsWith('//')) { continue }

    if ($line -match $rolePattern) {
      $flutterRoleChecks.Add([ordered]@{
        kind = 'role-check'
        expression = Normalize-Snippet $line
        owner = 'SYS-APP'
        status = 'legacy-review-required'
        file = $relative
        line = $lineIndex + 1
      })
    }
    if ($line -match $navigationPattern) {
      $flutterNavigationSources.Add([ordered]@{
        kind = 'navigation-source'
        expression = Normalize-Snippet $line
        owner = 'SYS-APP'
        status = 'workspace-migration-pending'
        file = $relative
        line = $lineIndex + 1
      })
    }
    if ($line -match $schedulePattern) {
      $flutterScheduleEntries.Add([ordered]@{
        kind = 'flutter-call'
        expression = Normalize-Snippet $line
        owner = 'SYS-SCHEDULE'
        status = 'legacy-unified-service-pending'
        file = $relative
        line = $lineIndex + 1
      })
    }
  }
}

$scheduleEntries = [Collections.Generic.List[object]]::new()
$attendanceMutations = [Collections.Generic.List[object]]::new()
$financeWrites = [Collections.Generic.List[object]]::new()
$writeVerbs = @('POST', 'PATCH', 'PUT', 'DELETE')

foreach ($route in $backendRoutes) {
  $routeSubject = "$($route.route) $($route.file)"
  if ($routeSubject -match '(?i)lesson|schedule|attendance') {
    $scheduleEntries.Add([ordered]@{
      kind = 'backend-route'
      expression = "$($route.verb) $($route.route)"
      owner = 'SYS-SCHEDULE'
      status = 'legacy-unified-service-pending'
      file = $route.file
      line = $route.line
    })
  }
  if (
    $writeVerbs -contains $route.verb -and
    $routeSubject -match '(?i)attendance'
  ) {
    $attendanceMutations.Add([ordered]@{
      kind = 'backend-route'
      expression = "$($route.verb) $($route.route)"
      owner = 'SYS-SCHEDULE'
      status = 'removal-required'
      file = $route.file
      line = $route.line
    })
  }
  if (
    $writeVerbs -contains $route.verb -and
    $routeSubject -match '(?i)payment|expense|subscription|payout|rate|adjustment|transfer'
  ) {
    $financeWrites.Add([ordered]@{
      kind = 'backend-route'
      expression = "$($route.verb) $($route.route)"
      owner = 'SYS-COMMERCE'
      status = 'commerce-migration-pending'
      file = $route.file
      line = $route.line
    })
  }
}

foreach ($entry in $flutterScheduleEntries) {
  $scheduleEntries.Add($entry)
  if ($entry.expression -match '(?i)saveLessonAttendance') {
    $attendanceMutations.Add([ordered]@{
      kind = 'flutter-call'
      expression = $entry.expression
      owner = 'SYS-APP'
      status = 'removal-required'
      file = $entry.file
      line = $entry.line
    })
  }
}

foreach ($file in $serverFiles) {
  $relative = Get-RelativePath $file.FullName
  $text = [IO.File]::ReadAllText($file.FullName)

  foreach ($match in [regex]::Matches(
    $text,
    '(?is)\b(?:insert\s+into|update|delete\s+from)\s+app\.lesson_attendance\b'
  )) {
    $attendanceMutations.Add([ordered]@{
      kind = 'sql-mutation'
      expression = Normalize-Snippet $match.Value
      owner = 'SYS-SCHEDULE'
      status = 'removal-required'
      file = $relative
      line = Get-LineNumber $text $match.Index
    })
  }

  foreach ($match in [regex]::Matches(
    $text,
    '(?is)\b(?:insert\s+into|update|delete\s+from)\s+app\.(?:payments|expenses|subscriptions|teacher_payouts|teacher_rates|account_adjustments|account_transfers)\b'
  )) {
    $financeWrites.Add([ordered]@{
      kind = 'sql-mutation'
      expression = Normalize-Snippet $match.Value
      owner = 'SYS-COMMERCE'
      status = 'commerce-migration-pending'
      file = $relative
      line = Get-LineNumber $text $match.Index
    })
  }
}

$targetTableNames = @('lessons', 'subscriptions', 'payments', 'tasks', 'users')
$schemaState = [ordered]@{}
foreach ($tableName in $targetTableNames) {
  $schemaState[$tableName] = @{
    columns = [ordered]@{}
    indexes = [ordered]@{}
    events = [Collections.Generic.List[object]]::new()
  }
}

foreach ($file in $migrationFiles) {
  $relative = Get-RelativePath $file.FullName
  $text = [IO.File]::ReadAllText($file.FullName)

  foreach ($match in [regex]::Matches(
    $text,
    '(?is)create\s+table\s+if\s+not\s+exists\s+app\.(?<table>lessons|subscriptions|payments|tasks|users)\s*\((?<body>.*?)\)\s*;'
  )) {
    $table = $match.Groups['table'].Value.ToLowerInvariant()
    $body = $match.Groups['body'].Value
    foreach ($line in ($body -split "`n")) {
      $candidate = $line.Trim().TrimEnd(',')
      if ($candidate -match '^(?i:constraint|primary\s+key|foreign\s+key|unique|check)\b') {
        continue
      }
      $columnMatch = [regex]::Match(
        $candidate,
        '^(?<column>[a-z_][a-z0-9_]*)\s+(?<definition>.+)$',
        [Text.RegularExpressions.RegexOptions]::IgnoreCase
      )
      if ($columnMatch.Success) {
        $column = $columnMatch.Groups['column'].Value.ToLowerInvariant()
        $schemaState[$table].columns[$column] = [ordered]@{
          name = $column
          definition = Normalize-Snippet $columnMatch.Groups['definition'].Value
          source = $relative
        }
      }
    }
    $schemaState[$table].events.Add([ordered]@{
      action = 'create-table'
      source = $relative
      line = Get-LineNumber $text $match.Index
    })
  }

  foreach ($match in [regex]::Matches(
    $text,
    '(?is)alter\s+table\s+(?:if\s+exists\s+)?app\.(?<table>lessons|subscriptions|payments|tasks|users)\s+(?<operations>.*?);'
  )) {
    $table = $match.Groups['table'].Value.ToLowerInvariant()
    $operations = Normalize-Snippet $match.Groups['operations'].Value

    foreach ($addMatch in [regex]::Matches(
      $operations,
      '(?is)\badd\s+column\s+(?:if\s+not\s+exists\s+)?(?<column>[a-z_][a-z0-9_]*)\s+(?<definition>.*?)(?=(?:,\s*)?\b(?:add|drop|alter|rename)\s+column\b|$)'
    )) {
      $column = $addMatch.Groups['column'].Value.ToLowerInvariant()
      $schemaState[$table].columns[$column] = [ordered]@{
        name = $column
        definition = (Normalize-Snippet $addMatch.Groups['definition'].Value).TrimEnd(',')
        source = $relative
      }
      $schemaState[$table].events.Add([ordered]@{
        action = 'add-column'
        column = $column
        source = $relative
        line = Get-LineNumber $text $match.Index
      })
    }

    foreach ($dropMatch in [regex]::Matches(
      $operations,
      '(?i)\bdrop\s+column\s+(?:if\s+exists\s+)?(?<column>[a-z_][a-z0-9_]*)'
    )) {
      $column = $dropMatch.Groups['column'].Value.ToLowerInvariant()
      [void]$schemaState[$table].columns.Remove($column)
      $schemaState[$table].events.Add([ordered]@{
        action = 'drop-column'
        column = $column
        source = $relative
        line = Get-LineNumber $text $match.Index
      })
    }

    foreach ($renameMatch in [regex]::Matches(
      $operations,
      '(?i)\brename\s+column\s+(?<from>[a-z_][a-z0-9_]*)\s+to\s+(?<to>[a-z_][a-z0-9_]*)'
    )) {
      $from = $renameMatch.Groups['from'].Value.ToLowerInvariant()
      $to = $renameMatch.Groups['to'].Value.ToLowerInvariant()
      if ($schemaState[$table].columns.Contains($from)) {
        $value = $schemaState[$table].columns[$from]
        [void]$schemaState[$table].columns.Remove($from)
        $value.name = $to
        $value.source = $relative
        $schemaState[$table].columns[$to] = $value
      }
      $schemaState[$table].events.Add([ordered]@{
        action = 'rename-column'
        from = $from
        to = $to
        source = $relative
        line = Get-LineNumber $text $match.Index
      })
    }
  }

  foreach ($match in [regex]::Matches(
    $text,
    '(?is)create\s+(?<unique>unique\s+)?index\s+(?:concurrently\s+)?(?:if\s+not\s+exists\s+)?(?<index>[a-z_][a-z0-9_]*)\s+on\s+(?:app\.)?(?<table>lessons|subscriptions|payments|tasks|users)\b(?<definition>.*?);'
  )) {
    $table = $match.Groups['table'].Value.ToLowerInvariant()
    $indexName = $match.Groups['index'].Value.ToLowerInvariant()
    $schemaState[$table].indexes[$indexName] = [ordered]@{
      name = $indexName
      unique = $match.Groups['unique'].Success
      definition = Normalize-Snippet $match.Value
      source = $relative
    }
    $schemaState[$table].events.Add([ordered]@{
      action = 'create-index'
      index = $indexName
      source = $relative
      line = Get-LineNumber $text $match.Index
    })
  }

  foreach ($match in [regex]::Matches(
    $text,
    '(?is)drop\s+index\s+(?:concurrently\s+)?(?:if\s+exists\s+)?(?<indexes>.*?);'
  )) {
    $indexNames = @(
      [regex]::Matches($match.Groups['indexes'].Value, '(?i)(?:app\.)?(?<index>[a-z_][a-z0-9_]*)') |
        ForEach-Object { $_.Groups['index'].Value.ToLowerInvariant() }
    )
    foreach ($table in $targetTableNames) {
      foreach ($indexName in $indexNames) {
        [void]$schemaState[$table].indexes.Remove($indexName)
      }
    }
  }
}

$schemaInventory = @(
  foreach ($tableName in $targetTableNames) {
    $state = $schemaState[$tableName]
    [ordered]@{
      table = "app.$tableName"
      owner = Get-Owner "server/db/migrations" $tableName
      status = 'current-schema'
      columns = @(
        $state.columns.Keys |
          Sort-Object |
          ForEach-Object { $state.columns[$_] }
      )
      indexes = @(
        $state.indexes.Keys |
          Sort-Object |
          ForEach-Object { $state.indexes[$_] }
      )
      events = @($state.events)
    }
  }
)

$allOwnedItems = @(
  $backendRoutes +
  $guardSites +
  $policySites +
  $dtoFields +
  $flutterRoleChecks +
  $flutterNavigationSources +
  $scheduleEntries +
  $attendanceMutations +
  $financeWrites +
  $schemaInventory
)
$unowned = @($allOwnedItems | Where-Object { $_.owner -notin $systems })
$missingStatus = @(
  $allOwnedItems |
    Where-Object {
      -not $_.Contains('status') -or [string]::IsNullOrWhiteSpace($_.status)
    }
)

$validationErrors = [Collections.Generic.List[string]]::new()
if ($backendRoutes.Count -ne $routeDecoratorCount) {
  $validationErrors.Add(
    "Route coverage mismatch: parsed=$($backendRoutes.Count), decorators=$routeDecoratorCount"
  )
}
if ($backendRoutes.Count -eq 0) { $validationErrors.Add('No backend routes found') }
if ($guardSites.Count -eq 0) { $validationErrors.Add('No @Roles sites found') }
if ($policySites.Count -eq 0) { $validationErrors.Add('No policy calls found') }
if ($dtoFields.Count -eq 0) { $validationErrors.Add('No DTO fields found') }
if ($flutterRoleChecks.Count -eq 0) { $validationErrors.Add('No Flutter role checks found') }
if ($flutterNavigationSources.Count -eq 0) { $validationErrors.Add('No Flutter navigation sources found') }
if ($scheduleEntries.Count -eq 0) { $validationErrors.Add('No schedule entry points found') }
if ($attendanceMutations.Count -gt 0) {
  $validationErrors.Add(
    "$($attendanceMutations.Count) active attendance mutations remain"
  )
}
if ($financeWrites.Count -eq 0) { $validationErrors.Add('No finance writes found') }
if ($unowned.Count -gt 0) { $validationErrors.Add("$($unowned.Count) items have no v4 owner") }
if ($missingStatus.Count -gt 0) { $validationErrors.Add("$($missingStatus.Count) items have no status") }

foreach ($table in $schemaInventory) {
  if ($table.columns.Count -eq 0) {
    $validationErrors.Add("$($table.table) has no parsed columns")
  }
}

$summary = [ordered]@{
  backend_routes = $backendRoutes.Count
  role_guards = $guardSites.Count
  policy_calls = $policySites.Count
  dto_fields = $dtoFields.Count
  flutter_role_checks = $flutterRoleChecks.Count
  flutter_navigation_sources = $flutterNavigationSources.Count
  schedule_entry_points = $scheduleEntries.Count
  attendance_mutations = $attendanceMutations.Count
  finance_writes = $financeWrites.Count
  schema_tables = $schemaInventory.Count
  unowned_items = $unowned.Count
  missing_status_items = $missingStatus.Count
}

$inventory = [ordered]@{
  schema_version = 1
  task = 'T8.1.2'
  source_digest_sha256 = Get-SourceDigest $digestFiles
  source_file_count = $digestFiles.Count
  systems = $systems
  summary = $summary
  backend_routes = @($backendRoutes | Sort-Object file, line, verb, route)
  role_guards = @($guardSites | Sort-Object file, line)
  policy_calls = @($policySites | Sort-Object file, line, call)
  dto_fields = @($dtoFields | Sort-Object file, line, dto, field)
  flutter_role_checks = @($flutterRoleChecks | Sort-Object file, line)
  flutter_navigation_sources = @($flutterNavigationSources | Sort-Object file, line)
  schedule_entry_points = @($scheduleEntries | Sort-Object file, line, kind)
  attendance_mutations = @($attendanceMutations | Sort-Object file, line, kind)
  finance_writes = @($financeWrites | Sort-Object file, line, kind)
  database_schema = $schemaInventory
  validation = [ordered]@{
    passed = ($validationErrors.Count -eq 0)
    errors = @($validationErrors)
  }
}

$json = ($inventory | ConvertTo-Json -Depth 16).Replace("`r`n", "`n") + "`n"

$markdown = [Text.StringBuilder]::new()
[void]$markdown.AppendLine('# MagicMusicCRM v4 — Current-State Inventory')
[void]$markdown.AppendLine()
[void]$markdown.AppendLine('**Task:** T8.1.2')
[void]$markdown.AppendLine("**Source digest:** ``$($inventory.source_digest_sha256)``")
[void]$markdown.AppendLine("**Validation:** $(if ($inventory.validation.passed) { 'PASS' } else { 'FAIL' })")
[void]$markdown.AppendLine()
[void]$markdown.AppendLine('## Coverage')
[void]$markdown.AppendLine()
[void]$markdown.AppendLine('| Slice | Count |')
[void]$markdown.AppendLine('|---|---:|')
foreach ($entry in $summary.GetEnumerator()) {
  [void]$markdown.AppendLine("| $($entry.Key.Replace('_', ' ')) | $($entry.Value) |")
}
[void]$markdown.AppendLine()
[void]$markdown.AppendLine(
  'Every row in the JSON artifact has one v4 system owner and an explicit migration status. ' +
  'The JSON file is the exhaustive machine-readable inventory; this document is its review summary.'
)
[void]$markdown.AppendLine()
[void]$markdown.AppendLine('## Ownership and status model')
[void]$markdown.AppendLine()
[void]$markdown.AppendLine('| Status | Meaning |')
[void]$markdown.AppendLine('|---|---|')
[void]$markdown.AppendLine('| `compatibility-facade` | Existing public route retained during incremental v4 migration |')
[void]$markdown.AppendLine('| `legacy-review-required` | Role/nav decision must be mapped to capability-based access |')
[void]$markdown.AppendLine('| `policy-protected` | Existing backend policy call is present |')
[void]$markdown.AppendLine('| `current-contract` | Existing DTO field requiring actor-aware contract review |')
[void]$markdown.AppendLine('| `workspace-migration-pending` | Navigation source awaits typed context/workspace migration |')
[void]$markdown.AppendLine('| `legacy-unified-service-pending` | Schedule path awaits the unified constraint/lifecycle service |')
[void]$markdown.AppendLine('| `removal-required` | Attendance write path must leave the active domain |')
[void]$markdown.AppendLine('| `commerce-migration-pending` | Finance write awaits v4 immutable-fact boundaries |')
[void]$markdown.AppendLine('| `current-schema` | Current migration-derived table/column/index state |')
[void]$markdown.AppendLine()
[void]$markdown.AppendLine('## Database inventory')
[void]$markdown.AppendLine()
[void]$markdown.AppendLine('| Table | Owner | Columns | Indexes |')
[void]$markdown.AppendLine('|---|---|---:|---:|')
foreach ($table in $schemaInventory) {
  [void]$markdown.AppendLine(
    "| ``$($table.table)`` | $($table.owner) | $($table.columns.Count) | $($table.indexes.Count) |"
  )
}
[void]$markdown.AppendLine()

foreach ($table in $schemaInventory) {
  [void]$markdown.AppendLine("### ``$($table.table)``")
  [void]$markdown.AppendLine()
  [void]$markdown.AppendLine('Columns: ' + (
    @($table.columns | ForEach-Object { "``$($_.name)``" }) -join ', '
  ))
  [void]$markdown.AppendLine()
  [void]$markdown.AppendLine('Indexes: ' + (
    @($table.indexes | ForEach-Object { "``$($_.name)``" }) -join ', '
  ))
  [void]$markdown.AppendLine()
}

[void]$markdown.AppendLine('## Active attendance mutations')
[void]$markdown.AppendLine()
[void]$markdown.AppendLine('| Kind | Entry | Location | Status |')
[void]$markdown.AppendLine('|---|---|---|---|')
foreach ($item in $attendanceMutations) {
  [void]$markdown.AppendLine(
    "| $($item.kind) | $(Escape-Markdown $item.expression) | ``$($item.file):$($item.line)`` | $($item.status) |"
  )
}
if ($attendanceMutations.Count -eq 0) {
  [void]$markdown.AppendLine('| — | No active attendance mutations | — | PASS |')
}
[void]$markdown.AppendLine()
[void]$markdown.AppendLine('## Active finance writes')
[void]$markdown.AppendLine()
[void]$markdown.AppendLine('| Kind | Entry | Location | Status |')
[void]$markdown.AppendLine('|---|---|---|---|')
foreach ($item in $financeWrites) {
  [void]$markdown.AppendLine(
    "| $($item.kind) | $(Escape-Markdown $item.expression) | ``$($item.file):$($item.line)`` | $($item.status) |"
  )
}
[void]$markdown.AppendLine()
[void]$markdown.AppendLine('## Verification')
[void]$markdown.AppendLine()
[void]$markdown.AppendLine('```powershell')
[void]$markdown.AppendLine('pwsh -File scripts/v4_inventory.ps1 -Check')
[void]$markdown.AppendLine('```')
[void]$markdown.AppendLine()
[void]$markdown.AppendLine(
  'The check regenerates both artifacts from source, validates route/category/schema coverage, ' +
  'and fails if either checked-in artifact is stale.'
)

$markdownText = $markdown.ToString().Replace("`r`n", "`n")

if ($Check) {
  if (-not (Test-Path -LiteralPath $jsonPath)) {
    throw "Missing inventory artifact: $(Get-RelativePath $jsonPath)"
  }
  if (-not (Test-Path -LiteralPath $markdownPath)) {
    throw "Missing inventory artifact: $(Get-RelativePath $markdownPath)"
  }
  if (-not $inventory.validation.passed) {
    throw "Inventory validation failed: $($inventory.validation.errors -join '; ')"
  }

  $existingJson = [IO.File]::ReadAllText($jsonPath).Replace("`r`n", "`n")
  $existingMarkdown = [IO.File]::ReadAllText($markdownPath).Replace("`r`n", "`n")
  if ($existingJson -ne $json) {
    throw 'docs/audits/v4-current-state-inventory.json is stale; regenerate without -Check'
  }
  if ($existingMarkdown -ne $markdownText) {
    throw 'docs/audits/v4-current-state-inventory.md is stale; regenerate without -Check'
  }

  Write-Output (
    "v4 inventory PASS: routes=$($summary.backend_routes), " +
    "dtoFields=$($summary.dto_fields), schemaTables=$($summary.schema_tables), " +
    "unowned=$($summary.unowned_items)"
  )
  exit 0
}

if (-not $inventory.validation.passed) {
  throw "Inventory validation failed: $($inventory.validation.errors -join '; ')"
}

$auditDirectory = Split-Path -Parent $jsonPath
if (-not (Test-Path -LiteralPath $auditDirectory)) {
  [void](New-Item -ItemType Directory -Path $auditDirectory)
}
[IO.File]::WriteAllText($jsonPath, $json, [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($markdownPath, $markdownText, [Text.UTF8Encoding]::new($false))
Write-Output "Wrote $(Get-RelativePath $jsonPath)"
Write-Output "Wrote $(Get-RelativePath $markdownPath)"
Write-Output (
  "v4 inventory generated: routes=$($summary.backend_routes), " +
  "dtoFields=$($summary.dto_fields), schemaTables=$($summary.schema_tables)"
)
