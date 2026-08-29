$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$deployScriptPath = Join-Path $PSScriptRoot "..\deploy-api-release.sh"
$migrationPath = Join-Path `
  $PSScriptRoot `
  "..\..\..\server\db\migrations\0142_schedule_plan_series_subscription_snapshot.up.sql"
foreach ($requiredPath in @($deployScriptPath, $migrationPath)) {
  if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
    throw "Required release contract file is missing: $requiredPath"
  }
}

$deployScript = Get-Content -Raw -LiteralPath $deployScriptPath
$migration = Get-Content -Raw -LiteralPath $migrationPath

function Get-RequiredMatch {
  param(
    [Parameter(Mandatory = $true)][string]$Text,
    [Parameter(Mandatory = $true)][string]$Pattern,
    [Parameter(Mandatory = $true)][string]$Label
  )

  $match = [regex]::Match($Text, $Pattern)
  if (-not $match.Success) {
    throw "Release DB contract value is missing: $Label"
  }
  return $match.Groups[1].Value
}

function Get-Sha256Hex {
  param([Parameter(Mandatory = $true)][string]$Value)

  $sha256 = [Security.Cryptography.SHA256]::Create()
  try {
    return ([BitConverter]::ToString(
      $sha256.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value))
    )).Replace("-", "").ToLowerInvariant()
  } finally {
    $sha256.Dispose()
  }
}

$expectedCheckSha256 = Get-RequiredMatch `
  $deployScript `
  '--expected-db-check-sha256 ([0-9a-f]{64})' `
  'CHECK SHA-256'
$expectedTriggerFunction = Get-RequiredMatch `
  $deployScript `
  '--expected-db-trigger-function ([a-z_][a-z0-9_]*\.[a-z_][a-z0-9_]*)' `
  'trigger function'
$expectedTriggerFunctionSha256 = Get-RequiredMatch `
  $deployScript `
  '--expected-db-trigger-function-sha256 ([0-9a-f]{64})' `
  'trigger function SHA-256'
$expectedUpdateColumns = Get-RequiredMatch `
  $deployScript `
  '--expected-db-trigger-update-columns ([a-z_][a-z0-9_,]*)' `
  'trigger UPDATE columns'

$containerName = "mmcrm-release-db-contract-$([guid]::NewGuid().ToString('N').Substring(0, 12))"
$containerStarted = $false
try {
  docker run -d --rm `
    --name $containerName `
    --network none `
    --tmpfs /var/lib/postgresql/data:rw,noexec,nosuid,nodev,size=128m `
    -e POSTGRES_HOST_AUTH_METHOD=trust `
    postgres:16.4-alpine | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "Isolated PostgreSQL 16.4 contract container failed to start."
  }
  $containerStarted = $true

  $ready = $false
  for ($attempt = 1; $attempt -le 80; $attempt++) {
    $probe = docker exec $containerName `
      psql -X -qAt -U postgres -c "select 1" 2>$null
    if ($LASTEXITCODE -eq 0 -and $probe -eq "1") {
      $ready = $true
      break
    }
    Start-Sleep -Milliseconds 250
  }
  if (-not $ready) {
    throw "Isolated PostgreSQL 16.4 did not become ready in 20 seconds."
  }
  # The image briefly starts an init server before the final postmaster.
  Start-Sleep -Seconds 2

  $schemaSetup = @'
set client_min_messages = warning;
create schema app;
create table app.schedule_plans (
  id uuid primary key,
  kind text,
  subscription_id uuid
);
create table app.schedule_series (
  client_type text,
  client_id uuid,
  completion_type text,
  client_charge_type text,
  client_charge_value numeric(12,2),
  teacher_compensation_type text,
  teacher_compensation_value numeric(12,2),
  subscription_id uuid,
  plan_id uuid,
  trial boolean,
  occurrence_count integer,
  timezone_name text,
  valid_until date
);
'@
  $catalogQuery = @'
select trigger_row.tgenabled,
       trigger_row.tgtype::integer,
       function_namespace.nspname || '.' || function_row.proname,
       coalesce((
         select string_agg(attribute.attname, ',' order by attribute.attname)
         from unnest(trigger_row.tgattr::smallint[]) update_column(attnum)
         join pg_attribute attribute
           on attribute.attrelid = relation.oid
          and attribute.attnum = update_column.attnum
       ), ''),
       trigger_row.tgnargs,
       function_row.pronargs,
       function_row.prorettype::regtype::text
