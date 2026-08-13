[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$ImageTag,
  [string]$DatabaseName = "magiccrm_v7_prodlike_image",
  [int]$HealthyPort = 3108,
  [int]$DegradedPort = 3109,
  [Parameter(Mandatory)][string]$ExpectedRevision,
  [string]$ExpectedMigrationId = "0134_canonical_clients"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if ($DatabaseName -notmatch '^magiccrm_v7_prodlike_[a-z0-9_]+$') {
  throw "The image gate only accepts a dedicated magiccrm_v7_prodlike_* database."
}
if ($ImageTag -notmatch '^magicmusiccrm-server:[a-zA-Z0-9_.+-]+$') {
  throw "The image gate only accepts a local magicmusiccrm-server:* image."
}

$postgresBin = Join-Path $env:LOCALAPPDATA "MagicMusicCRMToolchain/postgresql-17/bin"
$psql = Join-Path $postgresBin "psql.exe"
$createDb = Join-Path $postgresBin "createdb.exe"
$dropDb = Join-Path $postgresBin "dropdb.exe"
$adminUrl = "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/postgres"
$degradedDatabaseName = "${DatabaseName}_degraded"
$healthyContainer = "magiccrm-v7-image-gate"
$degradedContainer = "magiccrm-v7-image-gate-degraded"
$invalidContainer = "magiccrm-v7-image-gate-invalid"

foreach ($tool in @($psql, $createDb, $dropDb)) {
  if (-not (Test-Path -LiteralPath $tool)) {
    throw "Required PostgreSQL tool is missing: $tool"
  }
}

function Remove-GateContainer {
  param([Parameter(Mandatory)][string]$Name)

  if ($Name -notmatch '^magiccrm-v7-image-gate(?:-(?:degraded|invalid))?$') {
    throw "Refusing to remove a non-gate container: $Name"
  }
  $exists = ((@(
        & docker container ls -a --filter "name=^/${Name}$" --format '{{.Names}}'
      ) -join "").Trim())
  if ($exists -eq $Name) {
    & docker container rm -f $Name | Out-Null
    if ($LASTEXITCODE -ne 0) {
      throw "Unable to remove gate container $Name."
    }
  }
}

function Remove-GateDatabase {
  param([Parameter(Mandatory)][string]$Name)

  if ($Name -notmatch '^magiccrm_v7_prodlike_[a-z0-9_]+$') {
    throw "Refusing to remove a non-gate database: $Name"
  }
  $exists = ((@(
        & $psql $adminUrl -At -v ON_ERROR_STOP=1 -c (
          "select count(*) from pg_database where datname='$Name'"
        )
      ) -join "").Trim())
  if ($exists -eq "1") {
    & $dropDb --maintenance-db=$adminUrl --force $Name
    if ($LASTEXITCODE -ne 0) {
      throw "Unable to remove gate database $Name."
    }
  }
}

function New-GateDatabase {
  param([Parameter(Mandatory)][string]$Name)

  Remove-GateDatabase $Name
  & $createDb --maintenance-db=$adminUrl --owner=magiccrm_owner $Name
  if ($LASTEXITCODE -ne 0) {
    throw "Unable to create gate database $Name."
  }
}

function New-DatabaseUrl {
  param([Parameter(Mandatory)][string]$Name)

  return "postgresql://magiccrm_owner:magiccrm_owner@host.docker.internal:54329/$Name"
}

function New-EnvironmentArguments {
  param(
    [Parameter(Mandatory)][string]$Url,
    [Parameter(Mandatory)][string]$ScheduleMode
  )

  $jwtSecret = [guid]::NewGuid().ToString("N") + [guid]::NewGuid().ToString("N")
  return @(
    "-e", "NODE_ENV=production",
    "-e", "PORT=3000",
    "-e", "DATABASE_URL=$Url",
    "-e", "MIGRATION_DATABASE_URL=$Url",
    "-e", "JWT_ACCESS_SECRET=$jwtSecret",
    "-e", "V4_ACCESS_MODE=v4",
    "-e", "V4_ACCESS_KILL_SWITCH=false",
    "-e", "V4_SCHEDULE_MODE=$ScheduleMode",
    "-e", "V4_SCHEDULE_KILL_SWITCH=false",
    "-e", "V4_PARITY_UNEXPLAINED_DIFFS=0",
    "-e", "PLATFORM_OUTBOX_WORKER_ENABLED=false",
    "-e", "LESSON_COMPLETION_WORKER_ENABLED=false"
  )
}

function Wait-Live {
  param(
    [Parameter(Mandatory)][int]$Port,
    [Parameter(Mandatory)][string]$Container
  )

  for ($attempt = 0; $attempt -lt 40; $attempt++) {
    $running = (& docker inspect --format '{{.State.Running}}' $Container).Trim()
    if ($running -ne "true") {
      throw "Container $Container exited before liveness became available."
    }
    try {
      $live = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/api/health/live" -TimeoutSec 2
      if ($live.status -eq "ok") {
        return
      }
    } catch {
      Start-Sleep -Milliseconds 500
    }
  }
  throw "Container $Container did not become live."
}

$image = & docker image inspect $ImageTag --format '{{json .}}' | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) {
  throw "Unable to inspect image $ImageTag."
}
if ($image.Config.Labels.'org.opencontainers.image.revision' -ne $ExpectedRevision) {
  throw "Image revision label does not match $ExpectedRevision."
}
if ($image.Config.User -ne "magiccrm") {
  throw "Production image must run as the magiccrm user."
}
$healthCommand = $image.Config.Healthcheck.Test -join " "
if ($healthCommand -notmatch '/api/health/ready') {
  throw "Production image healthcheck does not use the readiness endpoint."
}

