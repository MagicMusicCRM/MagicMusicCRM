#!/usr/bin/env bash
set -Eeuo pipefail

umask 077
unset BACKUP_PASSPHRASE

BACKUP_ROOT="${BACKUP_ROOT:-/opt/magicmusiccrm/backups/encrypted}"
BACKUP_ENV="${BACKUP_ENV:-/opt/magicmusiccrm/infra/staging/.backup.env}"
POSTGRES_IMAGE="${POSTGRES_IMAGE:-postgres:16.4-alpine}"
WAIT_SECONDS="${WAIT_SECONDS:-90}"
DOCKER_TIMEOUT_SECONDS="${DOCKER_TIMEOUT_SECONDS:-30}"
CRYPTO_TIMEOUT_SECONDS="${CRYPTO_TIMEOUT_SECONDS:-300}"
ARCHIVE_TIMEOUT_SECONDS="${ARCHIVE_TIMEOUT_SECONDS:-300}"
RESTORE_TIMEOUT_SECONDS="${RESTORE_TIMEOUT_SECONDS:-600}"
MIGRATION_TIMEOUT_SECONDS="${MIGRATION_TIMEOUT_SECONDS:-600}"
RECONCILE_TIMEOUT_SECONDS="${RECONCILE_TIMEOUT_SECONDS:-300}"
CLEANUP_TIMEOUT_SECONDS="${CLEANUP_TIMEOUT_SECONDS:-15}"
KILL_GRACE_SECONDS="${KILL_GRACE_SECONDS:-5}"

backup_archive=""
candidate_image=""
candidate_revision=""
candidate_version=""
rollback_image=""
rollback_revision=""
rollback_version=""
expected_migration=""
migration_baseline=""

usage() {
  cat <<'EOF'
Usage: verify-release-backup-compatibility.sh [options]

Required options:
  --backup PATH
  --candidate-image IMAGE
  --candidate-revision FULL_40_CHAR_SHA
  --candidate-version VERSION
  --rollback-image IMAGE
  --rollback-revision FULL_40_CHAR_SHA
  --rollback-version VERSION
  --expected-migration ID

Optional:
  --migration-baseline PATH_TO_REVIEWED_JSON

This drill restores only into a random, internal Docker network and a new
temporary PostgreSQL volume. It never invokes production Compose, mounts a
live volume, runs a down migration, or writes to the production database.
EOF
}

die() {
  printf 'verify-release-backup-compatibility: %s\n' "$1" >&2
  exit 1
}

require_option_value() {
  if [[ $# -lt 2 || -z "${2}" ]]; then
    die "missing value for ${1}"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --backup)
      require_option_value "$@"; backup_archive="$2"; shift 2 ;;
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
    --expected-migration)
      require_option_value "$@"; expected_migration="$2"; shift 2 ;;
    --migration-baseline)
      require_option_value "$@"; migration_baseline="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      die "unknown option: $1" ;;
  esac
done

for command_name in \
  docker openssl realpath sha256sum tar mktemp grep stat wc tr sleep \
  basename id setsid timeout; do
  command -v "${command_name}" >/dev/null 2>&1 ||
    die "required command is unavailable: ${command_name}"
done

for required_name in \
  backup_archive candidate_image candidate_revision candidate_version \
  rollback_image rollback_revision rollback_version expected_migration; do
  [[ -n "${!required_name}" ]] || die "${required_name} is required"
done

[[ "${candidate_image}" =~ ^magicmusiccrm-server:[A-Za-z0-9_.+-]+$ ]] ||
  die "candidate image must be an exact magicmusiccrm-server tag"
[[ "${rollback_image}" =~ ^magicmusiccrm-server:[A-Za-z0-9_.+-]+$ ]] ||
  die "rollback image must be an exact magicmusiccrm-server tag"
[[ "${candidate_image}" != "${rollback_image}" ]] ||
  die "candidate and rollback image tags must be different"
[[ "${candidate_revision}" =~ ^[0-9a-f]{40}$ ]] ||
  die "candidate revision must be a full lowercase 40-character SHA"
[[ "${rollback_revision}" =~ ^[0-9a-f]{40}$ ]] ||
  die "rollback revision must be a full lowercase 40-character SHA"
[[ "${candidate_revision}" != "${rollback_revision}" ]] ||
  die "candidate and rollback revision labels must be different"
