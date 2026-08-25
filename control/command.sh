set -euo pipefail
SERVER=/opt/minecraft/server
STATE="$SERVER/config/brigada-core/state.json"
python3 - "$STATE" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
data["activeChallenge"] = None
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
chown minecraft:minecraft "$STATE"
systemctl start minecraft.service
sleep 16
echo '=== service'
systemctl is-active minecraft.service
echo '=== deployed'
sha256sum "$SERVER/mods/brigada-core-0.1.0.jar"
grep -E '^(require-resource-pack|resource-pack-id|resource-pack-sha1|resource-pack-prompt)=' "$SERVER/server.properties"
cat "$SERVER/ops.json"
echo '=== log'
journalctl -u minecraft.service -n 140 --no-pager
