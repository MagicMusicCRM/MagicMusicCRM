# MagicMusicCRM v3 Staging Rollback Runbook

**Scope**: Selectel staging for `api.phantom-net.ru`.

Use this runbook when a staging deploy or restore leaves the API unhealthy.
Production rollback must be approved separately before DNS cutover.

## 1. Confirm Incident

```bash
curl -fsS https://api.phantom-net.ru/api/health
cd /opt/magicmusiccrm/infra/staging
docker compose --env-file .env ps
docker compose --env-file .env logs --tail=200 api
```

## 2. Fast Restart

Use this when containers are present but API health fails.

```bash
cd /opt/magicmusiccrm/infra/staging
docker compose --env-file .env restart api caddy
for attempt in $(seq 1 30); do
  if curl -fsS https://api.phantom-net.ru/api/health; then
    break
  fi
  sleep 2
done
```

Success criteria:

- Public health returns HTTP 200.
- `api` container is healthy.
- Caddy is running.

## 3. Recreate Runtime Containers

Use this when restart does not recover the service but the database volume
should be preserved.

```bash
cd /opt/magicmusiccrm/infra/staging
docker compose --env-file .env up -d --build
docker compose --env-file .env ps
for attempt in $(seq 1 30); do
  if curl -fsS https://api.phantom-net.ru/api/health; then
    break
  fi
  sleep 2
done
```

## 4. Restore From Encrypted Backup

Use this only when data or schema state is broken. This is destructive for the
current staging PostgreSQL volume.

```bash
latest_backup="$(ls -1t /opt/magicmusiccrm/backups/encrypted/*.tgz.enc | head -n 1)"
CONFIRM_RESTORE=YES /opt/magicmusiccrm/infra/scripts/restore-staging.sh "${latest_backup}"
curl -fsS https://api.phantom-net.ru/api/health
```

After restore, verify auth:

```bash
curl -fsS https://api.phantom-net.ru/api/health
```

Run a signup/login smoke from the operator workstation if API health passes.

## 5. Monitoring Evidence

Healthy monitor check:

```bash
/opt/magicmusiccrm/infra/scripts/monitor-staging.sh
systemctl status magicmusiccrm-monitor.timer --no-pager
```

Alert drill without external credentials:

```bash
ALERT_DRY_RUN=1 FORCE_MONITOR_FAIL=1 /opt/magicmusiccrm/infra/scripts/monitor-staging.sh
tail -n 5 /opt/magicmusiccrm/monitoring/alerts.log
```

Success criteria:

- Healthy monitor exits `0`.
- Forced failure exits non-zero.
- Alert message is written to `alerts.log`.
- If Telegram credentials are configured, Telegram receives the alert.

## 6. Escalation

If restore does not recover health:

1. Keep current logs: `docker compose --env-file .env logs --tail=500 > /tmp/mmcrm-staging-failure.log`.
2. Do not delete backup artifacts.
3. Keep Supabase Cloud as reference/rollback source for v3 migration work.
4. Open or update the Linear infrastructure issue with commands, timestamps and failed checks.
