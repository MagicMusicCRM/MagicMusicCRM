param(
  [string]$SourceDir = "_archive/backups/hollihop_backup_2026-03-14T15-42-12",
  [string]$EvidenceDir = ".supergoal/hollihop-crm-import-adaptation-loading-ux-Guw3IO/evidence",
  [string]$BackupEvidencePath = "",
  [string[]]$EnvFiles = @("server/.env", "infra/staging/.env", "infra/staging/.backup.env"),
  [switch]$SkipMigrate,
  [switch]$UseLiveApi,
  [switch]$NoEnvFiles,
  [switch]$CheckOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$serverDir = Join-Path $repoRoot "server"
$timestamp = Get-Date -Format "yyyyMMddTHHmmss"

if ([System.IO.Path]::IsPathRooted($EvidenceDir)) {
  $evidenceRoot = [System.IO.Path]::GetFullPath($EvidenceDir)
} else {
  $evidenceRoot = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $EvidenceDir))
}

function Write-Step {
  param([string]$Message)
  Write-Host "==> $Message"
}

function Resolve-ProjectPath {
  param([string]$PathValue)
  if ([System.IO.Path]::IsPathRooted($PathValue)) {
    return [System.IO.Path]::GetFullPath($PathValue)
  }
  return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $PathValue))
}

function Get-DatabaseEnvName {
  if (-not [string]::IsNullOrWhiteSpace($env:MIGRATION_DATABASE_URL)) {
    return "MIGRATION_DATABASE_URL"
  }
  if (-not [string]::IsNullOrWhiteSpace($env:DATABASE_URL)) {
    return "DATABASE_URL"
  }
  return $null
}

function Convert-DotEnvValue {
  param([string]$Value)

  $trimmed = $Value.Trim()
  if ($trimmed.Length -ge 2) {
    $first = $trimmed.Substring(0, 1)
    $last = $trimmed.Substring($trimmed.Length - 1, 1)
    if (($first -eq '"' -and $last -eq '"') -or ($first -eq "'" -and $last -eq "'")) {
      return $trimmed.Substring(1, $trimmed.Length - 2)
    }
  }

  return $trimmed
}

function Import-DotEnvFile {
  param([string]$PathValue)

  $path = Resolve-ProjectPath $PathValue
  $loaded = New-Object 'System.Collections.Generic.List[string]'
  $skippedExisting = New-Object 'System.Collections.Generic.List[string]'

  if (-not (Test-Path -LiteralPath $path)) {
    return [pscustomobject]@{
      Path = $path
      Exists = $false
      Loaded = @()
      SkippedExisting = @()
    }
  }

  foreach ($line in Get-Content -LiteralPath $path) {
    $trimmed = $line.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith("#")) {
      continue
    }

    if ($trimmed -notmatch '^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') {
      continue
    }

    $name = $matches[1]
    $value = Convert-DotEnvValue -Value $matches[2]
    $current = Get-Item -Path "Env:$name" -ErrorAction SilentlyContinue
    if ($current -and -not [string]::IsNullOrWhiteSpace($current.Value)) {
      [void]$skippedExisting.Add($name)
      continue
    }

    Set-ProcessEnv -Name $name -Value $value
    [void]$loaded.Add($name)
  }

  return [pscustomobject]@{
    Path = $path
    Exists = $true
    Loaded = [string[]]$loaded
    SkippedExisting = [string[]]$skippedExisting
  }
}

function Assert-NoSecretLeak {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    return
  }

  $leakPatterns = @(
    "postgres(?:ql)?://",
    "authkey=",
    "HOLLIHOP_AUTH_KEY\s*=",
    "MIGRATION_DATABASE_URL\s*=",
    "DATABASE_URL\s*=",
    "PASSWORD\s*=",
    "TOKEN\s*=",
    "SECRET\s*="
  )

  $matches = Select-String -LiteralPath $Path -Pattern $leakPatterns -AllMatches -ErrorAction SilentlyContinue
  if ($matches) {
    throw "Potential secret-bearing value was written to $Path. Review and remove the log before sharing."
  }
}

