set -euo pipefail
sleep 30
systemctl is-active minecraft.service
systemctl show minecraft.service -p NRestarts --value
curl -fsS http://127.0.0.1:8088/world-ui-26.3-snapshot-9.zip | sha1sum
sha1sum /opt/minecraft/resourcepack/world-ui-26.3-snapshot-9.zip
journalctl -u minecraft.service --since '2026-08-25 04:42:20' --no-pager | grep -E 'Done \(|WorldKeeper|Started fake player|ERROR|Exception|Unknown|Missing|Couldn.t load|failed|Can.t keep up' || true
