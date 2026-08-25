set -euo pipefail
cd /opt/minecraft/server
systemctl stop minecraft.service
python3 - <<'PY'
import json, os
from pathlib import Path
profiles = {entry['uuid'].lower(): entry['name'] for entry in json.loads(Path('usercache.json').read_text())}
joined = {p.stem.lower() for p in Path('world/players/data').glob('*.dat')}
known = {name.lower(): name for uuid, name in profiles.items()
         if uuid in joined and name.lower() != 'worldkeeper'}
state_path = Path('config/brigada-core/state.json')
state = json.loads(state_path.read_text())
state['knownPlayers'] = known
tmp = state_path.with_suffix('.seed.tmp')
tmp.write_text(json.dumps(state, ensure_ascii=False, indent=2) + '\n')
os.replace(tmp, state_path)
print(json.dumps(known, ensure_ascii=False, sort_keys=True))
PY
chown minecraft:minecraft config/brigada-core/state.json
chmod 0640 config/brigada-core/state.json
systemctl start minecraft.service
sleep 42
systemctl is-active minecraft.service
systemctl show minecraft.service -p NRestarts --value
python3 - <<'PY'
import json
print(json.dumps(json.loads(open('config/brigada-core/state.json').read()).get('knownPlayers',{}), ensure_ascii=False))
PY
journalctl -u minecraft.service --since '-50 seconds' --no-pager | grep -E 'Done \(|Started fake player|WorldKeeper|ERROR|Exception|AccessDenied' || true
