#!/usr/bin/env bash
set -euo pipefail

STACK_DIR="${STACK_DIR:-/opt/magicmusiccrm/infra/staging}"
MONITOR_SCRIPT="${MONITOR_SCRIPT:-/opt/magicmusiccrm/infra/scripts/monitor-staging.sh}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root." >&2
  exit 1
fi

if [ ! -x "${MONITOR_SCRIPT}" ]; then
  echo "Missing executable monitor script: ${MONITOR_SCRIPT}" >&2
  exit 1
fi

if [ ! -f "${STACK_DIR}/.monitor.env" ]; then
  if [ -f "${STACK_DIR}/.monitor.env.example" ]; then
    install -m 600 "${STACK_DIR}/.monitor.env.example" "${STACK_DIR}/.monitor.env"
  else
    echo "Missing monitor env example: ${STACK_DIR}/.monitor.env.example" >&2
    exit 1
  fi
fi

cat >/etc/systemd/system/magicmusiccrm-monitor.service <<EOF
[Unit]
Description=MagicMusicCRM production health monitor
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
Environment=MONITOR_ENV=${STACK_DIR}/.monitor.env
ExecStart=${MONITOR_SCRIPT}
EOF

cat >/etc/systemd/system/magicmusiccrm-monitor.timer <<'EOF'
[Unit]
Description=Run MagicMusicCRM production health monitor every minute

[Timer]
OnBootSec=2min
OnUnitActiveSec=1min
AccuracySec=10s
Persistent=true
Unit=magicmusiccrm-monitor.service

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now magicmusiccrm-monitor.timer
systemctl list-timers magicmusiccrm-monitor.timer --no-pager
