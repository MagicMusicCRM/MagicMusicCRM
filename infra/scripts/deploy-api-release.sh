#!/usr/bin/env bash
set -Eeuo pipefail
set +x
export LC_ALL=C

RELEASE_ROOT="/opt/magicmusiccrm/releases"
STACK_DIR="${STACK_DIR:-/opt/magicmusiccrm/infra/staging}"
ENV_FILE="${ENV_FILE:-${STACK_DIR}/.env}"
BASE_COMPOSE="${BASE_COMPOSE:-${STACK_DIR}/docker-compose.yml}"
DEPLOYED_REVISION_FILE="${DEPLOYED_REVISION_FILE:-/opt/magicmusiccrm/DEPLOYED_REVISION}"
PUBLIC_READY_URL="${PUBLIC_READY_URL:-https://api.magicmusiccrm.ru/api/health/ready}"
HEALTH_TIMEOUT_SECONDS="${HEALTH_TIMEOUT_SECONDS:-90}"

candidate_override="${CANDIDATE_OVERRIDE:-}"
rollback_override="${ROLLBACK_OVERRIDE:-}"
candidate_image="${CANDIDATE_IMAGE:-}"
candidate_revision="${CANDIDATE_REVISION:-}"
candidate_version="${CANDIDATE_VERSION:-}"
rollback_image="${ROLLBACK_IMAGE:-}"
rollback_revision="${ROLLBACK_REVISION:-}"
rollback_version="${ROLLBACK_VERSION:-}"
expected_current_migration="${EXPECTED_CURRENT_MIGRATION:-}"
expected_migration="${EXPECTED_MIGRATION:-}"
expected_db_table="${EXPECTED_DB_TABLE:-}"
expected_db_trigger="${EXPECTED_DB_TRIGGER:-}"
expected_db_constraint="${EXPECTED_DB_CONSTRAINT:-}"
expected_db_check_sha256="${EXPECTED_DB_CHECK_SHA256:-}"
expected_db_trigger_function="${EXPECTED_DB_TRIGGER_FUNCTION:-}"
expected_db_trigger_function_sha256="${EXPECTED_DB_TRIGGER_FUNCTION_SHA256:-}"
expected_db_trigger_update_columns="${EXPECTED_DB_TRIGGER_UPDATE_COLUMNS:-}"

usage() {
  cat <<'EOF'
Usage: deploy-api-release.sh [options]

Required options (or matching uppercase environment variables):
  --candidate-override PATH
  --rollback-override PATH
  --candidate-image IMAGE
  --candidate-revision FULL_40_CHAR_SHA
  --candidate-version VERSION
  --rollback-image IMAGE
  --rollback-revision FULL_40_CHAR_SHA
  --rollback-version VERSION
  --expected-current-migration ID
  --expected-migration ID
  --expected-db-table SCHEMA.TABLE
  --expected-db-trigger NAME
  --expected-db-constraint NAME
  --expected-db-check-sha256 SHA256
  --expected-db-trigger-function SCHEMA.FUNCTION
  --expected-db-trigger-function-sha256 SHA256
  --expected-db-trigger-update-columns SORTED_CSV

Release 0142 database contract example:
  --expected-db-table app.schedule_series \
  --expected-db-trigger schedule_series_validate_plan_subscription \
  --expected-db-constraint schedule_series_template_shape_check \
  --expected-db-check-sha256 4eb90fa7e35a0a0706fba50767fd205c74e37e8e66e21ef040ad2a79e4df58ae \
  --expected-db-trigger-function app.validate_schedule_plan_series_subscription \
  --expected-db-trigger-function-sha256 2e87ee3dff67b9e6e6b891217229f9252cf64c6a3a27ccb8b1fed9952f4b2120 \
  --expected-db-trigger-update-columns plan_id,subscription_id

The script keeps database migrations in place during automatic rollback.
It never reads the Docker dotenv as a shell script and never prints it.
The CHECK hash is SHA-256 of case-preserving pg_get_constraintdef(..., false)
with all whitespace removed. Trigger UPDATE columns must be sorted.
The function hash is SHA-256 of pg_get_functiondef() with trailing newlines removed
and CRLF line endings canonicalized to LF.
EOF
}

die() {
  printf 'deploy-api-release: %s\n' "$1" >&2
  exit 1
}

