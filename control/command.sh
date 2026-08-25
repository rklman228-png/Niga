set -euo pipefail
SRC=/opt/brigada-core-src/src/main/java/dev/brigada13/core/challenge/ChallengeService.java

echo '=== eventZones refs ==='
grep -n 'eventZones' "$SRC" || true
for n in $(grep -n 'eventZones' "$SRC" | cut -d: -f1 | head -n 12); do
  a=$((n-14)); [ $a -lt 1 ] && a=1; b=$((n+24));
  echo "--- lines $a-$b ---"
  sed -n "${a},${b}p" "$SRC"
done

echo '=== mechanic enum ==='
cat /opt/brigada-core-src/src/main/java/dev/brigada13/core/challenge/MiniEventMechanic.java || true
