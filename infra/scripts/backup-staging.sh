#!/usr/bin/env bash
set -euo pipefail

STACK_DIR="${STACK_DIR:-/opt/magicmusiccrm/infra/staging}"
ENV_FILE="${ENV_FILE:-${STACK_DIR}/.env}"
BACKUP_ENV="${BACKUP_ENV:-${STACK_DIR}/.backup.env}"
BACKUP_ROOT="${BACKUP_ROOT:-/opt/magicmusiccrm/backups}"
STORAGE_DIR="${STORAGE_DIR:-/opt/magicmusiccrm/storage}"

if [ ! -f "${ENV_FILE}" ]; then
  echo "Missing env file: ${ENV_FILE}" >&2
  exit 1
fi

if [ -f "${BACKUP_ENV}" ]; then
  # shellcheck disable=SC1090
  . "${BACKUP_ENV}"
fi

: "${BACKUP_PASSPHRASE:?BACKUP_PASSPHRASE is required in ${BACKUP_ENV}}"

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_name="magicmusiccrm-staging-${timestamp}"
tmp_dir="$(mktemp -d)"
payload_dir="${tmp_dir}/payload"
out_dir="${BACKUP_ROOT}/encrypted"
out_file="${out_dir}/${backup_name}.tgz.enc"

cleanup() {
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

mkdir -p "${out_dir}"
chmod 700 "${BACKUP_ROOT}" "${out_dir}"
mkdir -p "${payload_dir}"

cd "${STACK_DIR}"

compose=(docker compose --env-file "${ENV_FILE}")
postgres_owner_user="$("${compose[@]}" exec -T postgres \
  sh -ceu 'printf %s "$POSTGRES_USER"')"
postgres_db="$("${compose[@]}" exec -T postgres \
  sh -ceu 'printf %s "$POSTGRES_DB"')"
postgres_app_user="$("${compose[@]}" exec -T postgres \
  sh -ceu 'printf %s "$POSTGRES_APP_USER"')"

"${compose[@]}" exec -T postgres \
  pg_dump -U "${postgres_owner_user}" -d "${postgres_db}" \
  --format=custom --blobs --no-owner --no-acl \
  > "${payload_dir}/postgres.dump"

"${compose[@]}" exec -T postgres \
  pg_dumpall -U "${postgres_owner_user}" --globals-only \
  > "${payload_dir}/postgres-globals.sql"

install -m 600 "${ENV_FILE}" "${payload_dir}/staging.env"

if [ -d "${STORAGE_DIR}" ]; then
  # The API bind mount is intentionally 0700 and owned by the non-host
  # runtime uid (10001). A host-side tar therefore cannot read it after a
  # clean start. Snapshot through a network-isolated read-only helper while
  # exposing only the storage source and this backup's temporary payload.
  docker run --rm \
    --network none \
    --read-only \
    --security-opt no-new-privileges:true \
    --mount "type=bind,src=${STORAGE_DIR},dst=/storage,readonly" \
    --mount "type=bind,src=${payload_dir},dst=/payload" \
    alpine:3.20 \
    sh -ceu 'tar -C /storage -czf /payload/storage.tgz .'
else
  printf 'storage directory not present: %s\n' "${STORAGE_DIR}" > "${payload_dir}/storage-not-present.txt"
fi

cat > "${payload_dir}/manifest.txt" <<EOF
backup_name=${backup_name}
created_at=${timestamp}
host=$(hostname)
stack_dir=${STACK_DIR}
storage_dir=${STORAGE_DIR}
postgres_db=${postgres_db}
postgres_owner_user=${postgres_owner_user}
postgres_app_user=${postgres_app_user}
EOF

(
  cd "${payload_dir}"
  sha256sum postgres.dump postgres-globals.sql staging.env manifest.txt > SHA256SUMS
  if [ -f storage.tgz ]; then
    sha256sum storage.tgz >> SHA256SUMS
  fi
)

tar -C "${payload_dir}" -czf "${tmp_dir}/${backup_name}.tgz" .

BACKUP_PASSPHRASE="${BACKUP_PASSPHRASE}" openssl enc \
  -aes-256-cbc -pbkdf2 -iter 600000 -salt \
  -in "${tmp_dir}/${backup_name}.tgz" \
  -out "${out_file}" \
  -pass env:BACKUP_PASSPHRASE

sha256sum "${out_file}" > "${out_file}.sha256"
chmod 600 "${out_file}" "${out_file}.sha256"

echo "${out_file}"