require_option_value() {
  if [[ $# -lt 2 || -z "${2}" ]]; then
    die "missing value for ${1}"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --candidate-override)
      require_option_value "$@"; candidate_override="$2"; shift 2 ;;
    --rollback-override)
      require_option_value "$@"; rollback_override="$2"; shift 2 ;;
    --candidate-image)
      require_option_value "$@"; candidate_image="$2"; shift 2 ;;
    --candidate-revision)
      require_option_value "$@"; candidate_revision="$2"; shift 2 ;;
    --candidate-version)
      require_option_value "$@"; candidate_version="$2"; shift 2 ;;
    --rollback-image)
      require_option_value "$@"; rollback_image="$2"; shift 2 ;;
    --rollback-revision)
      require_option_value "$@"; rollback_revision="$2"; shift 2 ;;
    --rollback-version)
      require_option_value "$@"; rollback_version="$2"; shift 2 ;;
    --expected-current-migration)
      require_option_value "$@"; expected_current_migration="$2"; shift 2 ;;
    --expected-migration)
      require_option_value "$@"; expected_migration="$2"; shift 2 ;;
    --expected-db-table)
      require_option_value "$@"; expected_db_table="$2"; shift 2 ;;
    --expected-db-trigger)
      require_option_value "$@"; expected_db_trigger="$2"; shift 2 ;;
    --expected-db-constraint)
      require_option_value "$@"; expected_db_constraint="$2"; shift 2 ;;
    --expected-db-check-sha256)
      require_option_value "$@"; expected_db_check_sha256="$2"; shift 2 ;;
    --expected-db-trigger-function)
      require_option_value "$@"; expected_db_trigger_function="$2"; shift 2 ;;
    --expected-db-trigger-function-sha256)
      require_option_value "$@"; expected_db_trigger_function_sha256="$2"; shift 2 ;;
    --expected-db-trigger-update-columns)
      require_option_value "$@"; expected_db_trigger_update_columns="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      die "unknown option: $1" ;;
  esac
done

for command_name in docker curl realpath flock date sha256sum; do
  command -v "${command_name}" >/dev/null 2>&1 ||
    die "required command is unavailable: ${command_name}"
done

for required_name in \
  candidate_override rollback_override candidate_image candidate_revision \
  candidate_version rollback_image rollback_revision rollback_version \
  expected_current_migration expected_migration expected_db_table \
  expected_db_trigger expected_db_constraint expected_db_check_sha256 \
  expected_db_trigger_function expected_db_trigger_function_sha256 \
  expected_db_trigger_update_columns; do
  [[ -n "${!required_name}" ]] || die "${required_name} is required"
done

[[ "${candidate_image}" =~ ^magicmusiccrm-server:[A-Za-z0-9_.+-]+$ ]] ||
  die "candidate image must be an exact magicmusiccrm-server tag"
[[ "${rollback_image}" =~ ^magicmusiccrm-server:[A-Za-z0-9_.+-]+$ ]] ||
  die "rollback image must be an exact magicmusiccrm-server tag"
[[ "${candidate_revision}" =~ ^[0-9a-f]{40}$ ]] ||
  die "candidate revision must be a full lowercase 40-character SHA"
[[ "${rollback_revision}" =~ ^[0-9a-f]{40}$ ]] ||
  die "rollback revision must be a full lowercase 40-character SHA"
[[ "${candidate_version}" =~ ^[A-Za-z0-9][A-Za-z0-9.+-]{0,79}$ ]] ||
  die "candidate version label is invalid"
[[ "${rollback_version}" =~ ^[A-Za-z0-9][A-Za-z0-9.+-]{0,79}$ ]] ||
  die "rollback version label is invalid"
[[ "${expected_current_migration}" =~ ^[0-9]{4}_[a-z0-9_]+$ ]] ||
  die "expected current migration ID is invalid"
[[ "${expected_migration}" =~ ^[0-9]{4}_[a-z0-9_]+$ ]] ||
  die "expected migration ID is invalid"
[[ "${expected_db_table}" =~ ^[a-z_][a-z0-9_]*\.[a-z_][a-z0-9_]*$ ]] ||
  die "expected database table must be schema.table"
[[ "${expected_db_trigger}" =~ ^[a-z_][a-z0-9_]*$ ]] ||
  die "expected database trigger name is invalid"
[[ "${expected_db_constraint}" =~ ^[a-z_][a-z0-9_]*$ ]] ||
  die "expected database constraint name is invalid"
[[ "${expected_db_check_sha256}" =~ ^[0-9a-f]{64}$ ]] ||
  die "expected database CHECK definition SHA-256 is invalid"
[[ "${expected_db_trigger_function}" =~ ^[a-z_][a-z0-9_]*\.[a-z_][a-z0-9_]*$ ]] ||
  die "expected database trigger function must be schema.function"
[[ "${expected_db_trigger_function_sha256}" =~ ^[0-9a-f]{64}$ ]] ||
  die "expected database trigger function SHA-256 is invalid"
[[ "${expected_db_trigger_update_columns}" =~ ^[a-z_][a-z0-9_]*(,[a-z_][a-z0-9_]*)*$ ]] ||
  die "expected trigger UPDATE columns must be a sorted CSV"
