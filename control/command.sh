#!/usr/bin/env bash
set -Eeuo pipefail
src=/opt/brigada-core-src
cd "$src"

echo "=== LOOM CACHE ==="
find /root/.gradle/caches/fabric-loom -type f 2>/dev/null | sed -n '1,120p'

echo "=== FABRIC API EVENT CLASSES ==="
find /root/.gradle/caches/modules-2/files-2.1/net.fabricmc.fabric-api -type f -name '*.jar' -print0 |
  xargs -0 -r -n1 sh -c 'jar tf "$0" 2>/dev/null | grep -E "(ServerTickEvents|ServerPlayerEvents|ServerLivingEntityEvents|ServerPlayConnectionEvents|CommandRegistrationCallback)\.class$" && echo "JAR=$0"' |
  sed -n '1,200p'

echo "=== MINECRAFT JARS ==="
find /root/.gradle/caches -type f -name '*.jar' | grep -E '26\.3-snapshot-9|minecraft.*26\.3|minecraft.*project' | sed -n '1,120p'

echo "INTROSPECT_OK"
