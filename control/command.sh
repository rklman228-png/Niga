set -euo pipefail
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
SERVER=/opt/minecraft/server
mkdir -p "$SERVER/mods" "$SERVER/backups/mods-$STAMP"
cp -a "$SERVER/mods/." "$SERVER/backups/mods-$STAMP/" 2>/dev/null || true
FABRIC_API=$(find /root/.gradle/caches/modules-2/files-2.1/net.fabricmc.fabric-api/fabric-api/0.158.1+26.3 -type f -name '*.jar' | head -n1)
test -n "$FABRIC_API"
install -m 0644 "$FABRIC_API" "$SERVER/mods/fabric-api-0.158.1+26.3.jar"
install -m 0644 /opt/brigada-core-src/build/libs/brigada-core-0.1.0.jar "$SERVER/mods/brigada-core-0.1.0.jar"
systemctl restart minecraft.service
sleep 12
systemctl --no-pager --full status minecraft.service || true
printf '\n=== MODS ===\n'
ls -lh "$SERVER/mods"
printf '\n=== RECENT LOG ===\n'
journalctl -u minecraft.service --since '-3 minutes' --no-pager -o cat | tail -n 220
