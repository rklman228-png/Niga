set -euo pipefail
BEFORE=$(stat -c %Y /opt/minecraft/server/config/brigada-core/state.json)
systemctl restart minecraft.service
sleep 35
AFTER=$(stat -c %Y /opt/minecraft/server/config/brigada-core/state.json)
echo "STATE_MTIME_BEFORE=$BEFORE"
echo "STATE_MTIME_AFTER=$AFTER"
test "$AFTER" -ge "$BEFORE"
test ! -e /opt/minecraft/server/config/brigada-core/state.json.tmp
systemctl is-active minecraft.service
systemctl show minecraft.service -p NRestarts --value
journalctl -u minecraft.service --since '-45 seconds' --no-pager | grep -E 'Done \(|World Core initialized|Started fake player|WorldKeeper|ERROR|Exception|AccessDenied|Can.t keep up' || true
