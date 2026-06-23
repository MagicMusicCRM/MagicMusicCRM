#!/usr/bin/env bash
# Daily retention cleanup of expired/consumed one-time tokens and dead refresh
# sessions (KVA: data minimization / 152-ФЗ). Runs as magicdeploy via cron;
# psql runs as the owner role inside the postgres container.
#
# Safe windows:
#  - reset/verification/otp tokens: drop once consumed or >7d past expiry.
#  - file download tokens: drop >1d past expiry (TTL is seconds/minutes).
#  - refresh sessions: drop revoked/expired >30d (== refresh TTL, so reuse
#    detection for still-relevant tokens is unaffected).
set -euo pipefail

docker exec -i magicmusiccrm-v3-postgres-1 \
  psql -U magiccrm_owner -d magiccrm -v ON_ERROR_STOP=1 <<'SQL'
delete from app.password_reset_tokens
  where consumed_at is not null or expires_at < now() - interval '7 days';
delete from app.email_verification_tokens
  where consumed_at is not null or expires_at < now() - interval '7 days';
delete from app.otp_challenges
  where consumed_at is not null or expires_at < now() - interval '7 days';
delete from app.file_download_tokens
  where expires_at < now() - interval '1 day';
delete from app.refresh_sessions
  where (revoked_at is not null and revoked_at < now() - interval '30 days')
     or expires_at < now() - interval '30 days';
SQL

echo "[token-cleanup $(date -u +%FT%TZ)] done"
