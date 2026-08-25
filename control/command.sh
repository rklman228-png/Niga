set -euo pipefail
sleep 20
systemctl is-active minecraft.service
systemctl show minecraft.service -p NRestarts --value
journalctl -u minecraft.service --since '2026-08-25 03:07:40' --no-pager | grep -E 'Done \(|World Core initialized|Started fake player|WorldKeeper|ERROR|Exception|AccessDenied|Can.t keep up' || true
test ! -e /opt/minecraft/server/config/brigada-core/state.json.tmp
sha256sum /opt/minecraft/server/mods/brigada-core-0.1.0.jar
sha1sum /opt/minecraft/resourcepack/world-ui-26.3-snapshot-9.zip
