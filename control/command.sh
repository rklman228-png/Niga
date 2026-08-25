set -euo pipefail
HOT=/opt/brigada-hotfix-src
SRC="$HOT/src/main/java/dev/brigada13/hotfix/RuntimeFixes.java"
SERVER=/opt/minecraft/server
MOD="$SERVER/mods/brigada-hotfix-1.0.0.jar"

python3 - <<'PY'
from pathlib import Path
p=Path('/opt/brigada-hotfix-src/src/main/java/dev/brigada13/hotfix/RuntimeFixes.java')
s=p.read_text()
old='''        PlayerBlockBreakEvents.BEFORE.register((level, player, pos, blockState, blockEntity) ->
                !isFullBoundaryPosition(level, pos));'''
new='''        PlayerBlockBreakEvents.BEFORE.register((level, player, pos, blockState, blockEntity) ->
                !(level instanceof ServerLevel serverLevel) || !isFullBoundaryPosition(serverLevel, pos));'''
if old not in s: raise SystemExit('cast anchor missing')
p.write_text(s.replace(old,new,1))
print('Level cast fixed')
PY

cd "$HOT"
./gradlew clean build --no-daemon
sha256sum build/libs/brigada-hotfix-0.1.0.jar
cp -f build/libs/brigada-hotfix-0.1.0.jar "$MOD"
systemctl restart minecraft-server.service
for i in $(seq 1 90); do
  if systemctl is-active --quiet minecraft-server.service && journalctl -u minecraft-server.service -n 100 --no-pager | grep -q 'Done ('; then break; fi
  sleep 2
done

echo '=== final verification ==='
systemctl is-active minecraft-server.service
ss -ltnp | grep ':25565 '
sha256sum "$MOD"
journalctl -u minecraft-server.service -n 180 --no-pager | grep -E 'brigada_hotfix|full-height boundary|boundary restored|boundary backup|Done \(' | tail -n 80 || true
if [ -f "$SERVER/brigada-boundary-backup.bin" ]; then stat -c 'boundary_backup_bytes=%s' "$SERVER/brigada-boundary-backup.bin"; else echo 'boundary_backup=none'; fi

echo FULL_HEIGHT_ENDER_EFFECTS_OK
