set -euo pipefail
HOT=/opt/brigada-hotfix-src
SRC="$HOT/src/main/java/dev/brigada13/hotfix/RuntimeFixes.java"
SERVER=/opt/minecraft/server
MOD="$SERVER/mods/brigada-hotfix-1.0.0.jar"
OUT="$GITHUB_WORKSPACE/control/generated"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
cp -a "$SRC" "$SRC.bak-$STAMP"
cp -a "$MOD" "$MOD.bak-$STAMP"

python3 - <<'PY'
from pathlib import Path
p=Path('/opt/brigada-hotfix-src/src/main/java/dev/brigada13/hotfix/RuntimeFixes.java')
s=p.read_text()
old='''        double damageMultiplier = switch (definition.difficulty()) {\n            case EASY -> 1.00;\n            case NORMAL -> 1.08;\n            case HARD -> 1.16;\n        };'''
new='''        double damageMultiplier = switch (definition.difficulty()) {\n            case EASY -> 1.00;\n            case NORMAL -> 1.15;\n            case HARD -> 1.42;\n        };'''
if old not in s:
    raise SystemExit('damage multiplier anchor missing')
s=s.replace(old,new,1)
old2='''            var attack = mob.getAttribute(Attributes.ATTACK_DAMAGE);\n            if (attack != null && damageMultiplier != 1.0)\n                attack.setBaseValue(attack.getBaseValue() * damageMultiplier);'''
new2='''            var attack = mob.getAttribute(Attributes.ATTACK_DAMAGE);\n            if (attack != null && damageMultiplier != 1.0) {\n                double baseAttack = attack.getBaseValue();\n                // Hard should hurt, but naturally brutal mobs must not become accidental one-shot machines.\n                double appliedMultiplier = definition.difficulty() == ChallengeDifficulty.HARD && baseAttack >= 16.0\n                        ? 1.18 : damageMultiplier;\n                attack.setBaseValue(baseAttack * appliedMultiplier);\n            }'''
if old2 not in s:
    raise SystemExit('attack scaling anchor missing')
s=s.replace(old2,new2,1)
p.write_text(s)
print('damage balance patched: NORMAL +15%, HARD +42%, heavy-hitter cap +18%')
PY

cd "$HOT"
echo '=== build locally on VPS ==='
./gradlew clean build --no-daemon --stacktrace
JAR=build/libs/brigada-hotfix-0.1.0.jar
test -s "$JAR"
sha256sum "$JAR"
install -m 0644 "$JAR" "$MOD"

echo '=== restart ==='
systemctl restart minecraft.service
for i in $(seq 1 120); do
  if journalctl -u minecraft.service --since "$(systemctl show minecraft.service -p ActiveEnterTimestamp --value)" --no-pager | grep -q 'Done ('; then break; fi
  sleep 2
done
systemctl is-active minecraft.service
ss -ltnp | grep ':25565 '
sha256sum "$MOD"
START=$(systemctl show minecraft.service -p ActiveEnterTimestamp --value)
journalctl -u minecraft.service --since "$START" --no-pager | tail -n 160
if ! journalctl -u minecraft.service --since "$START" --no-pager | grep -q 'Done ('; then
  echo SERVER_NOT_READY
  exit 43
fi
if journalctl -u minecraft.service --since "$START" --no-pager | grep -Eqi 'InjectionError|InvalidMixin|MixinApplyError|Could not execute entrypoint|Exception in server tick loop|Failed to start the minecraft server'; then
  echo FATAL_RUNTIME_ERROR
  exit 42
fi

rm -rf "$OUT"
mkdir -p "$OUT"
python3 - <<'PY'
from pathlib import Path
import re
out=Path.cwd()/'control/generated'
runtime=Path('/opt/brigada-hotfix-src/src/main/java/dev/brigada13/hotfix/RuntimeFixes.java').read_text()
runtime=runtime.replace('package dev.brigada13.hotfix;', 'package dev.brigada13.core.challenge;', 1)
runtime=runtime.replace('import dev.brigada13.core.challenge.ChallengeDefinition;\n','')
runtime=runtime.replace('import dev.brigada13.core.challenge.ChallengeDifficulty;\n','')
runtime=runtime.replace('import dev.brigada13.core.challenge.ChallengeKind;\n','')
runtime=runtime.replace('import dev.brigada13.core.challenge.MiniEventMechanic;\n','')
runtime=re.sub(r'\bRuntimeFixes\b', 'ChallengeRuntimeFixes', runtime)
(out/'ChallengeRuntimeFixes.java').write_text(runtime)
PY

grep -nA6 -B2 'double damageMultiplier' "$SRC"
grep -nA8 -B2 'baseAttack = attack.getBaseValue' "$SRC"
echo HARD_DAMAGE_REBALANCE_ACTIVE