set -euo pipefail
HOT=/opt/brigada-hotfix-src
SRC="$HOT/src/main/java/dev/brigada13/hotfix/RuntimeFixes.java"
MOD=/opt/minecraft/server/mods/brigada-hotfix-1.0.0.jar

sed -i 's/import net\.minecraft\.world\.entity\.projectile\.AbstractArrow;/import net.minecraft.world.entity.projectile.arrow.AbstractArrow;/' "$SRC"

echo '=== build locally on VPS ==='
cd "$HOT"
set +e
./gradlew clean build --no-daemon --stacktrace > /tmp/brigada-build.log 2>&1
STATUS=$?
set -e
cat /tmp/brigada-build.log
if [ "$STATUS" -ne 0 ]; then
  echo BUILD_FAILED_NO_DEPLOY
  exit "$STATUS"
fi

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

echo '=== verify ==='
systemctl is-active minecraft.service
ss -ltnp | grep ':25565 '
sha256sum "$MOD"
journalctl -u minecraft.service --since "$START" --no-pager | grep 'Done (' | tail -n 1
! journalctl -u minecraft.service --since "$START" --no-pager | grep -Eqi 'InjectionError|InvalidMixin|MixinApplyError|Could not execute entrypoint|Exception in server tick loop|Failed to start the minecraft server'

echo '=== live anchors ==='
grep -nA14 -B2 'scaleEventArrow' "$SRC" | head -n 45
grep -nA18 -B2 'UseItemCallback.EVENT' "$SRC" | head -n 50
grep -nA24 -B2 'expelOutsiders' "$SRC" | head -n 70
grep -nA10 -B2 'isForbiddenChallengeUse' "$SRC" | head -n 35
echo EVENT_COMBAT_LOCKDOWN_ACTIVE
