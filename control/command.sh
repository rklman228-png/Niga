set -euo pipefail
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
cp -a /opt/minecraft/server/mods/brigada-core-0.1.0.jar "/opt/minecraft/server/backups/brigada-core-0.1.0-$STAMP.jar"
install -m 0644 /opt/brigada-core-src/build/libs/brigada-core-0.1.0.jar /opt/minecraft/server/mods/brigada-core-0.1.0.jar
systemctl restart minecraft.service
sleep 70
systemctl is-active minecraft.service
journalctl -u minecraft.service --since '-3 minutes' --no-pager -o cat | grep -E 'Brigada|Loaded [0-9]+ .*challenges|Done|ERROR|Failed|Exception' | tail -n 220 || true
ss -ltnp | grep ':25565'
sha256sum /opt/minecraft/server/mods/brigada-core-0.1.0.jar