previous_trigger_column=""
IFS=',' read -r -a expected_trigger_columns \
  <<<"${expected_db_trigger_update_columns}"
for trigger_column in "${expected_trigger_columns[@]}"; do
  if [[ -n "${previous_trigger_column}" &&
    "${trigger_column}" < "${previous_trigger_column}" ]]; then
    die "expected trigger UPDATE columns must be sorted and unique"
  fi
  [[ "${trigger_column}" != "${previous_trigger_column}" ]] ||
    die "expected trigger UPDATE columns must be sorted and unique"
  previous_trigger_column="${trigger_column}"
done
unset expected_trigger_columns previous_trigger_column trigger_column
[[ "${HEALTH_TIMEOUT_SECONDS}" =~ ^[1-9][0-9]*$ ]] ||
  die "HEALTH_TIMEOUT_SECONDS must be a positive integer"
[[ "${PUBLIC_READY_URL}" == https://* ]] ||
  die "PUBLIC_READY_URL must use HTTPS"

[[ "${candidate_override}" == /* ]] || die "candidate override must be absolute"
[[ "${rollback_override}" == /* ]] || die "rollback override must be absolute"
candidate_override="$(realpath -e -- "${candidate_override}")"
rollback_override="$(realpath -e -- "${rollback_override}")"
for release_file in "${candidate_override}" "${rollback_override}"; do
  [[ -f "${release_file}" ]] || die "release override is not a regular file"
  [[ "${release_file}" == "${RELEASE_ROOT}/"* ]] ||
    die "release override escapes ${RELEASE_ROOT}"
  [[ "$(dirname -- "${release_file}")" != "${RELEASE_ROOT}" ]] ||
    die "release override must live in a versioned release directory"
done
[[ "${candidate_override}" != "${rollback_override}" ]] ||
  die "candidate and rollback overrides must be different files"
[[ -f "${ENV_FILE}" ]] || die "Compose env file is missing"
[[ -f "${BASE_COMPOSE}" ]] || die "base Compose file is missing"
[[ "${DEPLOYED_REVISION_FILE}" == /opt/magicmusiccrm/* ]] ||
  die "deployed revision marker must stay under /opt/magicmusiccrm"
[[ -f "${DEPLOYED_REVISION_FILE}" ]] || die "deployed revision marker is missing"
pre_deployed_revision="$(tr -d '[:space:]' <"${DEPLOYED_REVISION_FILE}")"
[[ "${pre_deployed_revision}" =~ ^[0-9a-f]{8,40}$ ]] ||
  die "deployed revision marker is invalid"
[[ "${rollback_revision}" == "${pre_deployed_revision}"* ]] ||
  die "deployed revision marker does not match the rollback revision"

exec 9>"${RELEASE_ROOT}/.deploy-api-release.lock"
flock -n 9 || die "another API release is already running"

compose_base=(
  docker compose
  --project-directory "${STACK_DIR}"
  --env-file "${ENV_FILE}"
  -f "${BASE_COMPOSE}"
)

database_query() {
  local sql="$1"
  # Expansion belongs to the PostgreSQL container's sh, not this host shell.
  # shellcheck disable=SC2016
  "${compose_base[@]}" exec -T postgres sh -ceu \
    'psql -X -qAt -F "|" -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "$1"' \
    sh "${sql}"
}

get_migration() {
  database_query \
    'select id from app_schema_migrations order by applied_at desc, id desc limit 1'
}

assert_image_metadata() {
  local image="$1"
  local revision="$2"
  local version="$3"
  local label="$4"
  local image_id actual_revision actual_version runtime_user health_command

  image_id="$(docker image inspect "${image}" --format '{{.Id}}')" ||
    die "${label} image is not loaded"
  [[ "${image_id}" =~ ^sha256:[0-9a-f]{64}$ ]] ||
    die "${label} image ID is invalid"
  actual_revision="$(docker image inspect "${image}" \
    --format '{{index .Config.Labels "org.opencontainers.image.revision"}}')"
  actual_version="$(docker image inspect "${image}" \
    --format '{{index .Config.Labels "org.opencontainers.image.version"}}')"
  runtime_user="$(docker image inspect "${image}" --format '{{.Config.User}}')"
  health_command="$(docker image inspect "${image}" \
    --format '{{join .Config.Healthcheck.Test " "}}')"

  [[ "${actual_revision}" == "${revision}" ]] ||
    die "${label} image revision label mismatch"
  [[ "${actual_version}" == "${version}" ]] ||
    die "${label} image version label mismatch"
  [[ "${runtime_user}" == "magiccrm" ]] ||
    die "${label} image must run as magiccrm"
  [[ "${health_command}" == *'/api/health/ready'* ]] ||
    die "${label} image healthcheck must use readiness"
  printf '%s' "${image_id}"
}

# CONTRACT_HARNESS_BEGIN image-migration-head
image_migration_head() {
  local image_id="$1"
  local label="$2"
  local migration_head

  migration_head="$(
    docker run --rm --pull never --network none --read-only --cap-drop ALL \
      --security-opt no-new-privileges:true --entrypoint sh "${image_id}" -ceu '
        LC_ALL=C
        export LC_ALL
        [ -r /app/dist/main.js ]
        [ -r /app/dist/db/migrate.js ]
        [ -r /app/dist/migration/commerce/v7/commerce-data.js ]
        set -- /app/db/migrations/*.up.sql
        [ "$#" -gt 0 ] && [ -f "$1" ]
        migration_head=""
        for migration_path do
          migration_file="${migration_path##*/}"
          migration_id="${migration_file%.up.sql}"
          case "$migration_id" in
            [0-9][0-9][0-9][0-9][a-z0-9_]*) ;;
            *) exit 3 ;;
          esac
          case "$migration_id" in
            *[!a-z0-9_]*) exit 3 ;;
          esac
          migration_head="$migration_id"
        done
        [ -n "$migration_head" ]
        [ -f "/app/db/migrations/${migration_head}.down.sql" ]
        printf "%s" "$migration_head"
      '
  )" || die "${label} image migration head cannot be read in isolation"
  [[ "${migration_head}" =~ ^[0-9]{4}_[a-z0-9_]+$ ]] ||
    die "${label} image migration head is invalid"
  printf '%s' "${migration_head}"
}
# CONTRACT_HARNESS_END image-migration-head

