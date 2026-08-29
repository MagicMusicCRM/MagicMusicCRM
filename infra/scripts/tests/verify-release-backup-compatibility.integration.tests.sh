#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
target_script="${repo_root}/infra/scripts/verify-release-backup-compatibility.sh"
test_root="$(mktemp -d)"
suite_started="${EPOCHREALTIME}"
HARNESS_CASE_TIMEOUT_SECONDS=12

cleanup_test_root() {
  rm -rf -- "${test_root}"
}
trap cleanup_test_root EXIT

fail() {
  printf 'verify-release-backup-compatibility integration: %s\n' "$1" >&2
  exit 1
}

fake_bin="${test_root}/bin"
mkdir -p "${fake_bin}"

cat >"${fake_bin}/docker" <<'FAKE_DOCKER'
#!/usr/bin/env bash
set -euo pipefail

record() {
  {
    printf 'docker'
    for value in "$@"; do
      printf '|%q' "${value}"
    done
    printf '\n'
  } >>"${FAKE_LOG}"
}

value_after() {
  local wanted="$1"
  shift
  local previous=""
  for value in "$@"; do
    if [[ "${previous}" == "${wanted}" ]]; then
      printf '%s' "${value}"
      return 0
    fi
    previous="${value}"
  done
  return 1
}

has_value() {
  local wanted="$1"
  shift
  local value
  for value in "$@"; do
    [[ "${value}" != "${wanted}" ]] || return 0
  done
  return 1
}

record "$@"
if [[ -n "${BACKUP_PASSPHRASE+x}" ]]; then
  printf 'docker|leaked-backup-passphrase\n' >>"${FAKE_LOG}"
  exit 91
fi

mkdir -p \
  "${FAKE_RESOURCE_DIR}/containers" \
  "${FAKE_RESOURCE_DIR}/networks" \
  "${FAKE_RESOURCE_DIR}/volumes"

