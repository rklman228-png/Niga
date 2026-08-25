set -euo pipefail
sleep 20
systemctl is-active minecraft.service
systemctl show minecraft.service -p NRestarts --value
journalctl -u minecraft.service --since '-90 seconds' --no-pager | grep -E 'Done \(|World Core initialized|Started fake player|WorldKeeper|ERROR|Exception|AccessDenied|Can.t keep up' || true
python3 - <<'PY'
import json
print(json.dumps(json.loads(open('/opt/minecraft/server/config/brigada-core/state.json').read()).get('knownPlayers',{}), ensure_ascii=False))
PY
