#!/usr/bin/env bash
set -eEuo pipefail

: "${DEBIAN_CODENAME:=bookworm}"

arch="$(dpkg --print-architecture)"

apt-get update
apt-get install -y --no-install-recommends ca-certificates curl gnupg

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

cat >/etc/apt/sources.list.d/docker.list <<EOF
deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian ${DEBIAN_CODENAME} stable
EOF

apt-get update
apt-get install -y --no-install-recommends \
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable docker
systemctl enable containerd || true
systemctl restart containerd || true
systemctl restart docker

# Convenience: allow admin user to run docker without sudo (if user exists).
if [ -n "${DEFAULT_ADMIN_USER:-}" ] && id -u "${DEFAULT_ADMIN_USER}" >/dev/null 2>&1; then
  groupadd -f docker
  usermod -aG docker "${DEFAULT_ADMIN_USER}" || true
fi