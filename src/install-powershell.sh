#!/usr/bin/env bash
set -eEuo pipefail

apt-get update
apt-get install -y --no-install-recommends ca-certificates curl apt-transport-https

tmp_deb="$(mktemp)"
curl -fsSL https://packages.microsoft.com/config/debian/12/packages-microsoft-prod.deb -o "$tmp_deb"
dpkg -i "$tmp_deb"
rm -f "$tmp_deb"

apt-get update
apt-get install -y --no-install-recommends powershell

command -v pwsh >/dev/null 2>&1