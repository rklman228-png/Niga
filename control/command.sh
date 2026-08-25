set -euo pipefail
sleep 20
systemctl is-active minecraft.service
systemctl show minecraft.service -p NRestarts --value
journalctl -u minecraft.service --since '2026-08-25 03:03:45' --no-pager | tail -160
echo "---- properties"
grep -E '^(enable-rcon|rcon.port|resource-pack|resource-pack-sha1|resource-pack-id|require-resource-pack)=' /opt/minecraft/server/server.properties
echo "---- listeners"
ss -ltnp | grep -E ':25565|:8088' || true
echo "---- pack"
sha1sum /opt/minecraft/resourcepack/world-ui-26.3-snapshot-9.zip
curl -fsS http://127.0.0.1:8088/world-ui-26.3-snapshot-9.zip | sha1sum
echo "---- tools"
command -v mcrcon || true
