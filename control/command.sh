#!/usr/bin/env bash
set -Eeuo pipefail
sleep 45

echo "=== FABRIC SERVICE ==="
systemctl --no-pager --full status minecraft || true

echo "=== PORT ==="
ss -ltnp | grep ':25565' || true

echo "=== LATEST LOG ==="
tail -n 160 /opt/minecraft/server/logs/latest.log 2>/dev/null || true

echo "=== JOURNAL ==="
journalctl -u minecraft -n 100 --no-pager

echo "=== FILES ==="
ls -lh /opt/minecraft/server/fabric-server-launch.jar /opt/minecraft/server/server.jar
echo "mods_count=$(find /opt/minecraft/server/mods -maxdepth 1 -type f -name '*.jar' | wc -l)"
cat /opt/minecraft/server/server-core.txt

if systemctl is-active --quiet minecraft && ss -ltn | grep -q ':25565'; then
  echo "FABRIC_FINAL_CHECK_OK"
else
  echo "FABRIC_FINAL_CHECK_FAILED"
  exit 1
fi
