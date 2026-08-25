set -euo pipefail
sleep 35
echo '=== service'
systemctl is-active minecraft.service
systemctl show minecraft.service -p NRestarts
echo '=== listeners'
ss -ltn | grep -E ':25565|:8088'
echo '=== pack from public URL'
curl -fsSL 'http://143.246.197.187:8088/world-ui-26.3-snapshot-9.zip' | sha1sum
echo '=== saved active challenge'
python3 - <<'PY'
import json
p='/opt/minecraft/server/config/brigada-core/state.json'
d=json.load(open(p, encoding='utf-8'))
print(d.get('activeChallenge'))
PY
echo '=== fake player/errors'
journalctl -u minecraft.service --since '2026-08-25 01:52:40' --no-pager | grep -E 'WorldKeeper|ERROR|Exception|Caused by|left the game|pausing' || true
