#!/usr/bin/env bash
# Scheduled encrypted Postgres backup (KVA-224). Runs as the `magicdeploy` user
# via cron — no root required.
#
# Why a new script: backup-staging.sh sourced the full `.env`, which chokes on
# the multi-line FIREBASE_PRIVATE_KEY. This one sources ONLY `.backup.env`
# (BACKUP_PASSPHRASE / BACKUP_ROOT) so it is robust.
#
# Output: AES-256 (pbkdf2) encrypted gzip dump in $BACKUP_ROOT/encrypted, with
# retention pruning. NOTE: an OFF-SITE copy is still required for true 3-2-1 —
# see the TODO at the bottom (needs an off-host target + credentials).
#
# Restore:
#   openssl enc -d -aes-256-cbc -pbkdf2 -pass "pass:$BACKUP_PASSPHRASE" \
#     -in auto-XXXX.sql.gz.enc | gunzip \
#   | docker exec -i magicmusiccrm-v3-postgres-1 psql -U magiccrm_owner -d magiccrm
set -euo pipefail

STACK_DIR="/opt/magicmusiccrm/infra/staging"
# shellcheck disable=SC1091
set -a; . "${STACK_DIR}/.backup.env"; set +a

DEST="${BACKUP_ROOT}/encrypted"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-14}"
mkdir -p "${DEST}"
chmod 0700 "${DEST}"

TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="${DEST}/auto-${TS}.sql.gz.enc"

docker exec magicmusiccrm-v3-postgres-1 pg_dump -U magiccrm_owner -d magiccrm \
    --no-owner --clean --if-exists \
  | gzip \
  | openssl enc -aes-256-cbc -salt -pbkdf2 -pass "pass:${BACKUP_PASSPHRASE}" \
  > "${OUT}.partial"
mv "${OUT}.partial" "${OUT}"
chmod 0600 "${OUT}"

# Retention: prune encrypted auto-backups older than RETENTION_DAYS.
find "${DEST}" -name 'auto-*.sql.gz.enc' -mtime "+${RETENTION_DAYS}" -delete

echo "[backup-cron $(date -u +%FT%TZ)] wrote ${OUT} ($(du -h "${OUT}" | cut -f1))"

# TODO(3-2-1 off-site): replicate ${OUT} to an off-host target once configured,
# e.g. `rclone copy "${OUT}" remote:mmcrm-backups/` or `aws s3 cp`. Without this,
# a host loss still loses the backups (KVA-224 residual).