# CONTRACT_HARNESS_BEGIN compose-api-image
resolve_compose_service_contract() {
  local override="$1"
  local parser_image_id="$2"
  local service="$3"
  local configured_contract

  configured_contract="$(
    "${compose_base[@]}" -f "${override}" config --format json |
      docker run --rm -i --pull never \
        --network none --read-only --cap-drop ALL \
        --security-opt no-new-privileges:true \
        --entrypoint node "${parser_image_id}" -e '
          let input = "";
          process.stdin.setEncoding("utf8");
          process.stdin.on("data", (chunk) => { input += chunk; });
          process.stdin.on("error", () => process.exit(2));
          process.stdin.on("end", () => {
            let config;
            try {
              config = JSON.parse(input);
            } catch {
              process.exit(3);
            }
            const service = process.argv[1];
            const serviceConfig = config?.services?.[service];
            const image = serviceConfig?.image;
            const command = serviceConfig?.command;
            const entrypoint = serviceConfig?.entrypoint;
            if (typeof image !== "string" || image.length === 0) {
              process.exit(4);
            }
            if (!Array.isArray(command) ||
                command.length === 0 ||
                command.some((part) => typeof part !== "string")) {
              process.exit(5);
            }
            if (entrypoint !== undefined && entrypoint !== null) {
              process.exit(6);
            }
            process.stdout.write(`${image}\x1f${JSON.stringify(command)}`);
          });
        ' "${service}"
  )" || die "release override API contract cannot be read from Compose JSON"
  [[ -n "${configured_contract}" ]] ||
    die "release override API contract is empty"
  printf '%s' "${configured_contract}"
}

assert_override_contract() {
  local override="$1"
  local expected_image="$2"
  local parser_image_id="$3"
  local configured_contract configured_image configured_command
  local expected_command='["sh","-c","node dist/db/migrate.js up && node dist/main.js"]'

  "${compose_base[@]}" -f "${override}" config --quiet
  configured_contract="$(resolve_compose_service_contract \
    "${override}" "${parser_image_id}" api)"
  IFS=$'\x1f' read -r configured_image configured_command \
    <<<"${configured_contract}"
  [[ "${configured_image}" == "${expected_image}" ]] ||
    die "release override does not resolve the exact API image"
  [[ "${configured_command}" == "${expected_command}" ]] ||
    die "release override does not preserve migrate-before-main API command"
}
# CONTRACT_HARNESS_END compose-api-image

candidate_image_id="$(assert_image_metadata \
  "${candidate_image}" "${candidate_revision}" "${candidate_version}" candidate)"
rollback_image_id="$(assert_image_metadata \
  "${rollback_image}" "${rollback_revision}" "${rollback_version}" rollback)"
[[ "${candidate_image_id}" != "${rollback_image_id}" ]] ||
  die "candidate and rollback images resolve to the same image ID"
candidate_image_migration_head="$(image_migration_head \
  "${candidate_image_id}" candidate)"
