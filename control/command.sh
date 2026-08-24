set -euo pipefail
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
cp -a /opt/minecraft/server/mods/brigada-core-0.1.0.jar "/opt/minecraft/server/backups/brigada-core-0.1.0-$STAMP.jar"
install -m 0644 /opt/brigada-core-src/build/libs/brigada-core-0.1.0.jar /opt/minecraft/server/mods/brigada-core-0.1.0.jar
systemctl restart minecraft.service
sleep 70
systemctl --no-pager --full status minecraft.service || true
printf '\n=== FINAL CHECK ===\n'
journalctl -u minecraft.service --since '-3 minutes' --no-pager -o cat | grep -E 'Brigada|Loaded [0-9]+ .*challenges|Done|ERROR|WARN|Failed|Exception|structure|tag|dialog' | tail -n 260 || true
printf '\n=== PORT ===\n'
ss -ltnp | grep ':25565' || true
