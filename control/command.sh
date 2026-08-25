set -euo pipefail
cd /opt/minecraft/server
echo "---- level"
grep '^level-name=' server.properties
echo "---- cache"
python3 - <<'PY'
import json
from pathlib import Path
p=Path('usercache.json')
print(json.dumps(json.loads(p.read_text()), ensure_ascii=False, indent=2) if p.exists() else '[]')
PY
echo "---- playerdata"
LEVEL=$(sed -n 's/^level-name=//p' server.properties)
find "$LEVEL/playerdata" -maxdepth 1 -type f -name '*.dat' -printf '%f
' | sort || true
echo "---- known state"
python3 - <<'PY'
import json
from pathlib import Path
p=Path('config/brigada-core/state.json')
d=json.loads(p.read_text())
print(json.dumps(d.get('knownPlayers', {}), ensure_ascii=False, indent=2))
PY