[[ "${candidate_version}" =~ ^[A-Za-z0-9][A-Za-z0-9.+-]{0,79}$ ]] ||
  die "candidate version label is invalid"
[[ "${rollback_version}" =~ ^[A-Za-z0-9][A-Za-z0-9.+-]{0,79}$ ]] ||
  die "rollback version label is invalid"
[[ "${candidate_version}" != "${rollback_version}" ]] ||
  die "candidate and rollback version labels must be different"
[[ "${expected_migration}" =~ ^[0-9]{4}_[a-z0-9_]+$ ]] ||
  die "expected migration ID is invalid"
if [[ -n "${migration_baseline}" ]]; then
  migration_baseline="$(realpath -e -- "${migration_baseline}")" || die "baseline file is missing"
  [[ -f "${migration_baseline}" && "${migration_baseline}" == *.json ]] || die "baseline must be a JSON file"
  [[ "$(wc -c < "${migration_baseline}")" -le 1048576 ]] || die "baseline file is too large"
fi
[[ "${WAIT_SECONDS}" =~ ^[1-9][0-9]*$ ]] ||
  die "WAIT_SECONDS must be a positive integer"
for timeout_name in \
  DOCKER_TIMEOUT_SECONDS CRYPTO_TIMEOUT_SECONDS ARCHIVE_TIMEOUT_SECONDS \
  RESTORE_TIMEOUT_SECONDS MIGRATION_TIMEOUT_SECONDS \
  RECONCILE_TIMEOUT_SECONDS CLEANUP_TIMEOUT_SECONDS KILL_GRACE_SECONDS; do
  [[ "${!timeout_name}" =~ ^[1-9][0-9]*$ ]] ||
    die "${timeout_name} must be a positive integer"