from pg_trigger trigger_row
join pg_class relation on relation.oid = trigger_row.tgrelid
join pg_namespace namespace on namespace.oid = relation.relnamespace
join pg_proc function_row on function_row.oid = trigger_row.tgfoid
join pg_namespace function_namespace
  on function_namespace.oid = function_row.pronamespace
where namespace.nspname = 'app'
  and relation.relname = 'schedule_series'
  and trigger_row.tgname = 'schedule_series_validate_plan_subscription'
  and not trigger_row.tgisinternal;
select regexp_replace(
         pg_get_constraintdef(constraint_row.oid, false),
         '[[:space:]]+', '', 'g'
       )
from pg_constraint constraint_row
join pg_class relation on relation.oid = constraint_row.conrelid
join pg_namespace namespace on namespace.oid = relation.relnamespace
where namespace.nspname = 'app'
  and relation.relname = 'schedule_series'
  and constraint_row.conname = 'schedule_series_template_shape_check'
  and constraint_row.contype = 'c'
  and constraint_row.convalidated
  and not constraint_row.connoinherit;
'@

  $catalogRows = ($schemaSetup + $migration + $catalogQuery) |
    docker exec -i $containerName `
      psql -X -qAt -F "|" -v ON_ERROR_STOP=1 -U postgres
  if ($LASTEXITCODE -ne 0) {
    throw "Migration 0142 failed in isolated PostgreSQL 16.4."
  }
  if ($catalogRows.Count -lt 2) {
    throw "Migration 0142 did not create both DB contract objects."
  }

  $triggerContract = ($catalogRows | Select-Object -First 1).Trim()
  $normalizedCheck = ($catalogRows | Select-Object -Last 1).Trim()
  $checkHash = Get-Sha256Hex $normalizedCheck
  $functionDefinitionRows = docker exec $containerName `
    psql -X -qAt -U postgres -c @"
select pg_get_functiondef(trigger_row.tgfoid)
from pg_trigger trigger_row
join pg_class relation on relation.oid = trigger_row.tgrelid
join pg_namespace namespace on namespace.oid = relation.relnamespace
where namespace.nspname = 'app'
  and relation.relname = 'schedule_series'
  and trigger_row.tgname = 'schedule_series_validate_plan_subscription'
  and not trigger_row.tgisinternal
"@
  if ($LASTEXITCODE -ne 0) {
    throw "Migration 0142 trigger function definition could not be read."
  }
  $functionDefinition = ($functionDefinitionRows -join "`n").TrimEnd("`r", "`n")
  $functionHash = Get-Sha256Hex $functionDefinition

  $expectedTriggerContract = `
    "O|23|$expectedTriggerFunction|$expectedUpdateColumns|0|0|trigger"
  if ($triggerContract -ne $expectedTriggerContract) {
    throw "Migration 0142 trigger catalog contract does not match the deploy guard."
  }
  if ($checkHash -ne $expectedCheckSha256) {
    throw "Migration 0142 normalized CHECK does not match the deploy guard."
  }
  if ($functionHash -ne $expectedTriggerFunctionSha256) {
    throw "Migration 0142 trigger function body does not match the deploy guard."
  }

  $noOpFunction = @'
create or replace function app.validate_schedule_plan_series_subscription()
returns trigger language plpgsql as $$
begin
  return new;
end;
$$;
'@
  $noOpFunction | docker exec -i $containerName `
    psql -X -qAt -v ON_ERROR_STOP=1 -U postgres | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "No-op trigger-function mutation setup failed."
  }
  $noOpDefinitionRows = docker exec $containerName `
    psql -X -qAt -U postgres -c `
      "select pg_get_functiondef('app.validate_schedule_plan_series_subscription()'::regprocedure)"
  if ($LASTEXITCODE -ne 0) {
    throw "No-op trigger-function definition could not be read."
  }
  $noOpDefinition = ($noOpDefinitionRows -join "`n").TrimEnd("`r", "`n")
  if ((Get-Sha256Hex $noOpDefinition) -eq $expectedTriggerFunctionSha256) {
    throw "Deploy guard failed to distinguish a no-op trigger function."
  }
} finally {
  if ($containerStarted) {
    docker rm -f $containerName 2>$null | Out-Null
  }
}

Write-Output "deploy-api-release DB contract: PASS"
