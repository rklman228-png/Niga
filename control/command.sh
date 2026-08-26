set -euo pipefail
LIVE=/opt/brigada-hotfix-src/src/main/java/dev/brigada13/hotfix/RuntimeFixes.java
OUT="$GITHUB_WORKSPACE/control/generated"
mkdir -p "$OUT"
export OUT
python3 - <<'PY'
from pathlib import Path
import os,re
live=Path('/opt/brigada-hotfix-src/src/main/java/dev/brigada13/hotfix/RuntimeFixes.java').read_text()
live=live.replace('package dev.brigada13.hotfix;', 'package dev.brigada13.core.challenge;', 1)
live=live.replace('import dev.brigada13.core.challenge.ChallengeDefinition;\n','')
live=live.replace('import dev.brigada13.core.challenge.ChallengeDifficulty;\n','')
live=live.replace('import dev.brigada13.core.challenge.ChallengeKind;\n','')
live=live.replace('import dev.brigada13.core.challenge.MiniEventMechanic;\n','')
live=re.sub(r'\bRuntimeFixes\b', 'ChallengeRuntimeFixes', live)
out=Path(os.environ['OUT'])/'ChallengeRuntimeFixes.java'
out.write_text(live)
print('bytes', out.stat().st_size)
PY
sha256sum "$OUT/ChallengeRuntimeFixes.java"
grep -nA18 -B2 'scaleEventArrow' "$OUT/ChallengeRuntimeFixes.java" | head -n 50
grep -nA18 -B2 'UseItemCallback.EVENT' "$OUT/ChallengeRuntimeFixes.java" | head -n 50
grep -nA26 -B2 'expelOutsiders' "$OUT/ChallengeRuntimeFixes.java" | head -n 70
echo LIVE_COMBAT_LOCKDOWN_SNAPSHOT_OK