case "${1:-}" in
  image)
    [[ "${2:-}" == inspect ]] || exit 92
    image_ref="${3:-}"
    case "${image_ref}" in
      "${CANDIDATE_TAG}")
        [[ "${FAKE_PHASE}" != candidate-image-resolve ]] || exit 41
        printf '%s|%s|%s|magiccrm|CMD wget /api/health/ready\n' \
          "${CANDIDATE_ID}" "${CANDIDATE_REVISION}" "${CANDIDATE_VERSION}"
        ;;
      "${ROLLBACK_TAG}")
        [[ "${FAKE_PHASE}" != rollback-image-resolve ]] || exit 42
        printf '%s|%s|%s|magiccrm|CMD wget /api/health/ready\n' \
          "${ROLLBACK_ID}" "${ROLLBACK_REVISION}" "${ROLLBACK_VERSION}"
        ;;
      "${POSTGRES_TAG}")
        [[ "${FAKE_PHASE}" != postgres-image-resolve ]] || exit 43
        printf '%s\n' "${POSTGRES_ID}"
        ;;
      *) exit 44 ;;
    esac
    ;;
  network)
    case "${2:-}" in
      create)
        has_value --internal "$@" || exit 45
        resource_name="${*: -1}"
        touch "${FAKE_RESOURCE_DIR}/networks/${resource_name}"
        [[ "${FAKE_PHASE}" != network-create ]] || exit 46
        printf '%s\n' "${resource_name}"
        ;;
      rm)
        resource_name="${*: -1}"
        rm -f -- "${FAKE_RESOURCE_DIR}/networks/${resource_name}"
        ;;
      inspect)
        resource_name="${*: -1}"
        [[ -f "${FAKE_RESOURCE_DIR}/networks/${resource_name}" ]]
        ;;
      *) exit 47 ;;
    esac
    ;;
  volume)
    case "${2:-}" in
      create)
        resource_name="${*: -1}"
        touch "${FAKE_RESOURCE_DIR}/volumes/${resource_name}"
        [[ "${FAKE_PHASE}" != volume-create ]] || exit 48
        printf '%s\n' "${resource_name}"
        ;;
      rm)
        resource_name="${*: -1}"
        rm -f -- "${FAKE_RESOURCE_DIR}/volumes/${resource_name}"
        ;;
      inspect)
        resource_name="${*: -1}"
        [[ -f "${FAKE_RESOURCE_DIR}/volumes/${resource_name}" ]]
        ;;
      *) exit 49 ;;
    esac
    ;;
  container)
    [[ "${2:-}" == inspect ]] || exit 50
    resource_name="${*: -1}"
    [[ -f "${FAKE_RESOURCE_DIR}/containers/${resource_name}" ]]
    ;;
  rm)
    resource_name="${*: -1}"
    rm -f -- "${FAKE_RESOURCE_DIR}/containers/${resource_name}"
    ;;
  exec)
    joined='|'
    for value in "$@"; do joined+="${value}|"; done
    if [[ "${joined}" == *'|pg_isready|'* ]]; then
      [[ "${FAKE_PHASE}" != postgres-ready ]] || exit 65
      exit 0
    fi
    if [[ "${joined}" == *'|pg_restore|'* ]]; then
      cat >/dev/null
      [[ "${FAKE_PHASE}" != pg-restore ]] || exit 66
      exit 0
    fi
    if [[ "${joined}" == *'|psql|'* ]]; then
      if [[ -f "${FAKE_RESOURCE_DIR}/migration-head" ]]; then
        cat "${FAKE_RESOURCE_DIR}/migration-head"
      else
        printf '%s\n' "${EXPECTED_MIGRATION}"
      fi
      exit 0
    fi
    exit 51
    ;;
  run)
    shift
    container_name="$(value_after --name "$@")" || exit 52
    network_name="$(value_after --network "$@")" || exit 53
    [[ "${network_name}" == "${EXPECTED_NETWORK}" ]] || exit 54
    has_value --pull "$@" || exit 55
    [[ "$(value_after --pull "$@")" == never ]] || exit 56

    image_id=""
    for value in "$@"; do
      case "${value}" in
        "${CANDIDATE_ID}"|"${ROLLBACK_ID}"|"${POSTGRES_ID}")
          image_id="${value}"
          ;;
        "${CANDIDATE_TAG}"|"${ROLLBACK_TAG}"|"${POSTGRES_TAG}")
          exit 57
          ;;
      esac
    done
    [[ -n "${image_id}" ]] || exit 58
    touch "${FAKE_RESOURCE_DIR}/containers/${container_name}"
    joined='|'
    for value in "$@"; do joined+="${value}|"; done

    if [[ "${image_id}" == "${POSTGRES_ID}" ]]; then
      [[ "${joined}" == *"source=${EXPECTED_VOLUME}"* ]] || exit 59
      [[ "${FAKE_PHASE}" != postgres-run ]] || exit 60
      printf 'fake-postgres-container\n'
      exit 0
    fi

    [[ "${joined}" != *'|--mount|'* ]] || exit 61
    if [[ "${image_id}" == "${CANDIDATE_ID}" &&
      "${joined}" == *'|dist/db/migrate.js|up|'* ]]; then
      stage=candidate-migrate
    elif [[ "${image_id}" == "${CANDIDATE_ID}" &&
      "${joined}" == *'|dist/migration/commerce/v7/commerce-data.js|'* ]]; then
      stage=candidate-reconcile
    elif [[ "${image_id}" == "${ROLLBACK_ID}" &&
      "${joined}" == *'|dist/db/migrate.js|up|'* ]]; then
      stage=rollback-migrate
    elif [[ "${image_id}" == "${ROLLBACK_ID}" &&
      "${joined}" == *'|dist/migration/commerce/v7/commerce-data.js|'* ]]; then
      stage=rollback-reconcile
    elif [[ "${image_id}" == "${ROLLBACK_ID}" &&
      "${joined}" == *'|node|-e|'* ]]; then
      stage=rollback-readiness
    else
      exit 62
    fi

    if [[ "${FAKE_BLOCK_STAGE:-}" == "${stage}" ]]; then
      printf '%s\n' "$$" >"${FAKE_BLOCK_PID_FILE}"
      printf 'blocked-child|start|%s|pid=%s\n' "${stage}" "$$" >>"${FAKE_LOG}"
      trap 'printf "blocked-child|killed|HUP\n" >>"${FAKE_LOG}"; exit 129' HUP
      trap 'printf "blocked-child|killed|INT\n" >>"${FAKE_LOG}"; exit 130' INT
      trap 'printf "blocked-child|killed|TERM\n" >>"${FAKE_LOG}"; exit 143' TERM
      if [[ "${FAKE_SIGNAL_STAGE:-}" == "${stage}" ]]; then
        runner_pid="$(awk '/^PPid:/ {print $2}' "/proc/${PPID}/status")"
        kill -s "${FAKE_SIGNAL}" "${runner_pid}"
      fi
      while :; do sleep 10; done
    fi
    [[ "${FAKE_PHASE}" != "${stage}" ]] || exit 63

    case "${stage}" in
      candidate-migrate)
        printf '%s\n' "${EXPECTED_MIGRATION}" \
          >"${FAKE_RESOURCE_DIR}/migration-head"
        printf 'Applied migrations: %s\n' "${EXPECTED_MIGRATION}"
        ;;
      candidate-reconcile|rollback-reconcile)
        printf '{"backfill":null,"issues":[]}\n'
        ;;
      rollback-migrate)
        printf 'Applied migrations: none\n'
        ;;
      rollback-readiness) ;;
    esac
    rm -f -- "${FAKE_RESOURCE_DIR}/containers/${container_name}"
    ;;
  *) exit 64 ;;
