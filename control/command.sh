set -euo pipefail
echo PROPERTIES
grep -E '^(resource-pack|resource-pack-id|resource-pack-sha1|require-resource-pack)' /opt/minecraft/server/server.properties || true
echo PACKS
find /opt/minecraft /var/www /srv -maxdepth 5 -type f -name '*world-ui*.zip' -o -name '*resource*pack*.zip' 2>/dev/null | sort
echo HTTP
systemctl list-units --type=service --all | grep -Ei 'http|pack|python' || true
ss -ltnp | grep ':8088' || true
