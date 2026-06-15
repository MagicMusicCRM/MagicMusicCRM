#!/usr/bin/env bash
set -euo pipefail

STACK_DIR="${STACK_DIR:-/opt/magicmusiccrm/infra/staging}"
ENV_FILE="${ENV_FILE:-${STACK_DIR}/.env}"
BACKUP_ENV="${BACKUP_ENV:-${STACK_DIR}/.backup.env}"
RESTORE_ARCHIVE="${1:-${RESTORE_ARCHIVE:-}}"

if [ "${CONFIRM_RESTORE:-}" != "YES" ]; then
  echo "Refusing restore without CONFIRM_RESTORE=YES." >&2
  exit 1
fi

if [ -z "${RESTORE_ARCHIVE}" ] || [ ! -f "${RESTORE_ARCHIVE}" ]; then
  echo "Usage: CONFIRM_RESTORE=YES $0 /path/to/backup.tgz.enc" >&2
  exit 1
fi

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

tmp_dir="$(mktemp -d)"

cleanup() {
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

BACKUP_PASSPHRASE="${BACKUP_PASSPHRASE}" openssl enc \
  -d -aes-256-cbc -pbkdf2 -iter 600000 \
  -in "${RESTORE_ARCHIVE}" \
  -out "${tmp_dir}/backup.tgz" \
  -pass env:BACKUP_PASSPHRASE

mkdir -p "${tmp_dir}/payload"
tar -C "${tmp_dir}/payload" -xzf "${tmp_dir}/backup.tgz"

(
  cd "${tmp_dir}/payload"
  sha256sum -c SHA256SUMS
)

cd "${STACK_DIR}"

docker compose --env-file "${ENV_FILE}" down
docker volume rm magicmusiccrm-v3_postgres_data >/dev/null 2>&1 || true
docker compose --env-file "${ENV_FILE}" up -d postgres redis

for _ in $(seq 1 60); do
  if docker compose --env-file "${ENV_FILE}" exec -T postgres \
    psql -U "${POSTGRES_OWNER_USER}" -d "${POSTGRES_DB}" -tAc 'select 1' >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

restore_ok=0
for attempt in $(seq 1 5); do
  if docker compose --env-file "${ENV_FILE}" exec -T postgres \
    pg_restore -U "${POSTGRES_OWNER_USER}" -d "${POSTGRES_DB}" \
    --clean --if-exists --no-owner --no-acl \
    < "${tmp_dir}/payload/postgres.dump"; then
    restore_ok=1
    break
  fi
  echo "pg_restore failed on attempt ${attempt}; retrying..." >&2
  sleep 3
done

if [ "${restore_ok}" != "1" ]; then
  echo "pg_restore failed after retries." >&2
  exit 1
fi

docker compose --env-file "${ENV_FILE}" exec -T postgres \
  psql -U "${POSTGRES_OWNER_USER}" -d "${POSTGRES_DB}" <<SQL
do \$\$
begin
  if exists (select 1 from pg_roles where rolname = '${POSTGRES_APP_USER}') then
    execute format('grant usage on schema app to %I', '${POSTGRES_APP_USER}');
    execute format('grant usage on all sequences in schema app to %I', '${POSTGRES_APP_USER}');
    execute format('grant select, insert, update, delete on all tables in schema app to %I', '${POSTGRES_APP_USER}');
    execute format('alter default privileges in schema app grant usage on sequences to %I', '${POSTGRES_APP_USER}');
    execute format('alter default privileges in schema app grant select, insert, update, delete on tables to %I', '${POSTGRES_APP_USER}');
  end if;
end
\$\$;
SQL

docker compose --env-file "${ENV_FILE}" up -d

for _ in $(seq 1 60); do
  if docker compose --env-file "${ENV_FILE}" exec -T api \
    wget -qO- http://127.0.0.1:3000/api/health >/dev/null 2>&1; then
    echo "Restore completed and API health passed."
    exit 0
  fi
  sleep 1
done

echo "Restore completed, but API health did not pass in time." >&2
docker compose --env-file "${ENV_FILE}" ps >&2
exit 1
