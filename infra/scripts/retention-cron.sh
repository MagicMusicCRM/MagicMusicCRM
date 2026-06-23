#!/usr/bin/env bash
# Monthly legal-retention purge (152-ФЗ / бухгалтерия).
# Policy confirmed by owner 2026-06-23:
#   - audit_events : keep 3 years, then purge
#   - payments     : keep 5 years (by payment_date), then purge
#   - messages     : NOT touched (explicit owner decision)
#
# Runs as magicdeploy via cron; psql runs as the owner role inside the postgres
# container (the app role has DELETE on audit_events revoked — append-only).
# The subscriptions.payment_id FK (nullable) is cleared before deleting an
# aged-out payment so the purge isn't blocked.
set -euo pipefail

docker exec -i magicmusiccrm-v3-postgres-1 \
  psql -U magiccrm_owner -d magiccrm -v ON_ERROR_STOP=1 <<'SQL'
begin;

-- Audit logs older than 3 years.
delete from app.audit_events
  where created_at < now() - interval '3 years';

-- Payments older than 5 years (by transaction date). Drop the subscription FK
-- link first, then delete the payment rows.
update app.subscriptions s
   set payment_id = null
  from app.payments p
 where s.payment_id = p.id
   and p.payment_date < now() - interval '5 years';

delete from app.payments
  where payment_date < now() - interval '5 years';

commit;
SQL

echo "[retention $(date -u +%FT%TZ)] done"