rollback_image_migration_head="$(image_migration_head \
  "${rollback_image_id}" rollback)"
[[ "${candidate_image_migration_head}" == "${expected_migration}" ]] ||
  die "declared target migration does not match the candidate image head"
[[ "${rollback_image_migration_head}" == "${expected_current_migration}" ]] ||
  die "declared current migration does not match the rollback image head"
assert_override_contract \
  "${candidate_override}" "${candidate_image}" "${candidate_image_id}"
assert_override_contract \
  "${rollback_override}" "${rollback_image}" "${rollback_image_id}"

api_container_id="$("${compose_base[@]}" ps --all -q api)"
[[ -n "${api_container_id}" ]] || die "API container is missing"
[[ "$(docker inspect "${api_container_id}" --format '{{.State.Running}}')" == true ]] ||
  die "API container is not running"
current_image_id="$(docker inspect "${api_container_id}" --format '{{.Image}}')"
current_image_ref="$(docker inspect "${api_container_id}" --format '{{.Config.Image}}')"
[[ "${current_image_id}" == "${rollback_image_id}" ]] ||
  die "running API is not the declared rollback image"
caddy_container_id="$("${compose_base[@]}" ps --all -q caddy)"
[[ -n "${caddy_container_id}" ]] || die "Caddy container is missing"
[[ "$(docker inspect "${caddy_container_id}" --format '{{.State.Running}}')" == true ]] ||
  die "Caddy container is not running"

pre_migration="$(get_migration)"

expected_db_schema="${expected_db_table%%.*}"
expected_db_relation="${expected_db_table#*.}"
expected_db_trigger_function_schema="${expected_db_trigger_function%%.*}"
expected_db_trigger_function_name="${expected_db_trigger_function#*.}"

# CONTRACT_HARNESS_BEGIN db-object-contract
assert_db_objects() {
  local constraint_result constraint_type constraint_validated
  local constraint_noinherit normalized_constraint constraint_hash
  local trigger_result trigger_enabled trigger_type trigger_function
  local trigger_update_columns trigger_arguments function_arguments function_return
  local trigger_function_definition canonical_trigger_function_definition
  local trigger_function_hash

  constraint_result="$(database_query "
    select
      constraint_row.contype,
      constraint_row.convalidated,
      constraint_row.connoinherit,
      regexp_replace(
        pg_get_constraintdef(constraint_row.oid, false),
        '[[:space:]]+', '', 'g'
      )
    from pg_constraint constraint_row
    join pg_class relation on relation.oid = constraint_row.conrelid
    join pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = '${expected_db_schema}'
      and relation.relname = '${expected_db_relation}'
      and constraint_row.conname = '${expected_db_constraint}'")" || return 1
  IFS='|' read -r constraint_type constraint_validated constraint_noinherit \
    normalized_constraint <<<"${constraint_result}"
  [[ "${constraint_type}" == c ]] || return 1
  [[ "${constraint_validated}" == t ]] || return 1
  [[ "${constraint_noinherit}" == f ]] || return 1
  [[ -n "${normalized_constraint}" ]] || return 1
  constraint_hash="$(printf '%s' "${normalized_constraint}" | sha256sum)" ||
    return 1
  constraint_hash="${constraint_hash%% *}"
  [[ "${constraint_hash}" == "${expected_db_check_sha256}" ]] || return 1

  trigger_result="$(database_query "
    select
      trigger_row.tgenabled,
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
    where namespace.nspname = '${expected_db_schema}'
      and relation.relname = '${expected_db_relation}'
      and trigger_row.tgname = '${expected_db_trigger}'
      and not trigger_row.tgisinternal")" || return 1
  IFS='|' read -r trigger_enabled trigger_type trigger_function \
    trigger_update_columns trigger_arguments function_arguments function_return \
    <<<"${trigger_result}"
  [[ "${trigger_enabled}" == O || "${trigger_enabled}" == A ]] || return 1
  # ROW + BEFORE + INSERT + UPDATE, with no DELETE/TRUNCATE/AFTER/STATEMENT bits.
  [[ "${trigger_type}" == 23 ]] || return 1
  [[ "${trigger_function}" == "${expected_db_trigger_function}" ]] || return 1
  [[ "${trigger_function}" == \
    "${expected_db_trigger_function_schema}.${expected_db_trigger_function_name}" ]] ||
    return 1
  [[ "${trigger_update_columns}" == \
    "${expected_db_trigger_update_columns}" ]] || return 1
  [[ "${trigger_arguments}" == 0 ]] || return 1
  [[ "${function_arguments}" == 0 ]] || return 1
  [[ "${function_return}" == trigger ]] || return 1

  trigger_function_definition="$(database_query "
    select pg_get_functiondef(trigger_row.tgfoid)
    from pg_trigger trigger_row
    join pg_class relation on relation.oid = trigger_row.tgrelid
    join pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = '${expected_db_schema}'
      and relation.relname = '${expected_db_relation}'
      and trigger_row.tgname = '${expected_db_trigger}'
      and not trigger_row.tgisinternal")" || return 1
  [[ -n "${trigger_function_definition}" ]] || return 1
  canonical_trigger_function_definition="${trigger_function_definition//$'\r\n'/$'\n'}"
  trigger_function_hash="$(
    printf '%s' "${canonical_trigger_function_definition}" | sha256sum
  )" || return 1
  trigger_function_hash="${trigger_function_hash%% *}"
  [[ "${trigger_function_hash}" == \
    "${expected_db_trigger_function_sha256}" ]] || return 1
}
# CONTRACT_HARNESS_END db-object-contract