$healthyUrl = New-DatabaseUrl $DatabaseName
$degradedUrl = New-DatabaseUrl $degradedDatabaseName

try {
  foreach ($container in @($healthyContainer, $degradedContainer, $invalidContainer)) {
    Remove-GateContainer $container
  }
  New-GateDatabase $DatabaseName
  New-GateDatabase $degradedDatabaseName

  $healthyEnv = New-EnvironmentArguments -Url $healthyUrl -ScheduleMode "v4"
  & docker run --rm --add-host host.docker.internal:host-gateway `
    @healthyEnv $ImageTag node dist/db/migrate.js up | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "Containerized production migration failed."
  }

  $invalidEnv = New-EnvironmentArguments -Url $healthyUrl -ScheduleMode "shadow"
  & docker run -d --name $invalidContainer `
    --add-host host.docker.internal:host-gateway @invalidEnv $ImageTag | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "Unable to start invalid-configuration container."
  }
  $invalidRunning = "true"
  for ($attempt = 0; $attempt -lt 30; $attempt++) {
    $invalidRunning = (& docker inspect --format '{{.State.Running}}' $invalidContainer).Trim()
    if ($invalidRunning -eq "false") {
      break
    }
    Start-Sleep -Milliseconds 500
  }
  $invalidExitCode = [int](& docker inspect --format '{{.State.ExitCode}}' $invalidContainer).Trim()
  if ($invalidRunning -ne "false" -or $invalidExitCode -eq 0) {
    throw "Invalid production flags did not fail closed inside the image."
  }
  Write-Output "Image invalid production flags: PASS"

  & docker run -d --name $healthyContainer `
    --add-host host.docker.internal:host-gateway `
    -p "127.0.0.1:${HealthyPort}:3000" @healthyEnv $ImageTag | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "Unable to start healthy image container."
  }
  Wait-Live -Port $HealthyPort -Container $healthyContainer
  $ready = Invoke-RestMethod `
    -Uri "http://127.0.0.1:$HealthyPort/api/health/ready" `
    -TimeoutSec 2
  if ($ready.status -ne "ok" -or $ready.latestMigrationId -ne $ExpectedMigrationId) {
    throw "Healthy image returned unexpected readiness state."
  }
  foreach ($check in $ready.checks.PSObject.Properties) {
    if ($check.Value -ne "ok") {
      throw "Healthy image readiness check $($check.Name)=$($check.Value)."
    }
  }
  & docker exec $healthyContainer sh -c `
    'wget -qO- http://127.0.0.1:3000/api/health/ready >/dev/null'
  if ($LASTEXITCODE -ne 0) {
    throw "Image healthcheck command failed for a ready container."
  }
  Write-Output "Image live/ready and healthcheck: PASS"

  $degradedEnv = New-EnvironmentArguments -Url $degradedUrl -ScheduleMode "v4"
  & docker run --rm --add-host host.docker.internal:host-gateway `
    @degradedEnv $ImageTag node dist/db/migrate.js up | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "Containerized degraded-fixture migration failed."
  }
  & $psql "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/$degradedDatabaseName" `
    -v ON_ERROR_STOP=1 -c "delete from app_schema_migrations" | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "Unable to create the degraded readiness fixture."
  }
  & docker run -d --name $degradedContainer `
    --add-host host.docker.internal:host-gateway `
    -p "127.0.0.1:${DegradedPort}:3000" @degradedEnv $ImageTag | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "Unable to start degraded image container."
  }
  Wait-Live -Port $DegradedPort -Container $degradedContainer
  $degradedResponse = Invoke-WebRequest `
    -Uri "http://127.0.0.1:$DegradedPort/api/health/ready" `
    -SkipHttpErrorCheck `
    -TimeoutSec 2
  $degradedBody = $degradedResponse.Content | ConvertFrom-Json
  if (
    $degradedResponse.StatusCode -ne 503 -or
    $degradedBody.status -ne "degraded" -or
    $degradedBody.checks.migrations -ne "error"
  ) {
    throw (
      "Degraded image readiness mismatch: " +
      "http=$($degradedResponse.StatusCode), " +
      "status=$($degradedBody.status), " +
      "migrations=$($degradedBody.checks.migrations)."
    )
  }
  & docker exec $degradedContainer sh -c `
    'wget -qO- http://127.0.0.1:3000/api/health/ready >/dev/null'
  if ($LASTEXITCODE -eq 0) {
    throw "Image healthcheck command accepted a degraded container."
  }
  Write-Output "Image degraded readiness HTTP 503: PASS"
} finally {
  foreach ($container in @($healthyContainer, $degradedContainer, $invalidContainer)) {
    Remove-GateContainer $container
  }
  foreach ($database in @($DatabaseName, $degradedDatabaseName)) {
    Remove-GateDatabase $database
  }
  Write-Output "Removed image-gate containers and databases."
}
