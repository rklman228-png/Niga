set -euo pipefail
sleep 35
systemctl is-active minecraft.service
systemctl show minecraft.service -p NRestarts --value
curl -fsS http://127.0.0.1:8088/world-ui-26.3-snapshot-9.zip | sha1sum
sha1sum /opt/minecraft/resourcepack/world-ui-26.3-snapshot-9.zip
sha256sum /opt/minecraft/server/mods/brigada-core-0.1.0.jar
grep -E '^(resource-pack|resource-pack-sha1|require-resource-pack)=' /opt/minecraft/server/server.properties
python3 - <<'PY'
import json
ops=json.load(open('/opt/minecraft/server/ops.json'))
print('OPS=' + ','.join(sorted(x['name'] for x in ops)))
PY
journalctl -u minecraft.service --since '2026-08-25 04:16:35' --no-pager | grep -E 'ERROR|Exception|Mixin apply|failed|Can.t keep up|Done \(|WorldKeeper' || true
