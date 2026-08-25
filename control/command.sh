set -euo pipefail
J=/opt/minecraft/server/mods/brigada-core-0.1.0.jar
OUT=/tmp/challenge.javap
javap -classpath "$J" -c -p dev.brigada13.core.challenge.ChallengeService > "$OUT"

echo '=== eventZones bytecode refs ==='
grep -n -B45 -A80 'eventZones' "$OUT" | head -n 520 || true

echo '=== likely zone/ring helpers ==='
grep -nE 'Zone|zone|ring|Circle|circle|hold|Hold|split|Split|extraction|Extraction|Particle|particle' "$OUT" | tail -n 220 || true