done
[[ "${backup_archive}" == /* ]] || die "backup path must be absolute"
[[ ! -L "${backup_archive}" ]] || die "backup archive path must not be a symlink"

backup_root_real="$(realpath -e -- "${BACKUP_ROOT}")" ||
  die "encrypted backup root is missing"
[[ -d "${backup_root_real}" ]] || die "encrypted backup root is not a directory"
backup_archive="$(realpath -e -- "${backup_archive}")" ||
  die "backup archive does not exist"
[[ -f "${backup_archive}" && ! -L "${backup_archive}" ]] ||
  die "backup archive must be a regular, non-symlink file"
[[ "${backup_archive}" == "${backup_root_real}/"* ]] ||
  die "backup archive escapes the encrypted backup root"
[[ "${backup_archive}" == *.tgz.enc ]] ||
  die "backup archive must end with .tgz.enc"

encrypted_checksum_file="${backup_archive}.sha256"
[[ -f "${encrypted_checksum_file}" && ! -L "${encrypted_checksum_file}" ]] ||
  die "encrypted backup checksum sidecar is missing"
sidecar_line_count="$(wc -l <"${encrypted_checksum_file}" | tr -d '[:space:]')"
[[ "${sidecar_line_count}" == 1 ]] ||
  die "encrypted backup checksum sidecar must contain exactly one line"
IFS= read -r sidecar_line <"${encrypted_checksum_file}"
[[ "${sidecar_line}" =~ ^[0-9a-f]{64}[[:space:]] ]] ||
  die "encrypted backup checksum sidecar is malformed"
expected_encrypted_sha="${sidecar_line:0:64}"
actual_encrypted_sha="$(sha256sum -- "${backup_archive}")"
actual_encrypted_sha="${actual_encrypted_sha:0:64}"
[[ "${actual_encrypted_sha}" == "${expected_encrypted_sha}" ]] ||
  die "encrypted backup checksum mismatch"
unset sidecar_line expected_encrypted_sha actual_encrypted_sha

[[ -f "${BACKUP_ENV}" && ! -L "${BACKUP_ENV}" ]] ||
  die "backup secret file is missing"
backup_env_owner="$(stat -c '%u' -- "${BACKUP_ENV}")"
[[ "${backup_env_owner}" == "$(id -u)" ]] ||
  die "backup secret file must be owned by the current user"
unset backup_env_owner
backup_env_mode="$(stat -c '%a' -- "${BACKUP_ENV}")"
[[ "${backup_env_mode}" == 400 || "${backup_env_mode}" == 600 ]] ||
  die "backup secret file mode must be 0400 or 0600"
unset backup_env_mode

control_dir="$(mktemp -d "/tmp/magiccrm-backup-drill-control.XXXXXXXX")"
readonly control_dir
chmod 700 "${control_dir}"
active_child_pid=""
cleanup_started=0
capture_sequence=0
tmp_dir=""
postgres_container=""
network_name=""
volume_name=""
candidate_migrate_container=""
candidate_reconcile_container=""
rollback_migrate_container=""
rollback_reconcile_container=""
rollback_readiness_container=""
database_password=""
candidate_head=""
rollback_head=""
final_head=""
network_created=0
volume_created=0

forward_active_child() {
  local signal_name="$1"
  [[ -n "${active_child_pid}" ]] || return 0
  kill -s "${signal_name}" -- "-${active_child_pid}" >/dev/null 2>&1 ||
    kill -s "${signal_name}" "${active_child_pid}" >/dev/null 2>&1 || true
}

handle_signal() {
  local signal_name="$1"
  local exit_status="$2"
  forward_active_child "${signal_name}"
  [[ "${cleanup_started}" == 0 ]] || return 0
  exit "${exit_status}"
}

run_bounded() {
  local timeout_seconds="$1"
  local phase_label="$2"
  local status child_pid
  shift 2

  setsid timeout --foreground --signal=TERM \
    --kill-after="${KILL_GRACE_SECONDS}s" "${timeout_seconds}s" "$@" &
  active_child_pid=$!
  child_pid="${active_child_pid}"
  if wait "${child_pid}"; then
    status=0
  else
    status=$?
  fi
  kill -s KILL -- "-${child_pid}" >/dev/null 2>&1 || true
  active_child_pid=""
  if [[ "${status}" == 124 || "${status}" == 137 ]]; then
    printf 'verify-release-backup-compatibility: phase timed out: %s\n' \
      "${phase_label}" >&2
  fi
  return "${status}"
}

run_bounded_from_file() {
  local timeout_seconds="$1"
  local phase_label="$2"
  local input_file="$3"
  local status child_pid
  shift 3

  [[ -f "${input_file}" && ! -L "${input_file}" ]] || return 1

  setsid timeout --foreground --signal=TERM \
    --kill-after="${KILL_GRACE_SECONDS}s" "${timeout_seconds}s" \
    "$@" <"${input_file}" &
  active_child_pid=$!
  child_pid="${active_child_pid}"
  if wait "${child_pid}"; then
    status=0
  else
    status=$?
  fi
  kill -s KILL -- "-${child_pid}" >/dev/null 2>&1 || true
  active_child_pid=""
  if [[ "${status}" == 124 || "${status}" == 137 ]]; then
    printf 'verify-release-backup-compatibility: phase timed out: %s\n' \
      "${phase_label}" >&2
  fi
  return "${status}"
}

capture_bounded() {
  local output_name="$1"
  local timeout_seconds="$2"
  local phase_label="$3"
  local capture_file captured_value
  shift 3
  ((capture_sequence += 1))
  capture_file="${control_dir}/capture-${capture_sequence}"
  run_bounded "${timeout_seconds}" "${phase_label}" "$@" \
    >"${capture_file}" || return $?
  captured_value="$(<"${capture_file}")"
  printf -v "${output_name}" '%s' "${captured_value}"
}

cleanup() {
  local status=$?
  local cleanup_failed=0 container_name inspect_status
  cleanup_started=1
  set +e
  forward_active_child KILL
  active_child_pid=""
  unset BACKUP_PASSPHRASE backup_passphrase database_password database_url
  for container_name in \
    "${candidate_migrate_container}" "${candidate_reconcile_container}" \
    "${rollback_migrate_container}" "${rollback_reconcile_container}" \
    "${rollback_readiness_container}" "${postgres_container}"; do
    [[ -n "${container_name}" ]] || continue
    run_bounded "${CLEANUP_TIMEOUT_SECONDS}" "inspect ${container_name}" \
      docker container inspect "${container_name}" >/dev/null 2>&1
    inspect_status=$?
    if [[ "${inspect_status}" == 0 ]]; then
      run_bounded "${CLEANUP_TIMEOUT_SECONDS}" "remove ${container_name}" \
        docker rm -f "${container_name}" >/dev/null 2>&1 || cleanup_failed=1
    elif [[ "${inspect_status}" != 1 ]]; then
      cleanup_failed=1
    fi
  done
  if [[ "${network_created}" == 1 && -n "${network_name}" ]]; then
    run_bounded "${CLEANUP_TIMEOUT_SECONDS}" "inspect network" \
      docker network inspect "${network_name}" >/dev/null 2>&1
    inspect_status=$?
    if [[ "${inspect_status}" == 0 ]]; then
      run_bounded "${CLEANUP_TIMEOUT_SECONDS}" "remove network" \
        docker network rm "${network_name}" >/dev/null 2>&1 || cleanup_failed=1
    elif [[ "${inspect_status}" != 1 ]]; then
      cleanup_failed=1
    fi
  fi
  if [[ "${volume_created}" == 1 && -n "${volume_name}" ]]; then
    run_bounded "${CLEANUP_TIMEOUT_SECONDS}" "inspect volume" \
      docker volume inspect "${volume_name}" >/dev/null 2>&1
    inspect_status=$?
    if [[ "${inspect_status}" == 0 ]]; then
      run_bounded "${CLEANUP_TIMEOUT_SECONDS}" "remove volume" \
        docker volume rm -f "${volume_name}" >/dev/null 2>&1 || cleanup_failed=1
    elif [[ "${inspect_status}" != 1 ]]; then
      cleanup_failed=1
    fi
  fi
  if [[ -n "${tmp_dir}" ]]; then
    case "${tmp_dir}" in
      /tmp/magiccrm-backup-drill-*)
        rm -rf -- "${tmp_dir}" || cleanup_failed=1
        [[ ! -e "${tmp_dir}" ]] || cleanup_failed=1
        ;;
      *) cleanup_failed=1 ;;
    esac
  fi
  case "${control_dir}" in
    /tmp/magiccrm-backup-drill-control.*)
      rm -rf -- "${control_dir}" || cleanup_failed=1
      [[ ! -e "${control_dir}" ]] || cleanup_failed=1
      ;;
    *) cleanup_failed=1 ;;
  esac
  if [[ "${cleanup_failed}" == 1 ]]; then
    printf 'verify-release-backup-compatibility: isolated cleanup incomplete\n' >&2
    [[ "${status}" != 0 ]] || status=1
  fi
  exit "${status}"
}
trap cleanup EXIT
trap 'handle_signal HUP 129' HUP
trap 'handle_signal INT 130' INT
trap 'handle_signal TERM 143' TERM

resolve_release_image() {
  local output_name="$1"
  local image_ref="$2"
  local expected_revision="$3"
  local expected_version="$4"
  local label="$5"
  local metadata image_id actual_revision actual_version runtime_user health_command

  capture_bounded metadata "${DOCKER_TIMEOUT_SECONDS}" \
    "resolve ${label} image" docker image inspect "${image_ref}" --format \
    '{{.Id}}|{{index .Config.Labels "org.opencontainers.image.revision"}}|{{index .Config.Labels "org.opencontainers.image.version"}}|{{.Config.User}}|{{join .Config.Healthcheck.Test " "}}' ||
    die "${label} image is not loaded"
  IFS='|' read -r \
    image_id actual_revision actual_version runtime_user health_command \
    <<<"${metadata}"
  [[ "${image_id}" =~ ^sha256:[0-9a-f]{64}$ ]] ||
    die "${label} image ID is invalid"
  [[ "${actual_revision}" == "${expected_revision}" ]] ||
    die "${label} image revision label mismatch"
  [[ "${actual_version}" == "${expected_version}" ]] ||
    die "${label} image version label mismatch"
  [[ "${runtime_user}" == magiccrm ]] ||
    die "${label} image must run as magiccrm"
  [[ "${health_command}" == *'/api/health/ready'* ]] ||
    die "${label} image healthcheck must use readiness"
  printf -v "${output_name}" '%s' "${image_id}"
}

resolve_release_image candidate_image_id \
  "${candidate_image}" "${candidate_revision}" "${candidate_version}" candidate
readonly candidate_image_id
resolve_release_image rollback_image_id \
  "${rollback_image}" "${rollback_revision}" "${rollback_version}" rollback
readonly rollback_image_id
[[ "${candidate_image_id}" != "${rollback_image_id}" ]] ||
  die "candidate and rollback tags resolve to the same image ID"
capture_bounded postgres_image_id "${DOCKER_TIMEOUT_SECONDS}" \
  "resolve PostgreSQL image" \
  docker image inspect "${POSTGRES_IMAGE}" --format '{{.Id}}' ||
  die "isolated PostgreSQL image is not loaded: ${POSTGRES_IMAGE}"
[[ "${postgres_image_id}" =~ ^sha256:[0-9a-f]{64}$ ]] ||
  die "isolated PostgreSQL image ID is invalid"
readonly postgres_image_id

capture_bounded run_id "${CRYPTO_TIMEOUT_SECONDS}" "generate run ID" \
  openssl rand -hex 8 || die "failed to generate isolated resource ID"
readonly run_id
resource_prefix="magiccrm-backup-drill-${run_id}"
readonly resource_prefix
postgres_container="${resource_prefix}-postgres"
readonly postgres_container
network_name="${resource_prefix}-network"
readonly network_name
volume_name="${resource_prefix}-data"
readonly volume_name
candidate_migrate_container="${resource_prefix}-candidate-migrate"
readonly candidate_migrate_container
candidate_reconcile_container="${resource_prefix}-candidate-reconcile"
readonly candidate_reconcile_container
rollback_migrate_container="${resource_prefix}-rollback-migrate"
readonly rollback_migrate_container
rollback_reconcile_container="${resource_prefix}-rollback-reconcile"
readonly rollback_reconcile_container
rollback_readiness_container="${resource_prefix}-rollback-readiness"
readonly rollback_readiness_container
tmp_dir="$(mktemp -d "/tmp/${resource_prefix}.XXXXXXXX")"
readonly tmp_dir
chmod 700 "${tmp_dir}"

set +x
read_backup_passphrase() {
  local secret_file="$1"
  local line raw_value parsed_value="" assignment_count=0

  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ "${line}" != *$'\r'* ]] ||
      die "backup secret file contains unsupported carriage returns"
    [[ "${line}" =~ ^[[:space:]]*$ ]] && continue
    [[ "${line}" =~ ^[[:space:]]*# ]] && continue
    [[ "${line}" == BACKUP_PASSPHRASE=* ]] ||
      die "backup secret file contains an unexpected key or shell syntax"
    ((assignment_count += 1))
    [[ "${assignment_count}" == 1 ]] ||
      die "backup secret file contains duplicate assignments"
    raw_value="${line#BACKUP_PASSPHRASE=}"
    case "${raw_value}" in
      \'*\') parsed_value="${raw_value:1:${#raw_value}-2}" ;;
      \"*\") parsed_value="${raw_value:1:${#raw_value}-2}" ;;
      *) parsed_value="${raw_value}" ;;
    esac
    [[ "${parsed_value}" =~ ^[A-Za-z0-9_./:+,=@%-]+$ &&
       ${#parsed_value} -ge 16 && ${#parsed_value} -le 512 ]] ||
      die "backup passphrase encoding is unsafe or too short"
  done <"${secret_file}"

  [[ "${assignment_count}" == 1 ]] ||
    die "backup secret file must contain exactly one BACKUP_PASSPHRASE"
  printf '%s' "${parsed_value}"
}

backup_passphrase="$(read_backup_passphrase "${BACKUP_ENV}")"
unset BACKUP_ENV
BACKUP_PASSPHRASE="${backup_passphrase}" \
  run_bounded "${CRYPTO_TIMEOUT_SECONDS}" "decrypt backup" openssl enc \
  -d -aes-256-cbc -pbkdf2 -iter 600000 \
  -in "${backup_archive}" \
  -out "${tmp_dir}/backup.tgz" \
  -pass env:BACKUP_PASSPHRASE || die "backup decryption failed"
unset backup_passphrase

run_bounded "${ARCHIVE_TIMEOUT_SECONDS}" "list backup paths" \
  tar -tzf "${tmp_dir}/backup.tgz" >"${tmp_dir}/archive-paths.txt" ||
  die "backup path listing failed"
while IFS= read -r archive_path; do
  normalized_path="${archive_path#./}"
  [[ -z "${normalized_path}" ]] && continue
  [[ "${normalized_path}" != /* && "${normalized_path}" != *\\* ]] ||
    die "backup payload contains an unsafe archive path"
  IFS='/' read -r -a path_parts <<<"${normalized_path}"
  for path_part in "${path_parts[@]}"; do
    [[ "${path_part}" != '..' ]] ||
      die "backup payload contains a parent-directory path"
  done
done <"${tmp_dir}/archive-paths.txt"

run_bounded "${ARCHIVE_TIMEOUT_SECONDS}" "list backup types" \
  tar -tvzf "${tmp_dir}/backup.tgz" >"${tmp_dir}/archive-types.txt" ||
  die "backup type listing failed"
while IFS= read -r archive_entry; do
  archive_type="${archive_entry:0:1}"
  [[ "${archive_type}" == '-' || "${archive_type}" == d ]] ||
    die "backup payload must contain only regular files and directories"
done <"${tmp_dir}/archive-types.txt"

mkdir -m 700 "${tmp_dir}/payload"
run_bounded "${ARCHIVE_TIMEOUT_SECONDS}" "extract backup" \
  tar --no-same-owner --no-same-permissions \
    -C "${tmp_dir}/payload" -xzf "${tmp_dir}/backup.tgz" ||
  die "backup extraction failed"
[[ -f "${tmp_dir}/payload/SHA256SUMS" && \
   ! -L "${tmp_dir}/payload/SHA256SUMS" ]] ||
  die "backup payload SHA256SUMS is missing"
[[ -f "${tmp_dir}/payload/postgres.dump" && \
   ! -L "${tmp_dir}/payload/postgres.dump" ]] ||
  die "backup payload postgres.dump is missing"

postgres_checksum_present=0
while IFS= read -r checksum_line; do
  [[ "${checksum_line}" =~ ^([0-9a-f]{64})([[:space:]][[:space:]]|[[:space:]]\*)(.+)$ ]] ||
    die "backup payload SHA256SUMS is malformed"
  checksum_path="${BASH_REMATCH[3]}"
  normalized_checksum_path="${checksum_path#./}"
  [[ -n "${normalized_checksum_path}" && \
     "${normalized_checksum_path}" != /* && \
     "${normalized_checksum_path}" != *\\* ]] ||
    die "backup payload checksum contains an unsafe path"
  IFS='/' read -r -a checksum_parts <<<"${normalized_checksum_path}"
  for checksum_part in "${checksum_parts[@]}"; do
    [[ "${checksum_part}" != '..' ]] ||
      die "backup payload checksum escapes the restore directory"
  done
  [[ -f "${tmp_dir}/payload/${normalized_checksum_path}" && \
     ! -L "${tmp_dir}/payload/${normalized_checksum_path}" ]] ||
    die "backup payload checksum references a missing regular file"
  if [[ "${normalized_checksum_path}" == postgres.dump ]]; then
    postgres_checksum_present=1
  fi
done <"${tmp_dir}/payload/SHA256SUMS"
[[ "${postgres_checksum_present}" == 1 ]] ||
  die "backup payload does not checksum postgres.dump"
run_bounded "${ARCHIVE_TIMEOUT_SECONDS}" "verify internal backup checksum" \
  bash -c \
    "cd -- \"\${1}\" && exec sha256sum -c --strict --quiet SHA256SUMS" \
    verify-internal-backup-checksum "${tmp_dir}/payload" >/dev/null ||
  die "backup payload internal checksum mismatch"

network_created=1
run_bounded "${DOCKER_TIMEOUT_SECONDS}" "create isolated network" \
  docker network create --internal \
    --label com.magicmusiccrm.purpose=release-backup-compatibility \
    "${network_name}" >/dev/null || die "isolated network creation failed"
volume_created=1
run_bounded "${DOCKER_TIMEOUT_SECONDS}" "create isolated volume" \
  docker volume create \
    --label com.magicmusiccrm.purpose=release-backup-compatibility \
    "${volume_name}" >/dev/null || die "isolated volume creation failed"

database_owner="drill_owner_${run_id}"
database_name="drill_db_${run_id}"
capture_bounded database_password "${CRYPTO_TIMEOUT_SECONDS}" \
  "generate database password" openssl rand -hex 32 ||
  die "failed to generate isolated database password"
run_bounded "${DOCKER_TIMEOUT_SECONDS}" "start isolated PostgreSQL" \
  docker run -d --pull never \
    --name "${postgres_container}" \
    --network "${network_name}" \
    --network-alias database \
    --restart no \
    --mount "type=volume,source=${volume_name},target=/var/lib/postgresql/data" \
    --tmpfs /tmp:rw,nosuid,nodev \
    --tmpfs /var/run/postgresql:rw,nosuid,nodev,mode=1777 \
    --label com.magicmusiccrm.purpose=release-backup-compatibility \
    -e "POSTGRES_USER=${database_owner}" \
    -e "POSTGRES_PASSWORD=${database_password}" \
    -e "POSTGRES_DB=${database_name}" \
    -e POSTGRES_HOST_AUTH_METHOD=scram-sha-256 \
    "${postgres_image_id}" >/dev/null ||
  die "isolated PostgreSQL start failed"

postgres_ready=0
# PostgreSQL's entrypoint first starts a socket-only initialization server.
# Wait for the final TCP listener so restore cannot race that server's restart.
for ((attempt = 1; attempt <= WAIT_SECONDS; attempt++)); do
  if run_bounded "${DOCKER_TIMEOUT_SECONDS}" "probe isolated PostgreSQL" \
    docker exec "${postgres_container}" \
      pg_isready -h 127.0.0.1 -U "${database_owner}" -d "${database_name}" \
    >/dev/null 2>&1; then
    postgres_ready=1
    break
  fi
  run_bounded "${DOCKER_TIMEOUT_SECONDS}" "wait for PostgreSQL retry" sleep 1 ||
    die "isolated PostgreSQL readiness wait failed"
done
[[ "${postgres_ready}" == 1 ]] || die "isolated PostgreSQL did not become ready"

run_bounded_from_file "${RESTORE_TIMEOUT_SECONDS}" "restore PostgreSQL backup" \
  "${tmp_dir}/payload/postgres.dump" \
  docker exec -i "${postgres_container}" \
    pg_restore -U "${database_owner}" -d "${database_name}" \
    --exit-on-error --single-transaction --no-owner --no-acl \
  >"${tmp_dir}/pg-restore.log" 2>&1 ||
  die "isolated PostgreSQL restore failed"

database_url="postgresql://${database_owner}:${database_password}@database:5432/${database_name}"

run_release_command() {
  local timeout_seconds="$1"
  local phase_label="$2"
  local container_name="$3"
  local image="$4"
  shift 4
  run_bounded "${timeout_seconds}" "${phase_label}" \
    docker run --rm --pull never \
    --name "${container_name}" \
    --network "${network_name}" \
    --read-only \
    --tmpfs /tmp:rw,nosuid,nodev \
    --security-opt no-new-privileges:true \
    --label com.magicmusiccrm.purpose=release-backup-compatibility \
    -e NODE_ENV=production \
    -e "DATABASE_URL=${database_url}" \
    -e "MIGRATION_DATABASE_URL=${database_url}" \
    "${image}" "$@"
}

get_restore_migration() {
  local output_name="$1"
  capture_bounded "${output_name}" "${DOCKER_TIMEOUT_SECONDS}" \
    "read restored migration head" docker exec "${postgres_container}" \
      psql -X -qAt -v ON_ERROR_STOP=1 \
      -U "${database_owner}" -d "${database_name}" \
      -c 'select id from app_schema_migrations order by applied_at desc, id desc limit 1'
}

if [[ -n "${migration_baseline}" ]]; then
  # The operator supplies SQL hashes reviewed against the installed release.
  # This records only the legacy baseline on the isolated restored database;
  # the candidate runner still rejects mismatching or already changed hashes.
  baseline_command='const {Pool}=require("pg"); const {MigrationRunner}=require("./dist/db/migration-runner"); const pool=new Pool({connectionString:process.env.MIGRATION_DATABASE_URL}); (async()=>{try{const ids=await new MigrationRunner(pool).baselineLegacy(JSON.parse(process.argv[1]));console.log("Reviewed legacy baseline rows: "+ids.length);}finally{await pool.end();}})().catch(()=>{console.error("Reviewed migration baseline rejected");process.exitCode=1;});'
  run_release_command \
    "${MIGRATION_TIMEOUT_SECONDS}" "reviewed legacy migration baseline" \
    "${candidate_migrate_container}" "${candidate_image_id}" \
    node -e "${baseline_command}" "$(< "${migration_baseline}")" \
    >"${tmp_dir}/candidate-baseline.log" 2>&1 ||
    die "reviewed migration baseline failed against the isolated restore"
fi

run_release_command \
  "${MIGRATION_TIMEOUT_SECONDS}" "candidate migrations" \
  "${candidate_migrate_container}" "${candidate_image_id}" \
  node dist/db/migrate.js up \
  >"${tmp_dir}/candidate-migrate.log" 2>&1 ||
  die "candidate migrations failed against the isolated restore"
get_restore_migration candidate_head || die "candidate migration head query failed"
[[ "${candidate_head}" == "${expected_migration}" ]] ||
  die "candidate migration head does not match the expected migration"

run_release_command \
  "${RECONCILE_TIMEOUT_SECONDS}" "candidate reconciliation" \
  "${candidate_reconcile_container}" "${candidate_image_id}" \
  node dist/migration/commerce/v7/commerce-data.js \
  >"${tmp_dir}/candidate-reconcile.json" 2>"${tmp_dir}/candidate-reconcile.log" ||
  die "candidate V7 reconciliation failed against the isolated restore"
grep -Fq '"issues":[]' "${tmp_dir}/candidate-reconcile.json" ||
  die "candidate V7 reconciliation reported integrity issues"

run_release_command \
  "${MIGRATION_TIMEOUT_SECONDS}" "rollback migration compatibility" \
  "${rollback_migrate_container}" "${rollback_image_id}" \
  node dist/db/migrate.js up \
  >"${tmp_dir}/rollback-migrate.log" 2>&1 ||
  die "rollback image cannot run migrations against the candidate schema"
grep -Fq 'Applied migrations: none' "${tmp_dir}/rollback-migrate.log" ||
  die "rollback image unexpectedly applied a migration"
get_restore_migration rollback_head || die "rollback migration head query failed"
[[ "${rollback_head}" == "${candidate_head}" && \
   "${rollback_head}" == "${expected_migration}" ]] ||
  die "rollback image changed the candidate migration head"

run_release_command \
  "${RECONCILE_TIMEOUT_SECONDS}" "rollback reconciliation" \
  "${rollback_reconcile_container}" "${rollback_image_id}" \
  node dist/migration/commerce/v7/commerce-data.js \
  >"${tmp_dir}/rollback-reconcile.json" 2>"${tmp_dir}/rollback-reconcile.log" ||
  die "rollback V7 reconciliation failed on the candidate schema"
grep -Fq '"issues":[]' "${tmp_dir}/rollback-reconcile.json" ||
  die "rollback V7 reconciliation reported integrity issues"

readiness_probe='const {Pool}=require("pg"); const pool=new Pool({connectionString:process.env.DATABASE_URL,max:1}); (async()=>{const client=await pool.connect(); try {await client.query("begin transaction read only"); const result=await client.query("select id from app_schema_migrations order by applied_at desc, id desc limit 1"); await client.query("rollback"); if(result.rows[0]?.id!==process.env.EXPECTED_MIGRATION) process.exitCode=3;} finally {client.release(); await pool.end();}})().catch(()=>{process.exitCode=1;});'
run_bounded "${DOCKER_TIMEOUT_SECONDS}" "rollback readiness probe" \
  docker run --rm --pull never \
    --name "${rollback_readiness_container}" \
    --network "${network_name}" \
    --read-only \
    --tmpfs /tmp:rw,nosuid,nodev \
    --security-opt no-new-privileges:true \
    --label com.magicmusiccrm.purpose=release-backup-compatibility \
    -e NODE_ENV=production \
    -e "DATABASE_URL=${database_url}" \
    -e "EXPECTED_MIGRATION=${expected_migration}" \
    "${rollback_image_id}" node -e "${readiness_probe}" \
  >"${tmp_dir}/rollback-readiness.log" 2>&1 ||
  die "rollback runtime cannot execute the readiness database probe"

get_restore_migration final_head || die "final migration head query failed"
[[ "${final_head}" == "${candidate_head}" && \
   "${final_head}" == "${expected_migration}" ]] ||
  die "compatibility probes changed the candidate migration head"

printf 'VERIFY_RELEASE_BACKUP_COMPATIBILITY|PASS|backup=%s|candidate=%s|rollback=%s|migration=%s\n' \
  "$(basename -- "${backup_archive}")" \
  "${candidate_image}" "${rollback_image}" "${expected_migration}"