function Invoke-LoggedCommand {
  param(
    [string]$Name,
    [string]$LogPath,
    [string]$WorkingDirectory,
    [string[]]$Command
  )

  Write-Step $Name
  $executable = $Command[0]
  $arguments = @()
  if ($Command.Length -gt 1) {
    $arguments = $Command[1..($Command.Length - 1)]
  }

  $previousLocation = (Get-Location).Path
  try {
    Set-Location $WorkingDirectory
    $output = & $executable @arguments 2>&1
    $exitCode = $LASTEXITCODE
  } finally {
    Set-Location $previousLocation
  }

  $output | Tee-Object -FilePath $LogPath
  Assert-NoSecretLeak -Path $LogPath

  if ($exitCode -ne 0) {
    throw "$Name failed with exit code $exitCode. See $LogPath"
  }
}

function Set-ProcessEnv {
  param(
    [string]$Name,
    [string]$Value
  )
  [System.Environment]::SetEnvironmentVariable($Name, $Value, "Process")
}

function Remove-ProcessEnv {
  param([string]$Name)
  [System.Environment]::SetEnvironmentVariable($Name, $null, "Process")
}

New-Item -ItemType Directory -Force -Path $evidenceRoot | Out-Null
Set-Location $repoRoot

Write-Step "HolliHop staging dry-run helper"
Write-Host "Repo: $repoRoot"
Write-Host "Evidence: $evidenceRoot"

if (-not (Test-Path -LiteralPath (Join-Path $serverDir "package.json"))) {
  throw "server/package.json was not found. Run this script from the MagicMusicCRM repository."
}

$npm = Get-Command npm -ErrorAction Stop
Write-Host "npm: $($npm.Source)"

if (-not $NoEnvFiles) {
  foreach ($envFile in $EnvFiles) {
    $result = Import-DotEnvFile -PathValue $envFile
    if ($result.Exists) {
      Write-Host ("Env file loaded: {0} ({1} keys loaded, {2} process values kept, values hidden)" -f $envFile, @($result.Loaded).Count, @($result.SkippedExisting).Count)
    }
  }
} else {
  Write-Host "Env file loading: skipped by -NoEnvFiles"
}

if ($UseLiveApi) {
  if ([string]::IsNullOrWhiteSpace($env:HOLLIHOP_AUTH_KEY)) {
    throw "HOLLIHOP_AUTH_KEY must be present as a transient process secret when -UseLiveApi is set."
  }
  Write-Host "Source: live HolliHop API (key present, value hidden)"
} else {
  $sourcePath = Resolve-ProjectPath $SourceDir
  if (-not (Test-Path -LiteralPath $sourcePath)) {
    throw "SourceDir was not found: $sourcePath"
  }
  Write-Host "Source: local archive $sourcePath"
}

if ($CheckOnly) {
  Write-Step "CheckOnly completed"
  Write-Host "The script is loadable. Backup, DB, migration and importer steps were intentionally skipped."
  exit 0
}

$currentImportMode = $env:HOLLIHOP_IMPORT_MODE
if ($null -ne $currentImportMode -and $currentImportMode.Trim().ToLowerInvariant() -eq "apply") {
  throw "Refusing to continue while HOLLIHOP_IMPORT_MODE=apply is already set. Clear it before running a guarded dry-run."
}

$dbEnvName = Get-DatabaseEnvName
if (-not $dbEnvName) {
  throw "MIGRATION_DATABASE_URL or DATABASE_URL must be present as a transient process secret for DB-backed dry-run."
}
Write-Host "Database env: $dbEnvName is present (value hidden)"

if ([string]::IsNullOrWhiteSpace($BackupEvidencePath)) {
  throw "BackupEvidencePath is required before DB-backed HolliHop dry-run because audit/source rows and migration metadata can be written."
}

$backupPath = Resolve-ProjectPath $BackupEvidencePath
if (-not (Test-Path -LiteralPath $backupPath)) {
  throw "BackupEvidencePath was not found: $backupPath"
}
Write-Host "Backup evidence: $backupPath"

