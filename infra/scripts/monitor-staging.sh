#!/usr/bin/env bash
set -euo pipefail

STACK_DIR="${STACK_DIR:-/opt/magicmusiccrm/infra/staging}"
MONITOR_ENV="${MONITOR_ENV:-${STACK_DIR}/.monitor.env}"
ENV_FILE="${ENV_FILE:-${STACK_DIR}/.env}"
HEALTH_URL="${HEALTH_URL:-https://api.magicmusiccrm.ru/api/health/ready}"
ALERT_LOG="${ALERT_LOG:-/opt/magicmusiccrm/monitoring/alerts.log}"
BACKEND_ERROR_LOG="${BACKEND_ERROR_LOG:-/opt/magicmusiccrm/monitoring/backend-errors.log}"
STATE_FILE="${STATE_FILE:-/opt/magicmusiccrm/monitoring/current-failure.sha256}"
RECENT_LOG_SECONDS="${RECENT_LOG_SECONDS:-75}"
DISK_PATH="${DISK_PATH:-/opt/magicmusiccrm}"
DISK_MAX_PERCENT="${DISK_MAX_PERCENT:-85}"
REQUIRED_SERVICES="${REQUIRED_SERVICES:-api,caddy,postgres,redis}"

if [ -f "${MONITOR_ENV}" ]; then
  # shellcheck disable=SC1090
  . "${MONITOR_ENV}"
fi

timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
failures=()

append_failure() {
  failures+=("$1")
}

send_alert() {
  local message="$1"
  mkdir -p "$(dirname "${ALERT_LOG}")"
  printf '%s %s\n' "${timestamp}" "${message}" >> "${ALERT_LOG}"

  if [ "${ALERT_DRY_RUN:-0}" = "1" ]; then
    printf 'DRY-RUN alert: %s\n' "${message}"
    return 0
  fi

  if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ]; then
    curl -fsS --max-time 10 \
      -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
      -d "chat_id=${TELEGRAM_CHAT_ID}" \
      --data-urlencode "text=${message}" >/dev/null
  else
    printf 'No alert sink configured; wrote alert to %s\n' "${ALERT_LOG}" >&2
  fi
}

remember_backend_errors() {
  local lines="$1"
  if [ -z "${lines}" ]; then
    return 0
  fi
  mkdir -p "$(dirname "${BACKEND_ERROR_LOG}")"
  printf '%s\n' "${lines}" >> "${BACKEND_ERROR_LOG}"
  tail -n 5000 "${BACKEND_ERROR_LOG}" > "${BACKEND_ERROR_LOG}.tmp"
  mv "${BACKEND_ERROR_LOG}.tmp" "${BACKEND_ERROR_LOG}"
}

if [ "${FORCE_MONITOR_FAIL:-0}" = "1" ]; then
  append_failure "forced monitor failure for alert drill"
fi

health_body=""
if ! health_body="$(curl -fsS --max-time 10 "${HEALTH_URL}")"; then
  append_failure "health check failed: ${HEALTH_URL}"
elif ! printf '%s' "${health_body}" | grep -Fq '"status":"ok"'; then
  append_failure "readiness is not ok: ${HEALTH_URL}"
fi

if [ ! -f "${ENV_FILE}" ]; then
  append_failure "missing env file: ${ENV_FILE}"
fi

