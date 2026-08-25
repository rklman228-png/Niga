set -euo pipefail
sleep 12
echo "---- startup markers"
journalctl -u minecraft.service --since '2026-08-25 03:03:45' --no-pager | grep -E 'Done \(|World Core initialized|Started fake player|WorldKeeper|ERROR|Exception|Mixin' | tail -80 || true
echo "---- recent errors"
journalctl -u minecraft.service --since '-20 seconds' --no-pager | grep -E 'ERROR|Exception|AccessDenied|Can.t keep up' || true
echo "---- state temp"
ls -la /opt/minecraft/server/config/brigada-core
echo "---- status"
systemctl is-active minecraft.service
systemctl show minecraft.service -p NRestarts --value
sha256sum /opt/minecraft/server/mods/brigada-core-0.1.0.jar
sha1sum /opt/minecraft/resourcepack/world-ui-26.3-snapshot-9.zip