$summaryPath = Join-Path $evidenceRoot "hollihop-staging-dry-run-summary-$timestamp.md"
@(
  "# HolliHop Staging Dry-Run Summary"
  ""
  "- Timestamp: ``$timestamp``"
  "- Mode: ``dry_run``"
  "- Database env: ``$dbEnvName`` present, value hidden"
  "- Backup evidence: ``$backupPath``"
  "- Source: ``$(if ($UseLiveApi) { 'live-api' } else { $sourcePath })``"
  "- Report directory: ``$evidenceRoot``"
) | Set-Content -LiteralPath $summaryPath

$envNames = @(
  "HOLLIHOP_IMPORT_MODE",
  "HOLLIHOP_IMPORT_VALIDATE_ONLY",
  "HOLLIHOP_IMPORT_REPORT_DIR",
  "HOLLIHOP_IMPORT_SOURCE_DIR"
)
$previousEnv = @{}
foreach ($name in $envNames) {
  $item = Get-Item -Path "Env:$name" -ErrorAction SilentlyContinue
  $previousEnv[$name] = if ($item) { $item.Value } else { $null }
}

try {
  Set-ProcessEnv -Name "HOLLIHOP_IMPORT_MODE" -Value "dry_run"
  Set-ProcessEnv -Name "HOLLIHOP_IMPORT_VALIDATE_ONLY" -Value "false"
  Set-ProcessEnv -Name "HOLLIHOP_IMPORT_REPORT_DIR" -Value $evidenceRoot
  if ($UseLiveApi) {
    Remove-ProcessEnv -Name "HOLLIHOP_IMPORT_SOURCE_DIR"
  } else {
    Set-ProcessEnv -Name "HOLLIHOP_IMPORT_SOURCE_DIR" -Value $sourcePath
  }

  if (-not $SkipMigrate) {
    Invoke-LoggedCommand `
      -Name "Run DB migrations" `
      -LogPath (Join-Path $evidenceRoot "hollihop-staging-dry-run-migrate-$timestamp.log") `
      -WorkingDirectory $serverDir `
      -Command @("npm", "run", "db:migrate")
  } else {
    Add-Content -LiteralPath $summaryPath -Value "- DB migrate: skipped by -SkipMigrate."
  }

  Invoke-LoggedCommand `
    -Name "Run HolliHop importer dry-run" `
    -LogPath (Join-Path $evidenceRoot "hollihop-staging-dry-run-import-$timestamp.log") `
    -WorkingDirectory $serverDir `
    -Command @("npm", "run", "hollihop:import", "--", "--dry-run")

  $report = Get-ChildItem -LiteralPath $evidenceRoot -Filter "hollihop-import-*.json" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

  if (-not $report) {
    throw "Importer completed but no hollihop-import report was found in $evidenceRoot"
  }

  $reportJson = Get-Content -Raw -LiteralPath $report.FullName | ConvertFrom-Json
  $warningCount = if ($reportJson.warnings) { @($reportJson.warnings).Count } else { 0 }

  Add-Content -LiteralPath $summaryPath -Value "- Report: ``$($report.FullName)``"
  Add-Content -LiteralPath $summaryPath -Value "- Warnings: ``$warningCount``"
  Add-Content -LiteralPath $summaryPath -Value "- Source counts: ``$(($reportJson.sourceCounts | ConvertTo-Json -Compress))``"
  Add-Content -LiteralPath $summaryPath -Value "- Planned counts: ``$(($reportJson.plannedCounts | ConvertTo-Json -Compress))``"
  Add-Content -LiteralPath $summaryPath -Value "- Stored counts: ``$(($reportJson.storedCounts | ConvertTo-Json -Compress))``"

  Assert-NoSecretLeak -Path $summaryPath

  Write-Step "Dry-run helper completed"
  Write-Host "Summary: $summaryPath"
  Write-Host "Report: $($report.FullName)"
  Write-Host "Review warnings, source counts, planned counts, stored counts and duplicate summary before any apply."
} finally {
  foreach ($name in $envNames) {
    if ($null -eq $previousEnv[$name]) {
      Remove-ProcessEnv -Name $name
    } else {
      Set-ProcessEnv -Name $name -Value $previousEnv[$name]
    }
  }
}
