set -euo pipefail
SRC=/opt/brigada-hotfix-src/src/main/java/dev/brigada13/hotfix/RuntimeFixes.java
MOD=/opt/minecraft/server/mods/brigada-hotfix-1.0.0.jar
OUT="$GITHUB_WORKSPACE/control/generated"

echo '=== live health ==='
systemctl is-active minecraft.service
ss -ltnp | grep ':25565 '
sha256sum "$MOD"
START=$(systemctl show minecraft.service -p ActiveEnterTimestamp --value)
journalctl -u minecraft.service --since "$START" --no-pager | grep 'Done (' | tail -n 1

echo '=== active balance ==='
grep -nA6 -B2 'double damageMultiplier' "$SRC"
grep -nA8 -B2 'baseAttack = attack.getBaseValue' "$SRC"

rm -rf "$OUT"
mkdir -p "$OUT"
export BRIGADA_OUT="$OUT"
python3 - <<'PY'
from pathlib import Path
import os,re
out=Path(os.environ['BRIGADA_OUT'])
runtime=Path('/opt/brigada-hotfix-src/src/main/java/dev/brigada13/hotfix/RuntimeFixes.java').read_text()
runtime=runtime.replace('package dev.brigada13.hotfix;', 'package dev.brigada13.core.challenge;', 1)
runtime=runtime.replace('import dev.brigada13.core.challenge.ChallengeDefinition;\n','')
runtime=runtime.replace('import dev.brigada13.core.challenge.ChallengeDifficulty;\n','')
runtime=runtime.replace('import dev.brigada13.core.challenge.ChallengeKind;\n','')
runtime=runtime.replace('import dev.brigada13.core.challenge.MiniEventMechanic;\n','')
runtime=re.sub(r'\bRuntimeFixes\b', 'ChallengeRuntimeFixes', runtime)
(out/'ChallengeRuntimeFixes.java').write_text(runtime)
print('snapshot bytes', (out/'ChallengeRuntimeFixes.java').stat().st_size)
PY
sha256sum "$OUT/ChallengeRuntimeFixes.java"
echo HARD_DAMAGE_SNAPSHOT_OK