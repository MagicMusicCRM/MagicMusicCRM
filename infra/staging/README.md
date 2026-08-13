# MagicMusicCRM v3 Staging Deploy

This staging stack is for rehearsing the v3 backend on a clean Ubuntu 24.04 VPS.
It is intentionally small: Caddy, API, PostgreSQL and Redis. Heavy monitoring and
external backups are added after the real Moscow server is available.

## DNS

Create an `A` record:

```text
api.magicmusiccrm.ru -> <server IPv4>
```

Wait until both commands resolve to the new server:

```bash
dig +short api.magicmusiccrm.ru
curl -4 ifconfig.me
```

## Server Bootstrap

Run on a freshly reinstalled Ubuntu 24.04 server as `root`.

```bash
export DEPLOY_USER=magicdeploy
export PUBLIC_SSH_KEY='ssh-ed25519 ...'
bash infra/scripts/bootstrap-ubuntu-24.04.sh
```

`PUBLIC_SSH_KEY` is required by default. The script writes the key for
`DEPLOY_USER`, then disables root SSH and password SSH through
`/etc/ssh/sshd_config.d/99-magiccrm-hardening.conf`.

Use `ALLOW_PASSWORD_SSH=1` only for temporary break-glass bootstrap on a
disposable staging host, and disable password SSH before exposing production.

## Deploy

Copy the repository to `/opt/magicmusiccrm`, then:

```bash
cd /opt/magicmusiccrm/infra/staging
cp .env.example .env
openssl rand -base64 32
openssl rand -base64 48
```

Put generated values into `.env`, then start:

```bash
docker compose up -d --build
docker compose ps
docker compose logs -f api
```

## Smoke

```bash
curl -fsS https://api.magicmusiccrm.ru/api/health
curl -fsS http://127.0.0.1:3000/api/health
```

Expected public response:

```json
{"status":"ok"}
```

## Migration Check

```bash
docker compose exec api node dist/db/migrate.js up
docker compose exec api node dist/db/migrate.js down
docker compose exec api node dist/db/migrate.js up
```

Do not run rollback against production data without a fresh backup and explicit
approval.

## Encrypted Backup

Create a server-local encrypted backup:

```bash
cd /opt/magicmusiccrm/infra/staging
cp .backup.env.example .backup.env
openssl rand -hex 48
chmod 600 .backup.env
/opt/magicmusiccrm/infra/scripts/backup-staging.sh
```

The script writes encrypted artifacts to:

```text
/opt/magicmusiccrm/backups/encrypted/*.tgz.enc
```

For staging, copy the encrypted artifact off the server with `scp` to prove that
the backup survives server loss. For production, use Selectel S3 or another
external object store as the off-server destination.

## Restore Drill

Restoring is destructive for the staging database. Run it only against staging
or a clean restore target:

```bash
CONFIRM_RESTORE=YES /opt/magicmusiccrm/infra/scripts/restore-staging.sh \
  /opt/magicmusiccrm/backups/encrypted/<backup>.tgz.enc
```

Expected result:

```text
Restore completed and API health passed.
```

## Monitoring

Install a one-minute systemd health monitor:

```bash
cd /opt/magicmusiccrm/infra/staging
cp .monitor.env.example .monitor.env
chmod 600 .monitor.env
/opt/magicmusiccrm/infra/scripts/install-monitoring-staging.sh
```

The monitor checks `/api/health/ready`, required Docker Compose services, disk
usage, recent API exceptions and Caddy 5xx responses. It also checks exhausted
email deliveries, stale report exports, failed analytics refreshes and poison
task/installment reminders. Repeated identical failures are deduplicated.
Alerts and preserved backend error lines are written to:

```text
/opt/magicmusiccrm/monitoring/alerts.log
/opt/magicmusiccrm/monitoring/backend-errors.log
```

Without Telegram credentials, keep `ALERT_DRY_RUN=1`; local persistent alert
and backend-error logs still work. Run an alert drill:

```bash
ALERT_DRY_RUN=1 FORCE_MONITOR_FAIL=1 \
  /opt/magicmusiccrm/infra/scripts/monitor-staging.sh
tail -n 5 /opt/magicmusiccrm/monitoring/alerts.log
```

For production, configure `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID` in
`.monitor.env` and re-run the alert drill before DNS cutover.

## Rollback

Use the full runbook:

```text
docs/runbooks/v3-staging-rollback.md
```
