set -euo pipefail
find /opt /var/www -type f -name 'world-ui-26.3-snapshot-9.zip' -printf '%p %s bytes
' 2>/dev/null || true
grep -E '^(resource-pack|resource-pack-sha1|resource-pack-id|require-resource-pack)=' /opt/minecraft/server/server.properties
systemctl is-active minecraft.service
systemctl cat worldui-pack.service 2>/dev/null || true
systemctl cat nginx.service 2>/dev/null | head -80 || true
ss -ltnp | grep ':8088' || true
