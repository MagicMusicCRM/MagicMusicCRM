#!/usr/bin/env bash
set -euo pipefail

DEPLOY_USER="${DEPLOY_USER:-magicdeploy}"
PUBLIC_SSH_KEY="${PUBLIC_SSH_KEY:-}"
ALLOW_PASSWORD_SSH="${ALLOW_PASSWORD_SSH:-0}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y ca-certificates curl git ufw fail2ban openssl

if [ -z "${PUBLIC_SSH_KEY}" ] && [ "${ALLOW_PASSWORD_SSH}" != "1" ]; then
  echo "PUBLIC_SSH_KEY is required. Set ALLOW_PASSWORD_SSH=1 only for temporary break-glass bootstrap." >&2
  exit 1
fi

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

. /etc/os-release
cat >/etc/apt/sources.list.d/docker.list <<EOF
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable
EOF

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

if ! id "${DEPLOY_USER}" >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" "${DEPLOY_USER}"
fi
usermod -aG docker "${DEPLOY_USER}"

if [ -n "${PUBLIC_SSH_KEY}" ]; then
  install -d -m 700 "/home/${DEPLOY_USER}/.ssh"
  printf '%s\n' "${PUBLIC_SSH_KEY}" >"/home/${DEPLOY_USER}/.ssh/authorized_keys"
  chmod 600 "/home/${DEPLOY_USER}/.ssh/authorized_keys"
  chown -R "${DEPLOY_USER}:${DEPLOY_USER}" "/home/${DEPLOY_USER}/.ssh"
fi

cat >/etc/ssh/sshd_config.d/99-magiccrm-hardening.conf <<EOF
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
UseDNS no
MaxAuthTries 3
LoginGraceTime 30
AllowUsers ${DEPLOY_USER}
EOF
sshd -t
systemctl restart ssh.service

ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

systemctl enable --now docker
systemctl enable --now fail2ban

mkdir -p /opt/magicmusiccrm
chown "${DEPLOY_USER}:${DEPLOY_USER}" /opt/magicmusiccrm

docker --version
docker compose version
ufw status verbose
