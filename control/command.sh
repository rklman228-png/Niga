set -euo pipefail
HOT=/opt/brigada-hotfix-src
SRC="$HOT/src/main/java/dev/brigada13/hotfix/RuntimeFixes.java"
SERVER=/opt/minecraft/server
MOD="$SERVER/mods/brigada-hotfix-1.0.0.jar"

python3 - <<'PY'
from pathlib import Path
p=Path('/opt/brigada-hotfix-src/src/main/java/dev/brigada13/hotfix/RuntimeFixes.java')
s=p.read_text()
imp='import dev.brigada13.core.challenge.ChallengeDifficulty;\n'
if imp not in s:
    anchor='import dev.brigada13.core.challenge.ChallengeDefinition;\n'
    if anchor not in s: raise SystemExit('ChallengeDefinition import anchor missing')
    s=s.replace(anchor, anchor+imp, 1)
p.write_text(s)
print('ChallengeDifficulty import fixed')
PY

cd "$HOT"
echo '=== rebuild on VPS ==='
./gradlew clean build --no-daemon --stacktrace
JAR=build/libs/brigada-hotfix-0.1.0.jar
test -s "$JAR"
sha256sum "$JAR"
install -m 0644 "$JAR" "$MOD"

echo '=== restart ==='
systemctl restart minecraft.service
for i in $(seq 1 120); do
  if ss -ltn | grep -q ':25565 '; then break; fi
  sleep 2
done
systemctl is-active minecraft.service
ss -ltnp | grep ':25565 '
sha256sum "$MOD"
START=$(systemctl show minecraft.service -p ActiveEnterTimestamp --value)
journalctl -u minecraft.service --since "$START" --no-pager | tail -n 180
if journalctl -u minecraft.service --since "$START" --no-pager | grep -Eqi 'InjectionError|InvalidMixin|MixinApplyError|Could not execute entrypoint|Exception in server tick loop|Failed to start the minecraft server'; then
  echo FATAL_RUNTIME_ERROR
  exit 42
fi

echo BALANCE_REWORK_ACTIVE
