#!/usr/bin/env bash
set -eEuo pipefail

cd /usr/local/
git clone --recurse-submodules https://github.com/fieldsets/fieldsets.git
chown -R "${DEFAULT_ADMIN_USER}:${DEFAULT_ADMIN_USER}" /usr/local/fieldsets
cd /usr/local/fieldsets
cp ./env.example ./.env
