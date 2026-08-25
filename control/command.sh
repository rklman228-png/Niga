set -euo pipefail
want=4836320d63d1db7d3cb2b11607679ca8e0a06d96
for d in /opt/brigada-build* /opt/brigada-core-src; do
  [ -d "$d" ] || continue
  f="$d/src/main/java/dev/brigada13/core/challenge/ChallengeService.java"
  [ -f "$f" ] || continue
  h=$(git hash-object "$f")
  printf '%s  %s\n' "$h" "$d"
  if [ "$h" = "$want" ]; then echo "MATCH=$d"; fi
done
