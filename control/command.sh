set -euo pipefail
OUT="$GITHUB_WORKSPACE/control/generated"
rm -rf "$OUT"
mkdir -p "$OUT"

for i in $(seq 1 120); do
  if ss -ltn | grep -q ':25565 '; then break; fi
  sleep 2
done

echo '=== server health ==='
systemctl is-active minecraft.service
ss -ltnp | grep ':25565 '
sha256sum /opt/minecraft/server/mods/brigada-hotfix-1.0.0.jar
START=$(systemctl show minecraft.service -p ActiveEnterTimestamp --value)
echo "service_started=$START"
journalctl -u minecraft.service --since "$START" --no-pager | grep -E 'Done \(|ERROR|Exception|InjectionError|InvalidMixin|MixinApplyError|Can.t keep up|full-height boundary|boundary restored' | tail -n 120 || true

python3 - <<'PY'
from pathlib import Path
import re, zipfile
out=Path.cwd()/'control/generated'
runtime=Path('/opt/brigada-hotfix-src/src/main/java/dev/brigada13/hotfix/RuntimeFixes.java').read_text()
runtime=runtime.replace('package dev.brigada13.hotfix;', 'package dev.brigada13.core.challenge;', 1)
for imp in (
    'import dev.brigada13.core.challenge.ChallengeDefinition;\n',
    'import dev.brigada13.core.challenge.ChallengeDifficulty;\n',
    'import dev.brigada13.core.challenge.ChallengeKind;\n',
    'import dev.brigada13.core.challenge.MiniEventMechanic;\n'):
    runtime=runtime.replace(imp,'')
runtime=re.sub(r'\bRuntimeFixes\b', 'ChallengeRuntimeFixes', runtime)
(out/'ChallengeRuntimeFixes.java').write_text(runtime)

mixin=Path('/opt/brigada-hotfix-src/src/main/java/dev/brigada13/hotfix/mixin/ChallengeServiceMixin.java').read_text()
mixin=mixin.replace('package dev.brigada13.hotfix.mixin;', 'package dev.brigada13.core.mixin;', 1)
mixin=mixin.replace('import dev.brigada13.hotfix.RuntimeFixes;', 'import dev.brigada13.core.challenge.ChallengeRuntimeFixes;', 1)
mixin=mixin.replace('RuntimeFixes.', 'ChallengeRuntimeFixes.')
(out/'ChallengeServiceMixin.java').write_text(mixin)

wm=Path('/opt/brigada-hotfix-src/src/main/java/dev/brigada13/hotfix/mixin/WorldMenuServiceMixin.java').read_text()
wm=wm.replace('package dev.brigada13.hotfix.mixin;', 'package dev.brigada13.core.mixin;', 1)
(out/'WorldMenuServiceMixin.java').write_text(wm)

with zipfile.ZipFile('/opt/minecraft/resourcepack/world-ui-26.3-snapshot-9.zip') as z:
    (out/'item_icons.json').write_bytes(z.read('assets/brigada_core/font/item_icons.json'))
PY

echo '=== live balance snapshot ==='
sha256sum "$OUT"/*
grep -nE 'splitSoloPointTicks|splitDuoTicks|tickSplitPressure|reinforceHardVillageRaid|healthMultiplier|damageMultiplier|ModifyConstant' "$OUT/ChallengeRuntimeFixes.java" "$OUT/ChallengeServiceMixin.java"

echo BRIGADA_BALANCE_HEALTH_OK