# CONTRACT_HARNESS_BEGIN pre-migration-contract
assert_pre_migration_contract() {
  local actual_migration="$1"

  assert_migration "${actual_migration}" || return 1
  if [[ "${actual_migration}" == "${candidate_image_migration_head}" ]]; then
    assert_db_objects
  else
    [[ "${actual_migration}" == "${rollback_image_migration_head}" ]]
  fi
}
# CONTRACT_HARNESS_END pre-migration-contract

wait_for_health() {
  local expected_image_id="$1"
  local container_id status running_image_id
  local attempt

  for ((attempt = 1; attempt <= HEALTH_TIMEOUT_SECONDS; attempt++)); do
    container_id="$("${compose_base[@]}" ps --all -q api 2>/dev/null || true)"
    if [[ -n "${container_id}" ]]; then
      status="$(docker inspect "${container_id}" \
        --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' \
        2>/dev/null || true)"
      running_image_id="$(docker inspect "${container_id}" --format '{{.Image}}' \
        2>/dev/null || true)"
      if [[ "${status}" == healthy && "${running_image_id}" == "${expected_image_id}" ]]; then
        return 0
      fi
      if [[ "${status}" == exited || "${status}" == dead ]]; then
        return 1
      fi
    fi
    sleep 1
  done
  return 1
}

assert_running_metadata() {
  local expected_image_ref="$1"
  local expected_image_id="$2"
  local expected_revision="$3"
  local expected_version="$4"
  local expected_worker_state="$5"
  local container_id flag inspect_template

  container_id="$("${compose_base[@]}" ps --all -q api)" || return 1
  [[ -n "${container_id}" ]] || return 1
  [[ "$(docker inspect "${container_id}" --format '{{.Config.Image}}')" == \
    "${expected_image_ref}" ]] || return 1
  [[ "$(docker inspect "${container_id}" --format '{{.Image}}')" == \
    "${expected_image_id}" ]] || return 1
  [[ "$(docker inspect "${container_id}" \
    --format '{{index .Config.Labels "org.opencontainers.image.revision"}}')" == \
    "${expected_revision}" ]] || return 1
  [[ "$(docker inspect "${container_id}" \
    --format '{{index .Config.Labels "org.opencontainers.image.version"}}')" == \
    "${expected_version}" ]] || return 1
  [[ "$(docker inspect "${container_id}" --format '{{.Config.User}}')" == \
    magiccrm ]] || return 1

  for flag in \
    LESSON_COMPLETION_WORKER_ENABLED PLATFORM_OUTBOX_WORKER_ENABLED \
    INSTALLMENT_DUE_WORKER_ENABLED LESSON_REMINDERS_ENABLED \
    TASK_REMINDERS_ENABLED SCHEDULE_SERIES_AUTOEXTEND; do
    inspect_template="{{range .Config.Env}}{{if eq . \"${flag}=${expected_worker_state}\"}}match{{end}}{{end}}"
    [[ "$(docker inspect "${container_id}" --format "${inspect_template}")" == match ]] ||
      return 1
  done
}

assert_migration() {
  [[ "$(get_migration)" == "$1" ]]
}

assert_reconciliation() {
  local override="$1"
  local workers_override="$2"
  local result
  result="$(
    "${compose_base[@]}" -f "${override}" -f "${workers_override}" \
      exec -T api node dist/migration/commerce/v7/commerce-data.js
  )" || return 1
  [[ "${result}" == *'"issues":[]'* ]]
  unset result
}

wait_public_ready() {
  local migration="$1"
  local body attempt
  for ((attempt = 1; attempt <= HEALTH_TIMEOUT_SECONDS; attempt++)); do
    body="$(curl -fsS --connect-timeout 2 --max-time 4 \
      "${PUBLIC_READY_URL}" 2>/dev/null || true)"
    if [[ "${body}" == *'"status":"ok"'* &&
      "${body}" == *"\"latestMigrationId\":\"${migration}\""* ]]; then
      unset body
      return 0
    fi
    sleep 1
  done
  unset body
  return 1
}

