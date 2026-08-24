#!/usr/bin/env bash
set -Eeuo pipefail
sleep 75

echo "=== FABRIC FINAL ==="
systemctl is-active minecraft
systemctl is-enabled minecraft
ss -ltnp | grep ':25565'
tail -n 120 /opt/minecraft/server/logs/latest.log

echo "=== IDENTITY ==="
grep -E 'Loading Minecraft .*Fabric Loader|Starting minecraft server version|Done \(' /opt/minecraft/server/logs/latest.log
echo "mods_count=$(find /opt/minecraft/server/mods -maxdepth 1 -type f -name '*.jar' | wc -l)"
grep -E '^(online-mode|white-list|enforce-whitelist|server-port)=' /opt/minecraft/server/server.properties
cat /opt/minecraft/server/whitelist.json
echo "FABRIC_FINAL_CHECK_OK"
