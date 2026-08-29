$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$scriptPath = Join-Path $PSScriptRoot "..\deploy-api-release.sh"
if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
  throw "Reusable API deploy script is missing: $scriptPath"
}

$scriptText = Get-Content -Raw -LiteralPath $scriptPath

function Assert-Contains {
  param(
    [Parameter(Mandatory = $true)][string]$Needle,
    [Parameter(Mandatory = $true)][string]$Message
  )

  if (-not $scriptText.Contains($Needle)) {
    throw $Message
  }
}

function Assert-Order {
  param(
    [Parameter(Mandatory = $true)][string]$Text,
    [Parameter(Mandatory = $true)][string[]]$Needles,
    [Parameter(Mandatory = $true)][string]$Message
  )

  $cursor = 0
  foreach ($needle in $Needles) {
    $relativeIndex = $Text.Substring($cursor).IndexOf(
      $needle,
      [StringComparison]::Ordinal
    )
    if ($relativeIndex -lt 0) {
      throw "$Message Missing or out of order: $needle"
    }
    $cursor += $relativeIndex + $needle.Length
  }
}

function Get-Section {
  param(
    [Parameter(Mandatory = $true)][string]$StartMarker,
    [Parameter(Mandatory = $true)][string]$EndMarker
  )

  $startIndex = $scriptText.IndexOf($StartMarker, [StringComparison]::Ordinal)
  if ($startIndex -lt 0) {
    throw "Section start marker is missing: $StartMarker"
  }
  $endIndex = $scriptText.IndexOf(
    $EndMarker,
    $startIndex + $StartMarker.Length,
    [StringComparison]::Ordinal
  )
  if ($endIndex -lt 0) {
    throw "Section end marker is missing: $EndMarker"
  }
  return $scriptText.Substring($startIndex, $endIndex - $startIndex)
}

Assert-Contains 'set -Eeuo pipefail' `
  'Deploy must fail closed on shell, pipeline and function errors.'
Assert-Contains 'set +x' `
  'Deploy must suppress shell tracing before handling runtime data.'
Assert-Contains 'RELEASE_ROOT="/opt/magicmusiccrm/releases"' `
  'Release overrides must be constrained to the production release root.'
Assert-Contains 'realpath -e -- "${candidate_override}"' `
  'Candidate override must be resolved before any runtime mutation.'
Assert-Contains 'realpath -e -- "${rollback_override}"' `
  'Rollback override must be resolved before any runtime mutation.'
Assert-Contains 'config --format json' `
  'Merged Compose JSON must prove the exact API service image before mutation.'
Assert-Contains 'const image = serviceConfig?.image;' `
  'Compose image resolution must select services.api.image without positional filtering.'
Assert-Contains 'node dist/db/migrate.js up && node dist/main.js' `
  'Merged Compose command must preserve migrate-before-main semantics.'
Assert-Contains 'entrypoint !== undefined && entrypoint !== null' `
  'Merged Compose entrypoint must not override the pinned API command.'
Assert-Contains '--entrypoint node "${parser_image_id}" -e' `
  'Compose JSON must be parsed inside the already validated immutable image.'
Assert-Contains 'org.opencontainers.image.revision' `
  'The exact full source revision label must be checked.'
Assert-Contains 'org.opencontainers.image.version' `
  'The exact application version label must be checked.'
Assert-Contains 'schedule_series_validate_plan_subscription' `
  'The release contract example must name the 0142 subscription trigger.'
Assert-Contains 'schedule_series_template_shape_check' `
  'The release contract example must name the validated 0142 constraint.'
Assert-Contains '4eb90fa7e35a0a0706fba50767fd205c74e37e8e66e21ef040ad2a79e4df58ae' `
  'The release contract example must pin the normalized PostgreSQL 16 CHECK definition.'
Assert-Contains 'app.validate_schedule_plan_series_subscription' `
  'The release contract must pin the exact trigger function.'
Assert-Contains '2e87ee3dff67b9e6e6b891217229f9252cf64c6a3a27ccb8b1fed9952f4b2120' `
  'The release contract must pin the PostgreSQL 16 trigger function definition.'
Assert-Contains 'plan_id,subscription_id' `
  'The release contract must pin the exact sorted UPDATE OF columns.'
Assert-Contains 'trap on_error ERR' `
  'Every runtime failure after mutation must enter automatic rollback.'
Assert-Contains "trap 'on_signal 129' HUP" `
  'A hangup after mutation must enter automatic rollback.'
Assert-Contains "trap 'on_signal 130' INT" `
  'An interrupt after mutation must enter automatic rollback.'
Assert-Contains "trap 'on_signal 143' TERM" `
  'A termination signal after mutation must enter automatic rollback.'