assert_pre_migration_contract "${pre_migration}" ||
  die "current migration is not a compatible release schema"
current_health="$(docker inspect "${api_container_id}" \
  --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}')"
[[ "${current_health}" == healthy ]] || die "current API is not healthy"
wait_public_ready "${pre_migration}" ||
  die "current public readiness does not match the release baseline"
current_reconciliation="$(
  "${compose_base[@]}" -f "${rollback_override}" \
    exec -T api node dist/migration/commerce/v7/commerce-data.js
)" || die "current reconciliation command failed"
[[ "${current_reconciliation}" == *'"issues":[]'* ]] ||
  die "current reconciliation reported integrity issues"
unset current_reconciliation

candidate_release_dir="$(dirname -- "${candidate_override}")"
rollout_stamp="$(date -u +%Y%m%dT%H%M%SZ)"
state_dir="${candidate_release_dir}/rollout-${rollout_stamp}"
[[ ! -e "${state_dir}" ]] || die "release state directory already exists"
mkdir -m 700 -- "${state_dir}"
workers_enabled_override="${state_dir}/workers-enabled.override.yml"

cat >"${workers_enabled_override}" <<'YAML'
services:
  api:
    environment:
      LESSON_COMPLETION_WORKER_ENABLED: "true"
      PLATFORM_OUTBOX_WORKER_ENABLED: "true"
      INSTALLMENT_DUE_WORKER_ENABLED: "true"
      LESSON_REMINDERS_ENABLED: "true"
      TASK_REMINDERS_ENABLED: "true"
      SCHEDULE_SERIES_AUTOEXTEND: "true"
YAML
chmod 600 "${workers_enabled_override}"

for release_override in "${candidate_override}" "${rollback_override}"; do
  "${compose_base[@]}" -f "${release_override}" \
    -f "${workers_enabled_override}" config --quiet
done

printf '%s|%s\n' "${current_image_ref}" "${current_image_id}" \
  >"${state_dir}/pre-image.txt"
printf '%s\n' "${pre_migration}" >"${state_dir}/pre-migration.txt"
printf '%s\n' "${pre_deployed_revision}" \
  >"${state_dir}/pre-deployed-revision.txt"
sha256sum "${candidate_override}" "${rollback_override}" \
  >"${state_dir}/override-sha256.txt"
