set -euo pipefail
OUT="$GITHUB_WORKSPACE/control/generated"
rm -rf "$OUT"
mkdir -p "$OUT"
python3 - <<'PY'
from pathlib import Path
import re, zipfile
out=Path.cwd()/'control/generated'
runtime=Path('/opt/brigada-hotfix-src/src/main/java/dev/brigada13/hotfix/RuntimeFixes.java').read_text()
runtime=runtime.replace('package dev.brigada13.hotfix;', 'package dev.brigada13.core.challenge;', 1)
runtime=runtime.replace('import dev.brigada13.core.challenge.ChallengeDefinition;\n','')
runtime=runtime.replace('import dev.brigada13.core.challenge.ChallengeKind;\n','')
runtime=runtime.replace('import dev.brigada13.core.challenge.MiniEventMechanic;\n','')
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
print('generated', *(p.name for p in sorted(out.iterdir())))
PY

echo '=== snapshots ==='
sha256sum "$OUT"/*
wc -c "$OUT"/*
grep -nE 'ensureFullHeightBoundary|restoreBoundary|scheduleWavePulse|PORTAL|replaceCoreVictoryParticles' "$OUT/ChallengeRuntimeFixes.java" "$OUT/ChallengeServiceMixin.java" | head -n 80

echo '=== lag since ready ==='
journalctl -u minecraft.service --since '2026-08-25 18:22:30 UTC' --no-pager | grep -E "Can't keep up|Done \(|full-height boundary|boundary restored" || true
ps -p $(systemctl show -p MainPID --value minecraft.service) -o pid,%cpu,%mem,etime,cmd
ss -ltnp | grep ':25565 '
echo SNAPSHOT_AND_LAG_CHECK_OK