Assert-Contains '--no-build --pull never --no-deps --force-recreate api' `
  'Cutover must never build or replace the validated local image tag.'
Assert-Contains 'node dist/migration/commerce/v7/commerce-data.js' `
  'Candidate and rollback health must be paired with reconciliation.'
Assert-Contains '--network none --read-only --cap-drop ALL' `
  'Image migration heads must be inspected without network or writable rootfs.'
Assert-Contains '--security-opt no-new-privileges:true --entrypoint sh' `
  'Image migration inspection must drop privilege escalation and avoid its command.'
Assert-Contains 'docker stop --time 15 "${container_id}"' `
  'A Compose stop failure must fall back to stopping the exact unproven container.'
Assert-Contains 'printf ''%s\n'' "${candidate_revision}" > "${DEPLOYED_REVISION_FILE}"' `
  'The deployed revision marker must be written only for the verified candidate.'

$releaseInputs = @{
  'candidate_override' = 'CANDIDATE_OVERRIDE'
  'rollback_override' = 'ROLLBACK_OVERRIDE'
  'candidate_image' = 'CANDIDATE_IMAGE'
  'candidate_revision' = 'CANDIDATE_REVISION'
  'candidate_version' = 'CANDIDATE_VERSION'
  'rollback_image' = 'ROLLBACK_IMAGE'
  'rollback_revision' = 'ROLLBACK_REVISION'
  'rollback_version' = 'ROLLBACK_VERSION'
  'expected_current_migration' = 'EXPECTED_CURRENT_MIGRATION'
  'expected_migration' = 'EXPECTED_MIGRATION'
  'expected_db_table' = 'EXPECTED_DB_TABLE'
  'expected_db_trigger' = 'EXPECTED_DB_TRIGGER'
  'expected_db_constraint' = 'EXPECTED_DB_CONSTRAINT'
  'expected_db_check_sha256' = 'EXPECTED_DB_CHECK_SHA256'
  'expected_db_trigger_function' = 'EXPECTED_DB_TRIGGER_FUNCTION'
  'expected_db_trigger_function_sha256' = 'EXPECTED_DB_TRIGGER_FUNCTION_SHA256'
  'expected_db_trigger_update_columns' = 'EXPECTED_DB_TRIGGER_UPDATE_COLUMNS'
}
foreach ($entry in $releaseInputs.GetEnumerator()) {
  Assert-Contains "$($entry.Key)=`"`${$($entry.Value):-}`"" `
    "Release input $($entry.Key) must support an explicit environment override."
  Assert-Contains "--$($entry.Key.Replace('_', '-'))" `
    "Release input $($entry.Key) must support an explicit command-line option."
}

$pathGuardText = Get-Section `
  '[[ "${candidate_override}" == /* ]]' `
  'exec 9>"${RELEASE_ROOT}/.deploy-api-release.lock"'
Assert-Order $pathGuardText @(
  '[[ "${candidate_override}" == /* ]]',
  '[[ "${rollback_override}" == /* ]]',
  'candidate_override="$(realpath -e -- "${candidate_override}")"',
  'rollback_override="$(realpath -e -- "${rollback_override}")"',
  '[[ -f "${release_file}" ]]',
  '[[ "${release_file}" == "${RELEASE_ROOT}/"* ]]',
  '[[ -f "${ENV_FILE}" ]]',
  '[[ -f "${BASE_COMPOSE}" ]]',
  '[[ -f "${DEPLOYED_REVISION_FILE}" ]]'
) 'Absolute release paths and required files must be guarded before locking.'

$preMutationValidationText = Get-Section `
  'candidate_image_id="$(assert_image_metadata' `
  'recreate_api() {'
Assert-Order $preMutationValidationText @(
  'candidate_image_id="$(assert_image_metadata',
  'rollback_image_id="$(assert_image_metadata',
  'candidate_image_migration_head="$(image_migration_head',
  'rollback_image_migration_head="$(image_migration_head',
  '[[ "${candidate_image_migration_head}" == "${expected_migration}" ]]',
  '[[ "${rollback_image_migration_head}" == "${expected_current_migration}" ]]',
  'assert_override_contract',
  '"${candidate_override}" "${candidate_image}" "${candidate_image_id}"',
  'assert_override_contract',
  '"${rollback_override}" "${rollback_image}" "${rollback_image_id}"',
  'current_image_id="$(docker inspect',
  '[[ "${current_image_id}" == "${rollback_image_id}" ]]',
  'caddy_container_id="$("${compose_base[@]}" ps --all -q caddy)"',
  '[[ -n "${caddy_container_id}" ]]',
  'pre_migration="$(get_migration)"',
  'current_health="$(docker inspect',
  'current_reconciliation=',
  'mkdir -m 700 -- "${state_dir}"',
  'config --quiet',
  '>"${state_dir}/pre-image.txt"',
  '>"${state_dir}/pre-migration.txt"'
) 'Images, labels, live baseline and saved rollback evidence must precede mutation.'

