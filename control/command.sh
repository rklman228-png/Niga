#!/usr/bin/env bash
set -Eeuo pipefail

echo "=== SERVICE ==="
systemctl is-active minecraft
systemctl is-enabled minecraft

echo "=== PORT ==="
ss -ltnp | grep ':25565'

echo "=== VERSION AND READY ==="
grep -E 'Starting minecraft server version|Done \(' /opt/minecraft/server/logs/latest.log | tail -n 5

echo "=== SETTINGS ==="
grep -E '^(online-mode|white-list|enforce-whitelist|level-name|server-port)=' /opt/minecraft/server/server.properties

echo "=== WHITELIST ==="
cat /opt/minecraft/server/whitelist.json

echo "=== WORLD ==="
du -sh /opt/minecraft/server/world
find /opt/minecraft/server/world -maxdepth 1 -type f -name level.dat -ls

echo "FINAL_SERVER_CHECK_OK"
