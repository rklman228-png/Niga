set -euo pipefail
server=/opt/minecraft/server/mods/brigada-core-0.1.0.jar
server_sha=$(sha256sum "$server" | awk '{print $1}')
echo "server_sha=$server_sha"

for d in /opt/brigada-build* /opt/brigada-core-src; do
  [ -d "$d" ] || continue
  jar="$d/build/libs/brigada-core-0.1.0.jar"
  if [ -f "$jar" ]; then
    sha=$(sha256sum "$jar" | awk '{print $1}')
    mt=$(stat -c '%y' "$jar")
    printf '%s  %s  %s\n' "$sha" "$mt" "$d"
    if [ "$sha" = "$server_sha" ]; then
      echo "MATCH=$d"
      echo '--- key source hashes ---'
      sha256sum "$d/src/main/java/dev/brigada13/core/challenge/ChallengeService.java" 2>/dev/null || true
      sha256sum "$d/src/main/java/dev/brigada13/core/particle/ParticleOptimizer.java" 2>/dev/null || true
      sha256sum "$d/src/main/resources/brigada_core.mixins.json" 2>/dev/null || true
      ls -lah "$d/src/main/java/dev/brigada13/core/mixin" || true
    fi
  fi
done
