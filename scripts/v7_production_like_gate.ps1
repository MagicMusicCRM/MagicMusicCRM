[CmdletBinding()]
param(
  [string]$DatabaseName = "magiccrm_v7_prodlike_gate",
  [int]$Port = 3107,
  [string]$ExpectedMigrationId = "0134_canonical_clients"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if ($DatabaseName -notmatch '^magiccrm_v7_prodlike_[a-z0-9_]+$') {
  throw "The production-like gate only accepts a dedicated magiccrm_v7_prodlike_* database."
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$serverRoot = Join-Path $repoRoot "server"
$postgresBin = Join-Path $env:LOCALAPPDATA "MagicMusicCRMToolchain/postgresql-17/bin"
$psql = Join-Path $postgresBin "psql.exe"
$createDb = Join-Path $postgresBin "createdb.exe"
$dropDb = Join-Path $postgresBin "dropdb.exe"
$adminUrl = "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/postgres"
$databaseUrl = "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/$DatabaseName"

foreach ($tool in @($psql, $createDb, $dropDb)) {
  if (-not (Test-Path -LiteralPath $tool)) {
    throw "Required PostgreSQL tool is missing: $tool"
  }
}

function Invoke-NpmStep {
  param([Parameter(Mandatory)][string[]]$Arguments)

  $output = & npm --prefix $serverRoot @Arguments 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "npm $($Arguments -join ' ') failed:`n$($output -join "`n")"
  }
  return $output
}

$existing = (& $psql $adminUrl -At -v ON_ERROR_STOP=1 -c (
    "select count(*) from pg_database where datname='$DatabaseName'"
  )).Trim()
if ($existing -eq "1") {
  & $dropDb --maintenance-db=$adminUrl --force $DatabaseName
  if ($LASTEXITCODE -ne 0) {
    throw "Unable to remove the stale production-like database."
  }
}

& $createDb --maintenance-db=$adminUrl --owner=magiccrm_owner $DatabaseName
if ($LASTEXITCODE -ne 0) {
  throw "Unable to create the production-like database."
}

$apiProcess = $null
try {
  $env:DATABASE_URL = $databaseUrl
  $env:MIGRATION_DATABASE_URL = $databaseUrl
  Invoke-NpmStep @("run", "db:migrate") | Out-Null

  $reconcileOutput = Invoke-NpmStep @("run", "v7:reconcile")
  $reconcileLine = $reconcileOutput |
    Where-Object { $_ -match '^\{' } |
    Select-Object -Last 1
  if (-not $reconcileLine) {
    throw "V7 reconciliation did not return JSON."
  }
  $reconciliation = $reconcileLine | ConvertFrom-Json
  if (@($reconciliation.issues).Count -ne 0) {
    throw "V7 reconciliation returned integrity issues."
  }

  $env:NODE_ENV = "production"
  $env:PORT = $Port.ToString()
  $env:JWT_ACCESS_SECRET =
    [guid]::NewGuid().ToString("N") + [guid]::NewGuid().ToString("N")
  $env:V4_ACCESS_MODE = "v4"
  $env:V4_ACCESS_KILL_SWITCH = "false"
  $env:V4_SCHEDULE_MODE = "shadow"
  $env:V4_SCHEDULE_KILL_SWITCH = "false"
  $env:V4_PARITY_UNEXPLAINED_DIFFS = "0"
  $env:PLATFORM_OUTBOX_WORKER_ENABLED = "false"
  $env:LESSON_COMPLETION_WORKER_ENABLED = "false"

  $invalidProcess = Start-Process `
    -FilePath "node" `
    -ArgumentList @("dist/main.js") `
    -WorkingDirectory $serverRoot `
    -WindowStyle Hidden `
    -PassThru
  if (-not $invalidProcess.WaitForExit(15000)) {
    Stop-Process -Id $invalidProcess.Id -Force
    throw "Fail-closed check failed: invalid production flags started the API."
  }
  if ($invalidProcess.ExitCode -eq 0) {
    throw "Fail-closed check failed: invalid production flags exited successfully."
  }
  Write-Output "Fail-closed invalid configuration: PASS"

  $env:V4_SCHEDULE_MODE = "v4"
  $apiProcess = Start-Process `
    -FilePath "node" `
    -ArgumentList @("dist/main.js") `
    -WorkingDirectory $serverRoot `
    -WindowStyle Hidden `
    -PassThru

  $ready = $null
  for ($attempt = 0; $attempt -lt 30; $attempt++) {
    if ($apiProcess.HasExited) {
      throw "Production-like API exited early with code $($apiProcess.ExitCode)."
    }
    try {
      $ready = Invoke-RestMethod `
        -Uri "http://127.0.0.1:$Port/api/health/ready" `
        -TimeoutSec 2
      break
    } catch {
      Start-Sleep -Milliseconds 500
    }
  }
  if ($null -eq $ready) {
    throw "Production-like readiness endpoint did not become available."
  }
  if (
    $ready.status -ne "ok" -or
    $ready.latestMigrationId -ne $ExpectedMigrationId
  ) {
    throw "Production-like readiness returned an unexpected status or migration."
  }
  foreach ($check in $ready.checks.PSObject.Properties) {
    if ($check.Value -ne "ok") {
      throw "Production-like readiness check $($check.Name)=$($check.Value)."
    }
  }
  foreach ($domain in @($ready.v4Rollout)) {
    if (
      $domain.effectivePath -ne "v4" -or
      -not $domain.enableAllowed -or
      $domain.killSwitch
    ) {
      throw "Production-like rollout is not enabled for $($domain.domain)."
    }
  }

  $live = Invoke-RestMethod `
    -Uri "http://127.0.0.1:$Port/api/health/live" `
    -TimeoutSec 2
  if ($live.status -ne "ok") {
    throw "Production-like liveness failed."
  }

  $rollout = @($ready.v4Rollout) |
    ForEach-Object { "$($_.domain):$($_.effectivePath)" }
  Write-Output (
    "Production-like live/ready: PASS; migration=$($ready.latestMigrationId); " +
    "rollout=$($rollout -join ',')"
  )
  Write-Output "V7 reconciliation: PASS (0 issues)"
} finally {
  if ($apiProcess -and -not $apiProcess.HasExited) {
    Stop-Process -Id $apiProcess.Id -Force
    $apiProcess.WaitForExit()
  }
  & $dropDb --maintenance-db=$adminUrl --force $DatabaseName
  if ($LASTEXITCODE -ne 0) {
    throw "Unable to remove the production-like database."
  }
  Write-Output "Removed temporary database: $DatabaseName"
}
