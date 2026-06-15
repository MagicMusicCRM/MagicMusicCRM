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

set -a
# shellcheck disable=SC1090
. "${ENV_FILE}"
set +a

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

docker compose --env-file "${ENV_FILE}" exec -T postgres \
  pg_dump -U "${POSTGRES_OWNER_USER}" -d "${POSTGRES_DB}" \
  --format=custom --blobs --no-owner --no-acl \
  > "${payload_dir}/postgres.dump"

docker compose --env-file "${ENV_FILE}" exec -T postgres \
  pg_dumpall -U "${POSTGRES_OWNER_USER}" --globals-only \
  > "${payload_dir}/postgres-globals.sql"

install -m 600 "${ENV_FILE}" "${payload_dir}/staging.env"

if [ -d "${STORAGE_DIR}" ]; then
  tar -C "${STORAGE_DIR}" -czf "${payload_dir}/storage.tgz" .
else
  printf 'storage directory not present: %s\n' "${STORAGE_DIR}" > "${payload_dir}/storage-not-present.txt"
fi

cat > "${payload_dir}/manifest.txt" <<EOF
backup_name=${backup_name}
created_at=${timestamp}
host=$(hostname)
stack_dir=${STACK_DIR}
storage_dir=${STORAGE_DIR}
postgres_db=${POSTGRES_DB}
postgres_owner_user=${POSTGRES_OWNER_USER}
postgres_app_user=${POSTGRES_APP_USER}
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
