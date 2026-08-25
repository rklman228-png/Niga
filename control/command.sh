set -euo pipefail
systemctl is-active minecraft.service
curl -fsS http://127.0.0.1:8088/world-ui-26.3-snapshot-9.zip | sha1sum
sha1sum /opt/minecraft/resourcepack/world-ui-26.3-snapshot-9.zip
ss -ltn | grep -E ':25565|:8088'
journalctl -u minecraft.service --since '2026-08-25 05:21:20' --no-pager | grep -E 'ERROR|Exception|Couldn.t load|failed|Done \(|Started fake player' || true