chmod 600 "${state_dir}"/*.txt

recreate_api() {
  local release_override="$1"
  local workers_override="$2"
  "${compose_base[@]}" -f "${release_override}" -f "${workers_override}" \
    up -d --no-build --pull never --no-deps --force-recreate api
}

start_caddy() {
  "${compose_base[@]}" up -d --no-build --pull never --no-deps caddy
}

mutation_started=0

# CONTRACT_HARNESS_BEGIN rollback-recovery
assert_rollback_schema_contract() {
  local actual_migration="$1"

  assert_migration "${actual_migration}" || return 1
  if [[ "${actual_migration}" == "${candidate_image_migration_head}" ]]; then
    assert_db_objects
  else
    [[ "${actual_migration}" == "${rollback_image_migration_head}" ]]
  fi
}

verify_rollback_stage() {
  local workers_override="$1"
  local expected_worker_state="$2"
  local required_schema="${3:-}"
  local actual_schema

  wait_for_health "${rollback_image_id}" || return 1
  assert_running_metadata \
    "${rollback_image}" "${rollback_image_id}" \
    "${rollback_revision}" "${rollback_version}" \
    "${expected_worker_state}" || return 1
  actual_schema="$(get_migration)" || return 1
  if [[ -n "${required_schema}" ]]; then
    [[ "${actual_schema}" == "${required_schema}" ]] || return 1
  fi
  if [[ "${actual_schema}" != "${rollback_image_migration_head}" &&
    "${actual_schema}" != "${candidate_image_migration_head}" ]]; then
    return 1
  fi
  assert_rollback_schema_contract "${actual_schema}" || return 1
  assert_reconciliation "${rollback_override}" "${workers_override}" ||
    return 1
  printf '%s' "${actual_schema}"
}

stop_service_fail_closed() {
  local service="$1"
  local expected_container_id="${2:-}"
  local container_id running

  [[ "${service}" == caddy || "${service}" == api ]] || return 1
  "${compose_base[@]}" stop "${service}" >/dev/null 2>&1 || true
  container_id="$(
    "${compose_base[@]}" ps --all -q "${service}" 2>/dev/null
  )" || return 1
  [[ -n "${container_id}" ]] || return 1
  if [[ -n "${expected_container_id}" ]]; then
    [[ "${container_id}" == "${expected_container_id}" ]] || return 1
  fi
  running="$(docker inspect "${container_id}" --format '{{.State.Running}}' \
    2>/dev/null)" || return 1
  if [[ "${running}" == true ]]; then
    docker stop --time 15 "${container_id}" >/dev/null 2>&1 || return 1
    running="$(docker inspect "${container_id}" --format '{{.State.Running}}' \
      2>/dev/null)" || return 1
  fi
  [[ "${running}" == false ]]
}

stop_unproven_rollback_api() {
  stop_service_fail_closed caddy || true
  if stop_service_fail_closed api; then
    printf 'AUTOMATIC_ROLLBACK|API_STOPPED|rollback-state-unproven\n' >&2
    return 0
  fi
  printf 'AUTOMATIC_ROLLBACK|API_STOP_FAILED|manual-action-required\n' >&2
  return 1
}

automatic_rollback() {
  local original_status="$1"
  local rollback_schema=""
  local rollback_ok=0

  set +e
  printf 'AUTOMATIC_ROLLBACK|START|status=%s\n' "${original_status}" >&2
  # Restore only the canonical production runtime; disabled workers are invalid in production.
  if stop_service_fail_closed caddy &&
    stop_service_fail_closed api &&
    recreate_api "${rollback_override}" "${workers_enabled_override}" &&
    rollback_schema="$(verify_rollback_stage \
      "${workers_enabled_override}" true)" &&
    start_caddy && wait_public_ready "${rollback_schema}"; then
    if printf '%s\n' "${pre_deployed_revision}" \
      >"${DEPLOYED_REVISION_FILE}" &&
      printf '%s\n' "${rollback_schema}" \
        >"${state_dir}/rollback-migration.txt" &&
      chmod 600 "${state_dir}/rollback-migration.txt"; then
      rollback_ok=1
    else
      stop_unproven_rollback_api
    fi
  else
    stop_unproven_rollback_api
  fi

  if [[ "${rollback_ok}" == 1 ]]; then
    printf 'AUTOMATIC_ROLLBACK|PASS\n' >&2
  else
    stop_service_fail_closed caddy || true
    printf 'AUTOMATIC_ROLLBACK|FAILED|public-remains-closed-if-not-ready\n' >&2
  fi
  set -e
}
# CONTRACT_HARNESS_END rollback-recovery

disable_release_traps() {
  trap - ERR
  trap '' HUP INT TERM
}

on_error() {
  local status=$?
  disable_release_traps
  if [[ "${mutation_started}" == 1 ]]; then
    automatic_rollback "${status}"
  fi
  exit "${status}"
}

on_signal() {
  local status="$1"
  disable_release_traps
  if [[ "${mutation_started}" == 1 ]]; then
    automatic_rollback "${status}"
  fi
  exit "${status}"
}

trap on_error ERR
trap 'on_signal 129' HUP
trap 'on_signal 130' INT
trap 'on_signal 143' TERM

# CONTRACT_HARNESS_BEGIN cutover
perform_cutover() {
  # From this point every error enters image-only rollback.
  stop_service_fail_closed caddy "${caddy_container_id}"

  # Stop the old runtime before the candidate entrypoint applies forward migrations.
  stop_service_fail_closed api "${api_container_id}"
  recreate_api "${candidate_override}" "${workers_enabled_override}"
  wait_for_health "${candidate_image_id}"
  assert_running_metadata \
    "${candidate_image}" "${candidate_image_id}" \
    "${candidate_revision}" "${candidate_version}" true
  assert_migration "${candidate_image_migration_head}"
  assert_db_objects
  assert_reconciliation "${candidate_override}" "${workers_enabled_override}"

  # Persist candidate evidence before reopening public traffic.
  printf '%s|%s\n' "${candidate_image}" "${candidate_image_id}" \
    >"${state_dir}/candidate-image.txt"
  printf '%s\n' "${candidate_image_migration_head}" \
    >"${state_dir}/candidate-migration.txt"
  chmod 600 "${state_dir}/candidate-image.txt" \
    "${state_dir}/candidate-migration.txt"

  # Public traffic is the final cutover step.
  start_caddy
  wait_public_ready "${candidate_image_migration_head}"
  printf '%s\n' "${candidate_revision}" > "${DEPLOYED_REVISION_FILE}"
}
# CONTRACT_HARNESS_END cutover

mutation_started=1
perform_cutover

mutation_started=0
trap - ERR HUP INT TERM
printf 'DEPLOY_API_RELEASE|PASS|image=%s|revision=%s|migration=%s\n' \
  "${candidate_image}" "${candidate_revision}" \
  "${candidate_image_migration_head}"