esac
FAKE_DOCKER

cat >"${fake_bin}/openssl" <<'FAKE_OPENSSL'
#!/usr/bin/env bash
set -euo pipefail

{
  printf 'openssl'
  for value in "$@"; do
    printf '|%q' "${value}"
  done
  printf '\n'
} >>"${FAKE_LOG}"

if [[ "${1:-}" == rand ]]; then
  [[ -z "${BACKUP_PASSPHRASE+x}" ]] || exit 71
  case "${3:-}" in
    8) printf '0123456789abcdef\n' ;;
    32) printf '%064d\n' 0 ;;
    *) exit 72 ;;
  esac
  exit 0
fi

[[ "${1:-}" == enc ]] || exit 73
[[ "${BACKUP_PASSPHRASE:-}" == "${FAKE_EXPECTED_PASSPHRASE}" ]] || exit 74
[[ -z "${BACKUP_ENV+x}" ]] || exit 75
printf 'openssl-env|passphrase=expected|backup-env=absent\n' >>"${FAKE_LOG}"

previous=""
output_path=""
for value in "$@"; do
  if [[ "${previous}" == -out ]]; then
    output_path="${value}"
  fi
  previous="${value}"
done
[[ -n "${output_path}" ]] || exit 76
printf 'fake decrypted archive\n' >"${output_path}"
[[ "${FAKE_PHASE}" != decrypt ]] || exit 77
FAKE_OPENSSL

cat >"${fake_bin}/tar" <<'FAKE_TAR'
#!/usr/bin/env bash
set -euo pipefail

[[ -z "${BACKUP_PASSPHRASE+x}" ]] || exit 81
{
  printf 'tar'
  for value in "$@"; do
    printf '|%q' "${value}"
  done
  printf '\n'
} >>"${FAKE_LOG}"

case "${1:-}" in
  -tzf)
    [[ "${FAKE_PHASE}" != tar-list ]] || exit 82
    printf './\n./postgres.dump\n./manifest.txt\n./SHA256SUMS\n'
    ;;
  -tvzf)
    [[ "${FAKE_PHASE}" != tar-types ]] || exit 83
    printf 'drwx------ root/root 0 2026-01-01 00:00 ./\n'
    printf -- '-rw------- root/root 4 2026-01-01 00:00 ./postgres.dump\n'
    printf -- '-rw------- root/root 8 2026-01-01 00:00 ./manifest.txt\n'
    printf -- '-rw------- root/root 1 2026-01-01 00:00 ./SHA256SUMS\n'
    ;;
  --no-same-owner)
    destination=""
    previous=""
    for value in "$@"; do
      if [[ "${previous}" == -C ]]; then
        destination="${value}"
      fi
      previous="${value}"
    done
    [[ -n "${destination}" ]] || exit 84
    printf 'fake postgres dump\n' >"${destination}/postgres.dump"
    printf 'fake manifest\n' >"${destination}/manifest.txt"
    (
      cd "${destination}"
      sha256sum postgres.dump manifest.txt >SHA256SUMS
    )
    [[ "${FAKE_PHASE}" != tar-extract ]] || exit 85
    ;;
  *) exit 86 ;;
