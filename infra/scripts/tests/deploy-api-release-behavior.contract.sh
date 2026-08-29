#!/usr/bin/env bash
set -Eeuo pipefail
set +x
export LC_ALL=C

script_path="${1:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/deploy-api-release.sh}"
[[ -f "${script_path}" ]] || {
  printf 'deploy-api-release behavior: missing script\n' >&2
  exit 1
}

extract_contract_section() {
  local section="$1"
  sed -n \
    "/^# CONTRACT_HARNESS_BEGIN ${section}$/,/^# CONTRACT_HARNESS_END ${section}$/p" \
    "${script_path}"
}

extract_function() {
  local function_name="$1"
  sed -n "/^${function_name}() {$/,/^}$/p" "${script_path}"
}

eval "$(extract_contract_section image-migration-head)"
eval "$(extract_contract_section db-object-contract)"
eval "$(extract_contract_section rollback-recovery)"
eval "$(extract_contract_section cutover)"
eval "$(extract_function resolve_compose_service_image)"
eval "$(extract_function assert_override_image)"

test_tmp="$(mktemp -d)"
[[ "${test_tmp}" == /tmp/* ]] || {
  printf 'deploy-api-release behavior: unsafe temp path\n' >&2
  exit 1
}
trap 'rm -rf -- "${test_tmp}"' EXIT

expect_pass() {
  local label="$1"
  shift
  "$@" || {
    printf 'deploy-api-release behavior: expected PASS: %s\n' "${label}" >&2
    exit 1
  }
}

expect_fail() {
  local label="$1"
  shift
  if "$@"; then
    printf 'deploy-api-release behavior: expected FAIL: %s\n' "${label}" >&2
    exit 1
  fi
}

fake_node_service_image() {
  local input compact api_object

  input="$(cat)" || return 2
  compact="$(printf '%s' "${input}" | tr -d '[:space:]')"
  [[ "${compact}" =~ \"services\":\{ ]] || return 3
  [[ "${compact}" =~ \"api\":\{([^{}]*)\} ]] || return 4
  api_object="${BASH_REMATCH[1]}"
  [[ "${api_object}" =~ \"image\":\"([^\"]+)\" ]] || return 5
  printf '%s' "${BASH_REMATCH[1]}"
}

fake_image_head=0141_previous
fake_image_fixture=output
image_fixture_root="${test_tmp}/image-root"
mkdir -p -- \
  "${image_fixture_root}/app/dist/db" \
  "${image_fixture_root}/app/dist/migration/commerce/v7" \
  "${image_fixture_root}/app/db/migrations"
touch -- \
  "${image_fixture_root}/app/dist/main.js" \
  "${image_fixture_root}/app/dist/db/migrate.js" \
  "${image_fixture_root}/app/dist/migration/commerce/v7/commerce-data.js"
for fixture_migration in \
  0088_lesson_completion_worker \
  0088z_legacy_negative_payment_refunds \
  0142_schedule_plan_series_subscription_snapshot; do
  touch -- \
    "${image_fixture_root}/app/db/migrations/${fixture_migration}.up.sql" \
    "${image_fixture_root}/app/db/migrations/${fixture_migration}.down.sql"
done
docker() {
  local final_arg rewritten_script

  case "$1" in
    run)
      if [[ " $* " == *' --entrypoint node '* ]]; then
        fake_node_service_image
      elif [[ "${fake_image_fixture}" == filesystem ]]; then
        for final_arg in "$@"; do :; done
        rewritten_script="${final_arg//\/app/${image_fixture_root}/app}"
        sh -ceu "${rewritten_script}"
      else
        printf '%s' "${fake_image_head}"
      fi
      ;;
    inspect)
      log_event "docker-inspect:${2}"
      if [[ "$2" == fake-caddy-container ]]; then
        cat -- "${caddy_running_file}"
      else
        cat -- "${api_running_file}"
      fi
      ;;
    stop)
      log_event "docker-stop:${*:2}"
      if [[ "${*:2}" == *fake-caddy-container* ]]; then
        printf 'false\n' >"${caddy_running_file}"
      else
        printf 'false\n' >"${api_running_file}"
      fi
      ;;
    *)
      return 1
      ;;
  esac
}
die() {
  exit 1
}
image_head_call() {
  (image_migration_head sha256:fake contract)
}

image_head_result="$(image_head_call)"
[[ "${image_head_result}" == 0141_previous ]] || {
  printf 'deploy-api-release behavior: valid image head was rejected\n' >&2
  exit 1
}
fake_image_head='../../not-a-migration'
expect_fail 'malformed image migration head' image_head_call
fake_image_head=0141_previous

fake_image_fixture=filesystem
touch -- \
  "${image_fixture_root}/app/db/migrations/0130_bad-name.up.sql" \
  "${image_fixture_root}/app/db/migrations/0130_bad-name.down.sql"
expect_fail 'unsafe migration filename inside image' image_head_call
rm -- \
  "${image_fixture_root}/app/db/migrations/0130_bad-name.up.sql" \
  "${image_fixture_root}/app/db/migrations/0130_bad-name.down.sql"
image_head_result="$(image_head_call)"
[[ "${image_head_result}" == 0142_schedule_plan_series_subscription_snapshot ]] || {
  printf 'deploy-api-release behavior: historical alphanumeric migration was rejected\n' >&2
  exit 1
}
fake_image_fixture=output

compose_config_fixture=compose-v2
fake_compose_config() {
  case "$*" in
    *'config --quiet')
      return 0
      ;;
    *'config --images api')
      printf '%s\n' \
        alpine:3.20 \
        registry.example/magic/api:candidate \
        postgres:16.4-alpine \
        redis:7.4.1-alpine
      ;;
    *'config --format json')
      case "${compose_config_fixture}" in
        compose-v2)
          printf '%s\n' \
            '{"services":{"api":{"image":"registry.example/magic/api:candidate"},"redis":{"image":"redis:7.4.1-alpine"}}}'
          ;;
        compose-v5)
          printf '%s\n' \
            '{' \
            '  "services": {' \
            '    "storage-init": {"image": "alpine:3.20"},' \
            '    "postgres": {"image": "postgres:16.4-alpine"},' \
            '    "api": {"image": "registry.example/magic/api:candidate"},' \
            '    "redis": {"image": "redis:7.4.1-alpine"}' \
            '  }' \
            '}'
          ;;
        wrong-api)
          printf '%s\n' \
            '{"services":{"api":{"image":"registry.example/magic/api:other"},"redis":{"image":"registry.example/magic/api:candidate"}}}'
          ;;
        missing-api-image)
          printf '%s\n' \
            '{"services":{"api":{"command":"node dist/main.js"},"redis":{"image":"registry.example/magic/api:candidate"}}}'
          ;;
        non-string-api-image)
          printf '%s\n' \
            '{"services":{"api":{"image":["registry.example/magic/api:candidate"]}}}'
          ;;
        *)
          return 1
          ;;
      esac
      ;;
    *)
      return 1
      ;;
  esac
}

# These globals are consumed by the extracted production functions through eval.
# shellcheck disable=SC2034
declare -a compose_base=(fake_compose_config)
parser_image_id=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
expected_override_image=registry.example/magic/api:candidate
override_image_call() {
  (assert_override_image \
    test-override "${expected_override_image}" "${parser_image_id}")
}

compose_config_fixture=compose-v2
expect_pass 'Compose v2 multi-image output resolves services.api.image' \
  override_image_call
compose_config_fixture=compose-v5
expect_pass 'Compose v5 multi-image output resolves services.api.image' \
  override_image_call
compose_config_fixture=wrong-api
expect_fail 'another service cannot satisfy the API image contract' \
  override_image_call
compose_config_fixture=missing-api-image
expect_fail 'missing services.api.image fails closed' override_image_call
compose_config_fixture=non-string-api-image
expect_fail 'non-string services.api.image fails closed' override_image_call

# These globals are consumed by the extracted production function through eval.
# shellcheck disable=SC2034
declare expected_db_schema=app \
  expected_db_relation=schedule_series \
  expected_db_constraint=schedule_series_template_shape_check \
  expected_db_trigger=schedule_series_validate_plan_subscription \
  expected_db_trigger_function=app.validate_schedule_plan_series_subscription \
  expected_db_trigger_function_schema=app \
  expected_db_trigger_function_name=validate_schedule_plan_series_subscription \
  expected_db_trigger_update_columns=plan_id,subscription_id

valid_constraint_definition='check(subscription_idisnullorplan_idisnotnull)'
expected_db_check_sha256="$(
  printf '%s' "${valid_constraint_definition}" | sha256sum
)"
expected_db_check_sha256="${expected_db_check_sha256%% *}"
fake_constraint_result="c|t|f|${valid_constraint_definition}"
fake_trigger_result='O|23|app.validate_schedule_plan_series_subscription|plan_id,subscription_id|0|0|trigger'
fake_function_definition='CREATE FUNCTION app.validate_schedule_plan_series_subscription() RETURNS trigger BODY exact-behavior'
expected_db_trigger_function_sha256="$(
  printf '%s' "${fake_function_definition}" | sha256sum
)"
expected_db_trigger_function_sha256="${expected_db_trigger_function_sha256%% *}"

database_query() {
  local sql="$1"
  case "${sql}" in
    *'select pg_get_functiondef(trigger_row.tgfoid)'*)
      printf '%s\n' "${fake_function_definition}"
      ;;
    *'from pg_constraint constraint_row'*)
      printf '%s\n' "${fake_constraint_result}"
      ;;
    *'from pg_trigger trigger_row'*)
      printf '%s\n' "${fake_trigger_result}"
      ;;
    *)
      return 1
      ;;
  esac
}

expect_pass 'exact CHECK and trigger catalog contract' assert_db_objects

fake_constraint_result="f|t|f|${valid_constraint_definition}"
expect_fail 'constraint must be CHECK type' assert_db_objects
fake_constraint_result='c|t|f|check(subscription_idisnull)'
expect_fail 'normalized CHECK definition hash must match' assert_db_objects
fake_constraint_result="c|t|f|${valid_constraint_definition}"

fake_trigger_result='R|23|app.validate_schedule_plan_series_subscription|plan_id,subscription_id|0|0|trigger'
expect_fail 'replica-only trigger is not enabled for normal writes' assert_db_objects
fake_trigger_result='O|19|app.validate_schedule_plan_series_subscription|plan_id,subscription_id|0|0|trigger'
expect_fail 'trigger timing and events must be exact' assert_db_objects
fake_trigger_result='O|23|app.wrong_function|plan_id,subscription_id|0|0|trigger'
expect_fail 'trigger function identity must match' assert_db_objects
fake_trigger_result='O|23|app.validate_schedule_plan_series_subscription|lesson_id,plan_id,subscription_id|0|0|trigger'
expect_fail 'UPDATE OF columns must match migration exactly' assert_db_objects
fake_trigger_result='A|23|app.validate_schedule_plan_series_subscription|plan_id,subscription_id|0|0|trigger'
expect_pass 'always-enabled trigger is accepted' assert_db_objects
fake_function_definition='CREATE FUNCTION app.validate_schedule_plan_series_subscription() RETURNS trigger BODY return-new-no-op'
expect_fail 'trigger function body hash must match' assert_db_objects
fake_function_definition='CREATE FUNCTION app.validate_schedule_plan_series_subscription() RETURNS trigger BODY exact-behavior'

event_file="${test_tmp}/events.log"
stage_file="${test_tmp}/stage.txt"
recreate_count_file="${test_tmp}/recreate-count.txt"
api_running_file="${test_tmp}/api-running.txt"
caddy_running_file="${test_tmp}/caddy-running.txt"
caddy_stop_count_file="${test_tmp}/caddy-stop-count.txt"
api_stop_count_file="${test_tmp}/api-stop-count.txt"
# These globals are consumed by the extracted rollback functions through eval.
# shellcheck disable=SC2034
declare DEPLOYED_REVISION_FILE="${test_tmp}/deployed-revision.txt" \
  candidate_override=candidate-release \
  candidate_image=candidate-image \
  candidate_image_id=sha256:candidate \
  candidate_revision=2222222222222222222222222222222222222222 \
  candidate_version=candidate-version \
  rollback_override=rollback-release \
  workers_enabled_override=workers-enabled \
  rollback_image=rollback-image \
  rollback_image_id=sha256:rollback \
  rollback_revision=1111111111111111111111111111111111111111 \
  rollback_version=rollback-version \
  rollback_image_migration_head=0141_previous \
  pre_deployed_revision=11111111
state_dir="${test_tmp}/state"
mkdir -- "${state_dir}"

# shellcheck disable=SC2034
declare -a compose_base=(fake_compose)
candidate_image_migration_head=0142_candidate

log_event() {
  printf '%s\n' "$1" >>"${event_file}"
}

current_stage() {
  cat -- "${stage_file}"
}

fake_compose() {
  if [[ "$*" == 'stop caddy' ]]; then
    local caddy_stop_count
    caddy_stop_count="$(cat -- "${caddy_stop_count_file}")"
    caddy_stop_count=$((caddy_stop_count + 1))
    printf '%s\n' "${caddy_stop_count}" >"${caddy_stop_count_file}"
    printf 'false\n' >"${caddy_running_file}"
    log_event "compose:stop caddy:${caddy_stop_count}"
    return 0
  fi
  if [[ "$*" == 'stop api' ]]; then
    local api_stop_count
    api_stop_count="$(cat -- "${api_stop_count_file}")"
    api_stop_count=$((api_stop_count + 1))
    printf '%s\n' "${api_stop_count}" >"${api_stop_count_file}"
    log_event "compose:stop api:${api_stop_count}"
    return 0
  fi
  log_event "compose:$*"
  if [[ "$*" == 'ps --all -q caddy' ]]; then
    printf 'fake-caddy-container\n'
  fi
  if [[ ("${scenario:-}" == rollback_unproven ||
    "${scenario:-}" == post_public_failure) &&
    "$*" == 'ps --all -q api' ]]; then
    printf 'fake-api-container\n'
  fi
  return 0
}

recreate_api() {
  local count
  count="$(cat -- "${recreate_count_file}")"
  count=$((count + 1))
  printf '%s\n' "${count}" >"${recreate_count_file}"
  printf '%s|%s\n' "${count}" "$2" >"${stage_file}"
  printf 'true\n' >"${api_running_file}"
  log_event "recreate:${count}:$2"
}

wait_for_health() {
  local stage
  stage="$(current_stage)"
  log_event "health:${stage}"
  if [[ "${scenario}" == rollback_unproven &&
    "${stage}" == 1'|'workers-enabled ]]; then
    return 1
  fi
}

assert_running_metadata() {
  local stage
  stage="$(current_stage)"
  log_event "metadata:${stage}:worker-$5"
}

get_migration() {
  log_event "migration:$(current_stage)"
  printf '%s' "${candidate_image_migration_head}"
}

assert_migration() {
  log_event "assert-migration:$(current_stage):$1"
  [[ "$1" == "${candidate_image_migration_head}" ]]
}

assert_db_objects() {
  log_event "db-objects:$(current_stage)"
}

assert_reconciliation() {
  local stage
  stage="$(current_stage)"
  log_event "reconcile:${stage}:$2"
}

start_caddy() {
  log_event start-caddy
  printf 'true\n' >"${caddy_running_file}"
}

wait_public_ready() {
  log_event "public-ready:$1"
  [[ "${scenario}" != post_public_failure ]]
}

reset_rollback_scenario() {
  scenario="$1"
  : >"${event_file}"
  : >"${stage_file}"
  printf '0\n' >"${recreate_count_file}"
  printf 'true\n' >"${api_running_file}"
  printf 'false\n' >"${caddy_running_file}"
  printf '0\n' >"${caddy_stop_count_file}"
  printf '0\n' >"${api_stop_count_file}"
  rm -f -- \
    "${DEPLOYED_REVISION_FILE}" \
    "${state_dir}/candidate-image.txt" \
    "${state_dir}/candidate-migration.txt"
  rm -f -- "${state_dir}/rollback-migration.txt"
}

assert_log_contains() {
  local expected="$1"
  grep -Fqx -- "${expected}" "${event_file}" || {
    printf 'deploy-api-release behavior: missing event: %s\n' "${expected}" >&2
    exit 1
  }
}

assert_log_excludes() {
  local unexpected="$1"
  if grep -Fqx -- "${unexpected}" "${event_file}"; then
    printf 'deploy-api-release behavior: unexpected event: %s\n' \
      "${unexpected}" >&2
    exit 1
  fi
}

assert_event_before() {
  local first="$1"
  local second="$2"
  local first_line second_line
  first_line="$(grep -nF -- "${first}" "${event_file}" | head -n 1 | cut -d: -f1)"
  second_line="$(grep -nF -- "${second}" "${event_file}" | head -n 1 | cut -d: -f1)"
  [[ -n "${first_line}" && -n "${second_line}" &&
    "${first_line}" -lt "${second_line}" ]] || {
    printf 'deploy-api-release behavior: wrong event order: %s -> %s\n' \
      "${first}" "${second}" >&2
    exit 1
  }
}

reset_rollback_scenario main_cutover
perform_cutover
assert_event_before 'compose:stop caddy:1' 'compose:stop api:1'
assert_event_before 'compose:stop api:1' 'recreate:1:workers-enabled'
assert_log_contains 'metadata:1|workers-enabled:worker-true'
assert_log_contains 'assert-migration:1|workers-enabled:0142_candidate'
assert_log_contains 'db-objects:1|workers-enabled'
assert_log_contains 'reconcile:1|workers-enabled:workers-enabled'
assert_event_before 'reconcile:1|workers-enabled:workers-enabled' start-caddy
assert_log_contains 'public-ready:0142_candidate'
assert_log_excludes 'recreate:1:workers-disabled'
[[ "$(cat -- "${DEPLOYED_REVISION_FILE}")" == "${candidate_revision}" ]] || {
  printf 'deploy-api-release behavior: cutover lost candidate revision\n' >&2
  exit 1
}
[[ "$(cat -- "${state_dir}/candidate-migration.txt")" == \
  "${candidate_image_migration_head}" ]] || {
  printf 'deploy-api-release behavior: cutover lost candidate schema evidence\n' >&2
  exit 1
}

reset_rollback_scenario rollback_success
automatic_rollback 77 2>/dev/null
assert_event_before 'compose:stop api:1' 'recreate:1:workers-enabled'
assert_log_contains 'recreate:1:workers-enabled'
assert_log_contains 'health:1|workers-enabled'
assert_log_contains 'metadata:1|workers-enabled:worker-true'
assert_log_contains 'assert-migration:1|workers-enabled:0142_candidate'
assert_log_contains 'db-objects:1|workers-enabled'
assert_log_contains 'reconcile:1|workers-enabled:workers-enabled'
assert_log_contains 'compose:stop api:1'
assert_log_contains start-caddy
assert_log_contains 'public-ready:0142_candidate'
[[ "$(cat -- "${DEPLOYED_REVISION_FILE}")" == "${pre_deployed_revision}" ]] || {
  printf 'deploy-api-release behavior: successful rollback lost deployed revision\n' >&2
  exit 1
}
[[ "$(cat -- "${state_dir}/rollback-migration.txt")" == \
  "${candidate_image_migration_head}" ]] || {
  printf 'deploy-api-release behavior: successful rollback lost schema evidence\n' >&2
  exit 1
}
[[ "$(cat -- "${caddy_running_file}")" == true ]] || {
  printf 'deploy-api-release behavior: successful rollback did not reopen Caddy\n' >&2
  exit 1
}

reset_rollback_scenario rollback_unproven
automatic_rollback 78 2>/dev/null
assert_event_before 'health:1|workers-enabled' 'compose:stop api:2'
assert_log_contains 'compose:stop api:2'
assert_log_contains 'docker-stop:--time 15 fake-api-container'
assert_log_contains 'docker-inspect:fake-api-container'
assert_log_excludes start-caddy

reset_rollback_scenario post_public_failure
automatic_rollback 79 2>/dev/null
assert_event_before start-caddy 'compose:stop caddy:2'
assert_event_before 'compose:stop caddy:2' 'compose:stop api:2'
assert_log_contains 'health:1|workers-enabled'
assert_log_contains 'metadata:1|workers-enabled:worker-true'
assert_log_contains 'compose:stop api:2'
[[ "$(cat -- "${caddy_running_file}")" == false ]] || {
  printf 'deploy-api-release behavior: Caddy remained open after failed public check\n' >&2
  exit 1
}

printf 'deploy-api-release behavior: PASS\n'
