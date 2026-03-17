#!/usr/bin/env bash
set -eEuo pipefail

cd /usr/local/
if [ -d "fieldsets" ]; then
    cd fieldsets
    git pull origin main
    cd ..
else
    git clone --recurse-submodules https://github.com/fieldsets/fieldsets.git
fi

chown -R ${DEFAULT_ADMIN_USER}:${DEFAULT_ADMIN_USER} /usr/local/fieldsets
cd /usr/local/fieldsets
cp ./env.example ./.env

git pull origin main
git submodule foreach --recursive git pull origin main