esac
FAKE_TAR

cat >"${fake_bin}/realpath" <<'FAKE_REALPATH'
#!/usr/bin/env bash
set -euo pipefail
{
  printf 'realpath'
  for value in "$@"; do printf '|%q' "${value}"; done
  printf '\n'
} >>"${FAKE_LOG}"
case "${1:-}" in -e) shift ;; esac
case "${1:-}" in --) shift ;; esac
exec /usr/bin/realpath "$@"
FAKE_REALPATH

cat >"${fake_bin}/sha256sum" <<'FAKE_SHA256SUM'
#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${FAKE_LOG:-}" ]]; then
  {
    printf 'sha256sum'
    for value in "$@"; do
      printf '|%q' "${value}"
    done
    printf '\n'
  } >>"${FAKE_LOG}"
fi

block_checksum_if_requested() {
  local stage=checksum
  local runner_pid runner_cmdline
  [[ "${FAKE_BLOCK_STAGE:-}" == "${stage}" ]] || return 0

  printf '%s\n' "$$" >"${FAKE_BLOCK_PID_FILE}"
  printf 'blocked-child|start|%s|pid=%s\n' "${stage}" "$$" >>"${FAKE_LOG}"
  trap 'printf "blocked-child|killed|HUP\n" >>"${FAKE_LOG}"; exit 129' HUP
  trap 'printf "blocked-child|killed|INT\n" >>"${FAKE_LOG}"; exit 130' INT
  trap 'printf "blocked-child|killed|TERM\n" >>"${FAKE_LOG}"; exit 143' TERM

  if [[ "${FAKE_SIGNAL_STAGE:-}" == "${stage}" ]]; then
    runner_pid="${PPID}"
    while [[ "${runner_pid}" =~ ^[0-9]+$ && "${runner_pid}" -gt 1 ]]; do
      runner_cmdline="$(tr '\0' ' ' <"/proc/${runner_pid}/cmdline")"
      if [[ "${runner_cmdline}" == *verify-release-backup-compatibility.sh* ]]; then
        kill -s "${FAKE_SIGNAL}" "${runner_pid}"
        break
      fi
      runner_pid="$(awk '/^PPid:/ {print $2}' "/proc/${runner_pid}/status")"
    done
  fi
  while :; do sleep 10; done
}

if [[ "${1:-}" == -- ]]; then
  shift
  exec /usr/bin/sha256sum "$@"
fi
if [[ "${1:-}" == -c ]]; then
  block_checksum_if_requested
  [[ "${FAKE_PHASE}" != checksum ]] || exit 87
  shift
  checksum_file=""
  for value in "$@"; do
    case "${value}" in
      --strict|--quiet) ;;
      *) checksum_file="${value}" ;;
    esac
  done
  [[ -n "${checksum_file}" ]] || exit 89
  exec /usr/bin/sha256sum -cs "${checksum_file}"
fi
exec /usr/bin/sha256sum "$@"
FAKE_SHA256SUM

cat >"${fake_bin}/timeout" <<'FAKE_TIMEOUT'
#!/usr/bin/env bash
set -euo pipefail
signal_name=TERM
kill_after=1s
while [[ $# -gt 0 ]]; do
  case "$1" in
    --foreground) shift ;;
    --signal=*) signal_name="${1#*=}"; shift ;;
    --kill-after=*) kill_after="${1#*=}"; shift ;;
    *) break ;;
  esac