$workerFlags = @(
  'LESSON_COMPLETION_WORKER_ENABLED',
  'PLATFORM_OUTBOX_WORKER_ENABLED',
  'INSTALLMENT_DUE_WORKER_ENABLED',
  'LESSON_REMINDERS_ENABLED',
  'TASK_REMINDERS_ENABLED',
  'SCHEDULE_SERIES_AUTOEXTEND'
)
foreach ($flag in $workerFlags) {
  Assert-Contains "$flag`: `"true`"" `
    "Canonical cutover runtime must explicitly enable $flag."
  if ($scriptText.Contains("$flag`: `"false`"")) {
    throw "Production cutover must not create an invalid disabled override for $flag."
  }
}

$cutoverText = Get-Section `
  '# From this point every error enters image-only rollback.' `
  'mutation_started=0'
Assert-Order $cutoverText @(
  'stop_service_fail_closed caddy "${caddy_container_id}"',
  'stop_service_fail_closed api "${api_container_id}"',
  'recreate_api "${candidate_override}" "${workers_enabled_override}"',
  'wait_for_health "${candidate_image_id}"',
  '"${candidate_revision}" "${candidate_version}" true',
  'assert_migration "${candidate_image_migration_head}"',
  'assert_db_objects',
  'assert_reconciliation "${candidate_override}" "${workers_enabled_override}"',
  'start_caddy',
  'wait_public_ready "${candidate_image_migration_head}"',
  'printf ''%s\n'' "${candidate_revision}" > "${DEPLOYED_REVISION_FILE}"'
) 'Main cutover must stop the old API, then verify one canonical production runtime.'

$dbContractText = Get-Section `
  '# CONTRACT_HARNESS_BEGIN db-object-contract' `
  '# CONTRACT_HARNESS_END db-object-contract'
Assert-Order $dbContractText @(
  'constraint_row.contype',
  'constraint_row.convalidated',
  'constraint_row.connoinherit',
  'pg_get_constraintdef',
  'constraint_hash=',
  '"${constraint_hash}" == "${expected_db_check_sha256}"',
  'trigger_row.tgenabled',
  'trigger_row.tgtype::integer',
  'function_namespace.nspname',
  'trigger_row.tgattr::smallint[]',
  '[[ "${trigger_enabled}" == O || "${trigger_enabled}" == A ]]',
  '[[ "${trigger_type}" == 23 ]]',
  '"${expected_db_trigger_update_columns}"',
  'pg_get_functiondef(trigger_row.tgfoid)',
  '"${trigger_function_hash}" ==',
  '"${expected_db_trigger_function_sha256}"'
) 'DB object validation must check exact CHECK and trigger catalog semantics.'

$rollbackVerificationText = Get-Section `
  'verify_rollback_stage() {' `
  'stop_unproven_rollback_api() {'
Assert-Order $rollbackVerificationText @(
  'wait_for_health "${rollback_image_id}"',
  'assert_running_metadata',
  'actual_schema="$(get_migration)"',
  '"${rollback_image_migration_head}"',
  '"${candidate_image_migration_head}"',
  'assert_rollback_schema_contract "${actual_schema}"',
  'assert_reconciliation "${rollback_override}" "${workers_override}"'
) 'Rollback must prove health, identity, schema and reconciliation.'

$rollbackText = Get-Section `
  'automatic_rollback() {' `
  '# CONTRACT_HARNESS_END rollback-recovery'
Assert-Order $rollbackText @(
  '# Restore only the canonical production runtime; disabled workers are invalid in production.',
  'stop_service_fail_closed caddy',
  'stop_service_fail_closed api',
  'recreate_api "${rollback_override}" "${workers_enabled_override}"',
  'rollback_schema="$(verify_rollback_stage',
  '"${workers_enabled_override}" true)',
  'start_caddy',
  'wait_public_ready "${rollback_schema}"',
  'stop_unproven_rollback_api'
) 'Automatic rollback must verify one valid production stage and fail closed on failure.'

if ($scriptText -match '(?i)(db:rollback|migrate\.js\s+down|migrate\.ts\s+down)') {
  throw 'Automatic rollback must be image-only and must retain the migrated schema.'
}
if ($scriptText -match '(?m)^\s*\.\s+"?\$\{?ENV_FILE') {
  throw 'Docker dotenv must never be sourced or printed by the deploy script.'
}
if ($scriptText.Contains('{{range .Config.Env}}{{println .}}{{end}}')) {
  throw 'Runtime checks must not capture the complete container environment.'
}
if ($scriptText.Contains('dist/platform/v7-commerce-data.js')) {
  throw 'The legacy reconciliation path does not exist in the rollback image.'
}

Write-Output "deploy-api-release contract: PASS"
