set -euo pipefail
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
SRC=/opt/brigada-core-src/build/libs/brigada-core-0.1.0.jar
DST=/opt/minecraft/server/mods/brigada-core-0.1.0.jar
BACKUP=/opt/minecraft/server/backups/brigada-core-0.1.0-$STAMP.jar
install -d -m 0755 /opt/minecraft/server/backups
cp -a "$DST" "$BACKUP"
install -m 0644 "$SRC" "$DST"
systemctl restart minecraft.service
sleep 25
printf 'SERVICE\n'
systemctl is-active minecraft.service
printf '\nARTIFACT\n'
sha256sum "$DST"
printf '\nPORT\n'
ss -ltnp | grep ':25565'
printf '\nLOG\n'
journalctl -u minecraft.service -n 120 --no-pager | grep -E 'Brigada|Done|ERROR|Exception|120' | tail -n 40
printf '\nBACKUP\n%s\n' "$BACKUP"
