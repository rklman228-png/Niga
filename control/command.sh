set -euo pipefail
HOT=/opt/brigada-hotfix-src
RUNTIME="$HOT/src/main/java/dev/brigada13/hotfix/RuntimeFixes.java"

python3 - <<'PY'
from pathlib import Path
p = Path('/opt/brigada-hotfix-src/src/main/java/dev/brigada13/hotfix/RuntimeFixes.java')
s = p.read_text()
s = s.replace('source.is(DamageTypes.ON_FIRE) && entity.level() instanceof ServerLevel level\n                && isDay(level) && level.canSeeSky(entity.blockPosition())',
              'source.is(DamageTypes.ON_FIRE) && entity.level() instanceof ServerLevel level\n                && level.canSeeSky(entity.blockPosition())')
s = s.replace('if (isDay(level) && level.canSeeSky(mob.blockPosition()) && mob.isOnFire()) {',
              'if (level.canSeeSky(mob.blockPosition()) && mob.isOnFire()) {')
start = s.find('    private static boolean isDay(ServerLevel level) {')
if start != -1:
    end = s.find('    private static void fixDefense(', start)
    s = s[:start] + s[end:]
p.write_text(s)
PY

cd "$HOT"
echo '=== compile hotfix v2 final ==='
./gradlew clean build --no-daemon --stacktrace
JAR=$(find build/libs -maxdepth 1 -type f -name 'brigada-hotfix-*.jar' ! -name '*sources*' ! -name '*dev*' -print -quit)
test -n "$JAR" -a -s "$JAR"
sha256sum "$JAR"
jar tf "$JAR" | grep -E 'RuntimeFixes|ChallengeServiceMixin|brigada_hotfix.mixins.json'
echo BUILD_V2_OK
