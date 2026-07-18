#!/usr/bin/env bash
set -euo pipefail

STACK_DIR="${STACK_DIR:-/opt/magicmusiccrm/infra/staging}"
MONITOR_ENV="${MONITOR_ENV:-${STACK_DIR}/.monitor.env}"
ENV_FILE="${ENV_FILE:-${STACK_DIR}/.env}"
HEALTH_URL="${HEALTH_URL:-https://api.magicmusiccrm.ru/api/health}"
ALERT_LOG="${ALERT_LOG:-/opt/magicmusiccrm/monitoring/alerts.log}"
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

if [ "${FORCE_MONITOR_FAIL:-0}" = "1" ]; then
  append_failure "forced monitor failure for alert drill"
fi

if ! curl -fsS --max-time 10 "${HEALTH_URL}" >/dev/null; then
  append_failure "health check failed: ${HEALTH_URL}"
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
  message="MagicMusicCRM staging alert on $(hostname): $(IFS='; '; printf '%s' "${failures[*]}")"
  send_alert "${message}"
  exit 2
fi

printf 'MagicMusicCRM staging monitor OK at %s\n' "${timestamp}"
