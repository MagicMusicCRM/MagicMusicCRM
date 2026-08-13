$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..\..")
$monitor = Get-Content -Raw (Join-Path $repoRoot "infra\scripts\monitor-staging.sh")
$installer = Get-Content -Raw (Join-Path $repoRoot "infra\scripts\install-monitoring-staging.sh")
$compose = Get-Content -Raw (Join-Path $repoRoot "infra\staging\docker-compose.yml")
$caddy = Get-Content -Raw (Join-Path $repoRoot "infra\staging\Caddyfile")
$monitorEnv = Get-Content -Raw (Join-Path $repoRoot "infra\staging\.monitor.env.example")

function Assert-Contains([string]$Value, [string]$Expected, [string]$Message) {
  if (-not $Value.Contains($Expected)) {
    throw $Message
  }
}

Assert-Contains $monitorEnv "/api/health/ready" "Monitor must use the readiness endpoint."
Assert-Contains $monitor 'logs --since "${RECENT_LOG_SECONDS}s" api' "Monitor must inspect backend errors."
Assert-Contains $monitor '"status":5[0-9][0-9]' "Monitor must detect Caddy 5xx responses."
Assert-Contains $monitor "app.email_outbox" "Monitor must inspect exhausted email deliveries."
Assert-Contains $monitor "app.report_export_jobs" "Monitor must inspect stale exports."
Assert-Contains $installer "Persistent=true" "The systemd timer must catch up after downtime."

Assert-Contains $compose 'NODE_ENV: ${NODE_ENV:-production}' "Production compose must not run as staging."
Assert-Contains $compose 'INSTALLMENT_DUE_WORKER_ENABLED: ${INSTALLMENT_DUE_WORKER_ENABLED:-true}' "Installment worker must default on."
Assert-Contains $compose 'LESSON_REMINDERS_ENABLED: ${LESSON_REMINDERS_ENABLED:-true}' "Lesson reminders must default on."
Assert-Contains $compose 'max-size: "20m"' "Container logs must be rotated."
Assert-Contains $caddy "format json" "Caddy access logging must be enabled."

Write-Output "Production observability contract: PASS"
