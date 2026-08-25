set -euo pipefail
systemctl is-active minecraft
for attempt in $(seq 1 18); do
  if ss -ltn 'sport = :25565' | grep -q ':25565'; then break; fi
  sleep 5
done
ss -ltnp 'sport = :25565'
curl -fsSL http://127.0.0.1:8088/world-ui-26.3-snapshot-9.zip | sha1sum
grep -E '^(resource-pack-sha1|require-resource-pack|online-mode)=' /opt/minecraft/server/server.properties
systemctl show minecraft -p NRestarts -p ActiveState -p SubState
journalctl -u minecraft --since '10 minutes ago' --no-pager | tail -120