if [ -d "${STACK_DIR}" ] && [ -f "${ENV_FILE}" ]; then
  cd "${STACK_DIR}"
  IFS=',' read -r -a services <<< "${REQUIRED_SERVICES}"
  for service in "${services[@]}"; do
    service="$(printf '%s' "${service}" | xargs)"
    if [ -z "${service}" ]; then
      continue
    fi
    if ! docker compose --env-file "${ENV_FILE}" ps --status running --services | grep -Fxq "${service}"; then
      append_failure "container not running: ${service}"
    fi
  done

  api_errors="$(
    docker compose --env-file "${ENV_FILE}" logs --since "${RECENT_LOG_SECONDS}s" api 2>&1 \
      | grep -E 'Unhandled exception|tick failed|Analytics refresh failed|outbox attempts failed|Required email delivery failed|Report export .*(failed|could not be claimed)' \
      || true
  )"
  api_error_count="$(printf '%s\n' "${api_errors}" | sed '/^$/d' | wc -l | tr -d ' ')"
  if [ "${api_error_count}" -gt 0 ]; then
    append_failure "backend errors in last ${RECENT_LOG_SECONDS}s: ${api_error_count}"
    remember_backend_errors "${api_errors}"
  fi

  caddy_5xx_count="$(
    docker compose --env-file "${ENV_FILE}" logs --since "${RECENT_LOG_SECONDS}s" caddy 2>&1 \
      | grep -Ec '"status":5[0-9][0-9]' \
      || true
  )"
  if [ "${caddy_5xx_count}" -gt 0 ]; then
    append_failure "HTTP 5xx responses in last ${RECENT_LOG_SECONDS}s: ${caddy_5xx_count}"
  fi

  db_metrics=""
  if ! db_metrics="$(
    docker compose --env-file "${ENV_FILE}" exec -T postgres sh -lc \
      'psql -X -qAt -U "$POSTGRES_USER" -d "$POSTGRES_DB"' <<'SQL'
select concat_ws('|',
  count(*) filter (
    where status = 'failed' and attempt_count >= 5
      and updated_at > now() - interval '10 minutes'
  ),
  (select count(*) from app.report_export_jobs
    where status in ('queued', 'processing')
      and created_at < now() - interval '15 minutes'),
  (select count(*) from app.analytics_refresh_runs
    where status = 'failed'
      and claimed_at > now() - interval '24 hours'),
  (select count(*) from app.shared_task_reminders where status = 'poison'),
  (select count(*) from app.installment_payment_reminders where status = 'poison')
)
from app.email_outbox;
SQL
  )"; then
    append_failure "database operational metrics query failed"
  elif [ -n "${db_metrics}" ]; then
    IFS='|' read -r failed_email stale_export failed_analytics poison_tasks poison_installments <<< "${db_metrics}"
    [ "${failed_email:-0}" -gt 0 ] && append_failure "new exhausted email deliveries in 10m: ${failed_email}"
    [ "${stale_export:-0}" -gt 0 ] && append_failure "stale report exports: ${stale_export}"
    [ "${failed_analytics:-0}" -gt 0 ] && append_failure "failed analytics refreshes in 24h: ${failed_analytics}"
    [ "${poison_tasks:-0}" -gt 0 ] && append_failure "poison task reminders: ${poison_tasks}"
    [ "${poison_installments:-0}" -gt 0 ] && append_failure "poison installment reminders: ${poison_installments}"
  fi
else
  append_failure "missing stack directory: ${STACK_DIR}"
fi

disk_used_percent="$(df -P "${DISK_PATH}" | awk 'NR == 2 {gsub("%", "", $5); print $5}')"
if [ -z "${disk_used_percent}" ]; then
  append_failure "disk check failed: ${DISK_PATH}"
elif [ "${disk_used_percent}" -ge "${DISK_MAX_PERCENT}" ]; then
  append_failure "disk usage ${disk_used_percent}% >= ${DISK_MAX_PERCENT}% on ${DISK_PATH}"
fi

if [ "${#failures[@]}" -gt 0 ]; then
  failure_text="$(IFS='; '; printf '%s' "${failures[*]}")"
  fingerprint="$(printf '%s' "${failure_text}" | sha256sum | awk '{print $1}')"
  previous="$(cat "${STATE_FILE}" 2>/dev/null || true)"
  if [ "${fingerprint}" != "${previous}" ]; then
    message="MagicMusicCRM production alert on $(hostname): ${failure_text}"
    send_alert "${message}"
    mkdir -p "$(dirname "${STATE_FILE}")"
    printf '%s\n' "${fingerprint}" > "${STATE_FILE}"
  fi
  exit 2
fi

if [ -s "${STATE_FILE}" ]; then
  send_alert "MagicMusicCRM production recovered on $(hostname)"
  : > "${STATE_FILE}"
fi

printf 'MagicMusicCRM production monitor OK at %s\n' "${timestamp}"