done
[[ $# -ge 2 ]] || exit 88
duration="$1"
shift
set +e
/usr/bin/timeout -s "${signal_name}" -k "${kill_after}" \
  "${duration}" "$@"
status=$?
set -e
if [[ "${status}" == 137 || "${status}" == 143 ]]; then
  printf 'timeout|expired|status=%s\n' "${status}" >>"${FAKE_LOG}"
  exit 124
fi
exit "${status}"
FAKE_TIMEOUT

chmod 700 \
  "${fake_bin}/docker" "${fake_bin}/openssl" "${fake_bin}/tar" \
  "${fake_bin}/realpath" "${fake_bin}/sha256sum" "${fake_bin}/timeout"
export PATH="${fake_bin}:${PATH}"

CANDIDATE_TAG='magicmusiccrm-server:candidate-test'
ROLLBACK_TAG='magicmusiccrm-server:rollback-test'
POSTGRES_TAG='postgres:test'
CANDIDATE_ID="sha256:$(printf '%064d' 1)"
ROLLBACK_ID="sha256:$(printf '%064d' 2)"
POSTGRES_ID="sha256:$(printf '%064d' 3)"
CANDIDATE_REVISION="$(printf 'a%.0s' {1..40})"
ROLLBACK_REVISION="$(printf 'b%.0s' {1..40})"
CANDIDATE_VERSION='1.5.21+201'
ROLLBACK_VERSION='1.5.18+198'
EXPECTED_MIGRATION='0142_schedule_plan_series_subscription_snapshot'
EXPECTED_NETWORK='magiccrm-backup-drill-0123456789abcdef-network'
EXPECTED_VOLUME='magiccrm-backup-drill-0123456789abcdef-data'
FAKE_EXPECTED_PASSPHRASE='CorrectHorseBattery42'

export \
  CANDIDATE_TAG ROLLBACK_TAG POSTGRES_TAG \
  CANDIDATE_ID ROLLBACK_ID POSTGRES_ID \
  CANDIDATE_REVISION ROLLBACK_REVISION \
  CANDIDATE_VERSION ROLLBACK_VERSION EXPECTED_MIGRATION \
  EXPECTED_NETWORK EXPECTED_VOLUME FAKE_EXPECTED_PASSPHRASE

last_case_dir=""
run_case() {
  local name="$1"
  local phase="${2:-}"
  local expected_status="$3"
  local secret_mode="${4:-600}"
  local secret_content="${5:-BACKUP_PASSPHRASE=${FAKE_EXPECTED_PASSPHRASE}}"
  local signal_stage="${6:-}"
  local signal_name="${7:-}"
  local argument_variant="${8:-}"
  local block_stage="${9:-}"
  local timeout_variant="${10:-}"
  local case_dir="${test_root}/${name}"
  local backup_root="${case_dir}/backups/encrypted"
  local backup_archive="${backup_root}/fixture.tgz.enc"
  local backup_env="${case_dir}/.backup.env"
  local rollback_revision_arg="${ROLLBACK_REVISION}"
  local rollback_version_arg="${ROLLBACK_VERSION}"
  local migration_timeout=3
  local archive_timeout=3
  local status blocked_pid

  mkdir -p \
    "${backup_root}" \
    "${case_dir}/resources/containers" \
    "${case_dir}/resources/networks" \
    "${case_dir}/resources/volumes"
  printf 'fake encrypted backup\n' >"${backup_archive}"
  sha256sum "${backup_archive}" >"${backup_archive}.sha256"
  printf '%s\n' "${secret_content}" >"${backup_env}"
  chmod "${secret_mode}" "${backup_env}"
  : >"${case_dir}/commands.log"
  if [[ "${argument_variant}" == same-revision ]]; then
    rollback_revision_arg="${CANDIDATE_REVISION}"
  elif [[ "${argument_variant}" == same-version ]]; then
    rollback_version_arg="${CANDIDATE_VERSION}"
  fi
  if [[ "${timeout_variant}" == short ]]; then
    migration_timeout=1
  elif [[ "${timeout_variant}" == archive-short ]]; then
    archive_timeout=1
  fi

  if compgen -G '/tmp/magiccrm-backup-drill-0123456789abcdef.*' >/dev/null; then
    fail "pre-existing deterministic drill temporary directory"
  fi
  if compgen -G '/tmp/magiccrm-backup-drill-control.*' >/dev/null; then
    fail "pre-existing drill control directory"
  fi

  set +e
  BACKUP_PASSPHRASE='hostile-inherited-secret' \
  BACKUP_ROOT="${backup_root}" \
  BACKUP_ENV="${backup_env}" \
  POSTGRES_IMAGE="${POSTGRES_TAG}" \
  WAIT_SECONDS=1 \
  DOCKER_TIMEOUT_SECONDS=3 \
  CRYPTO_TIMEOUT_SECONDS=3 \
  ARCHIVE_TIMEOUT_SECONDS="${archive_timeout}" \
  RESTORE_TIMEOUT_SECONDS=3 \
  MIGRATION_TIMEOUT_SECONDS="${migration_timeout}" \
  RECONCILE_TIMEOUT_SECONDS=3 \
  CLEANUP_TIMEOUT_SECONDS=2 \
  KILL_GRACE_SECONDS=1 \
  FAKE_LOG="${case_dir}/commands.log" \
  FAKE_RESOURCE_DIR="${case_dir}/resources" \
  FAKE_PHASE="${phase}" \
  FAKE_SIGNAL_STAGE="${signal_stage}" \
  FAKE_SIGNAL="${signal_name}" \
  FAKE_BLOCK_STAGE="${block_stage}" \
  FAKE_BLOCK_PID_FILE="${case_dir}/blocked-child.pid" \
    /usr/bin/timeout -s KILL "${HARNESS_CASE_TIMEOUT_SECONDS}s" \
    bash "${target_script}" \
      --backup "${backup_archive}" \
      --candidate-image "${CANDIDATE_TAG}" \
      --candidate-revision "${CANDIDATE_REVISION}" \
      --candidate-version "${CANDIDATE_VERSION}" \
      --rollback-image "${ROLLBACK_TAG}" \
      --rollback-revision "${rollback_revision_arg}" \
      --rollback-version "${rollback_version_arg}" \
      --expected-migration "${EXPECTED_MIGRATION}" \
      >"${case_dir}/output.log" 2>&1
  status=$?
  set -e

  [[ "${status}" != 137 ]] ||
    fail "${name}: harness-level ${HARNESS_CASE_TIMEOUT_SECONDS}s deadline expired"

  if [[ "${expected_status}" == nonzero ]]; then
    if [[ "${status}" == 0 ]]; then
      sed -n '1,80p' "${case_dir}/output.log" >&2
      fail "${name}: expected failure"
    fi
  elif [[ "${status}" != "${expected_status}" ]]; then
    sed -n '1,80p' "${case_dir}/output.log" >&2
    sed -n '1,80p' "${case_dir}/commands.log" >&2
    fail "${name}: expected status ${expected_status}, got ${status}"
  fi

  for resource_kind in containers networks volumes; do
    if find "${case_dir}/resources/${resource_kind}" \
      -type f -print -quit | grep -q .; then
      fail "${name}: isolated Docker ${resource_kind} were not cleaned"
    fi
  done
  if compgen -G '/tmp/magiccrm-backup-drill-0123456789abcdef.*' >/dev/null; then
    fail "${name}: decrypted temporary directory was not cleaned"
  fi
  if compgen -G '/tmp/magiccrm-backup-drill-control.*' >/dev/null; then
    fail "${name}: control directory was not cleaned"
  fi
  if [[ -f "${case_dir}/blocked-child.pid" ]]; then
    blocked_pid="$(<"${case_dir}/blocked-child.pid")"
    for _ in {1..20}; do
      kill -0 "${blocked_pid}" >/dev/null 2>&1 || break
      sleep 0.05
    done
    if kill -0 "${blocked_pid}" >/dev/null 2>&1; then
      fail "${name}: tracked blocking child survived cleanup"
    fi
  fi
  if grep -Fq "${FAKE_EXPECTED_PASSPHRASE}" "${case_dir}/commands.log"; then
    fail "${name}: passphrase leaked into recorded argv"
  fi
  if grep -Fq 'docker|leaked-backup-passphrase' "${case_dir}/commands.log"; then
    fail "${name}: backup passphrase leaked into Docker environment"
  fi
  last_case_dir="${case_dir}"
}

run_case success '' 0
success_log="${last_case_dir}/commands.log"
grep -Fq 'VERIFY_RELEASE_BACKUP_COMPATIBILITY|PASS' \
  "${last_case_dir}/output.log" || fail 'success marker is missing'
[[ "$(grep -Fc "docker|image|inspect|${CANDIDATE_TAG}|" "${success_log}")" == 1 ]] ||
  fail 'candidate tag was not resolved exactly once'
[[ "$(grep -Fc "docker|image|inspect|${ROLLBACK_TAG}|" "${success_log}")" == 1 ]] ||
  fail 'rollback tag was not resolved exactly once'
[[ "$(grep -Fc "docker|image|inspect|${POSTGRES_TAG}|" "${success_log}")" == 1 ]] ||
  fail 'PostgreSQL tag was not resolved exactly once'
if grep '^docker|run|' "${success_log}" |
  grep -Eq "${CANDIDATE_TAG}|${ROLLBACK_TAG}|${POSTGRES_TAG}"; then
  fail 'a Docker run used a mutable tag after resolution'
fi
[[ "$(grep -c '^docker|run|' "${success_log}")" == 6 ]] ||
  fail 'unexpected Docker run inventory'
grep -Fq 'docker|network|create|--internal|' "${success_log}" ||
  fail 'internal network creation was not recorded'
grep -Fq 'openssl-env|passphrase=expected|backup-env=absent' "${success_log}" ||
  fail 'OpenSSL environment isolation was not proved'

run_case mode-rejection '' nonzero 644
if grep -Eq '^(docker|openssl|tar)\|' "${last_case_dir}/commands.log"; then
  fail 'unsafe secret mode reached crypto, archive or Docker runtime'
fi

run_case extra-key '' nonzero 600 \
  $'BACKUP_PASSPHRASE=CorrectHorseBattery42\nEXTRA_KEY=value'
run_case set-x '' nonzero 600 \
  $'set -x\nBACKUP_PASSPHRASE=CorrectHorseBattery42'
sentinel="${test_root}/shell-syntax-executed"
run_case shell-syntax '' nonzero 600 \
  "BACKUP_PASSPHRASE=\$(touch ${sentinel})"
[[ ! -e "${sentinel}" ]] || fail 'backup dotenv shell syntax was executed'

run_case same-revision '' nonzero 600 \
  "BACKUP_PASSPHRASE=${FAKE_EXPECTED_PASSPHRASE}" '' '' same-revision
run_case same-version '' nonzero 600 \
  "BACKUP_PASSPHRASE=${FAKE_EXPECTED_PASSPHRASE}" '' '' same-version

failure_phases=(
  decrypt tar-list tar-types tar-extract checksum network-create volume-create
  postgres-run postgres-ready pg-restore candidate-migrate candidate-reconcile
  rollback-migrate rollback-reconcile rollback-readiness
)
for phase in "${failure_phases[@]}"; do
  run_case "failure-${phase}" "${phase}" nonzero
done

run_case timeout-child '' nonzero 600 \
  "BACKUP_PASSPHRASE=${FAKE_EXPECTED_PASSPHRASE}" '' '' '' \
  candidate-migrate short
grep -Fq 'timeout|expired|' "${last_case_dir}/commands.log" ||
  fail 'timeout did not terminate the blocking child process group'

run_case timeout-checksum '' nonzero 600 \
  "BACKUP_PASSPHRASE=${FAKE_EXPECTED_PASSPHRASE}" '' '' '' \
  checksum archive-short
grep -Fq 'timeout|expired|' "${last_case_dir}/commands.log" ||
  fail 'archive timeout did not terminate the blocking checksum process group'

run_case signal-checksum-hup '' 129 600 \
  "BACKUP_PASSPHRASE=${FAKE_EXPECTED_PASSPHRASE}" checksum HUP '' checksum
run_case signal-checksum-int '' 130 600 \
  "BACKUP_PASSPHRASE=${FAKE_EXPECTED_PASSPHRASE}" checksum INT '' checksum
run_case signal-checksum-term '' 143 600 \
  "BACKUP_PASSPHRASE=${FAKE_EXPECTED_PASSPHRASE}" checksum TERM '' checksum

run_case signal-hup '' 129 600 \
  "BACKUP_PASSPHRASE=${FAKE_EXPECTED_PASSPHRASE}" candidate-migrate HUP '' \
  candidate-migrate
run_case signal-int '' 130 600 \
  "BACKUP_PASSPHRASE=${FAKE_EXPECTED_PASSPHRASE}" candidate-migrate INT '' \
  candidate-migrate
run_case signal-term '' 143 600 \
  "BACKUP_PASSPHRASE=${FAKE_EXPECTED_PASSPHRASE}" candidate-migrate TERM '' \
  candidate-migrate

suite_runtime="$(awk -v started="${suite_started}" -v ended="${EPOCHREALTIME}" \
  'BEGIN { printf "%.3f", ended - started }')"
printf 'verify-release-backup-compatibility integration: PASS (%d failure phases + migration/checksum timeouts + HUP/INT/TERM at migration and checksum, runtime=%ss)\n' \
  "${#failure_phases[@]}" "${suite_runtime}"
