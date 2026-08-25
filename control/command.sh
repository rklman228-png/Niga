set -euo pipefail
HOT=/opt/brigada-hotfix-src
SRC="$HOT/src/main/java/dev/brigada13/hotfix/RuntimeFixes.java"
MOD=/opt/minecraft/server/mods/brigada-hotfix-1.0.0.jar
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
cp -a "$SRC" "$SRC.bak-$STAMP"
cp -a "$MOD" "$MOD.bak-$STAMP"

python3 - <<'PY'
from pathlib import Path
p=Path('/opt/brigada-hotfix-src/src/main/java/dev/brigada13/hotfix/RuntimeFixes.java')
s=p.read_text()
old='definition.difficulty() == ChallengeDifficulty.HARD && baseAttack >= 16.0'
new='definition.difficulty() == ChallengeDifficulty.HARD && baseAttack >= 25.0'
if old not in s and new not in s:
    raise SystemExit('heavy hitter threshold anchor missing')
s=s.replace(old,new,1)
p.write_text(s)
print('heavy-hitter safety threshold moved 16 -> 25; raid mobs now get full Hard x2.5')
PY

cd "$HOT"
./gradlew clean build --no-daemon --stacktrace
JAR=build/libs/brigada-hotfix-0.1.0.jar
test -s "$JAR"
sha256sum "$JAR"
install -m 0644 "$JAR" "$MOD"
systemctl restart minecraft.service
sleep 2
START=$(systemctl show minecraft.service -p ActiveEnterTimestamp --value)
for i in $(seq 1 120); do
  if journalctl -u minecraft.service --since "$START" --no-pager | grep -q 'Done ('; then break; fi
  sleep 2
done
systemctl is-active minecraft.service
ss -ltnp | grep ':25565 '
sha256sum "$MOD"
journalctl -u minecraft.service --since "$START" --no-pager | grep 'Done (' | tail -n 1
! journalctl -u minecraft.service --since "$START" --no-pager | grep -Eqi 'InjectionError|InvalidMixin|MixinApplyError|Could not execute entrypoint|Exception in server tick loop|Failed to start the minecraft server'
grep -nA7 -B2 'baseAttack = attack.getBaseValue' "$SRC"
echo FULL_HARD_RAID_DAMAGE_ACTIVE
