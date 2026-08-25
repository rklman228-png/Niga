set -euo pipefail
MC=/root/.gradle/caches/fabric-loom/26.3-snapshot-9/minecraft-merged.jar

echo '=== MagmaCube / Slime ==='
javap -classpath "$MC" net.minecraft.world.entity.monster.MagmaCube 2>/dev/null | head -n 100 || true
javap -classpath "$MC" net.minecraft.world.entity.monster.Slime 2>/dev/null | grep -E 'getSize|setSize|remove|split|finalizeSpawn|isTiny|canSpawn' || true

echo '=== Heightmap ==='
javap -classpath "$MC" net.minecraft.world.level.levelgen.Heightmap\$Types 2>/dev/null | head -n 80 || true
javap -classpath "$MC" net.minecraft.server.level.ServerLevel 2>/dev/null | grep -E 'getHeight\(|getHeightmapPos|playSound|sendParticles' | head -n 80 || true

echo '=== Fabric ServerEntityEvents ==='
FAB=$(find /root/.gradle/caches -type f -name '*.jar' | while read f; do jar tf "$f" 2>/dev/null | grep -q 'net/fabricmc/fabric/api/event/lifecycle/v1/ServerEntityEvents.class' && { echo "$f"; break; }; done)
echo "fabric=$FAB"
[ -n "$FAB" ] && javap -classpath "$FAB:$MC" net.fabricmc.fabric.api.event.lifecycle.v1.ServerEntityEvents || true
[ -n "$FAB" ] && javap -classpath "$FAB:$MC" 'net.fabricmc.fabric.api.event.lifecycle.v1.ServerEntityEvents$Load' || true

echo '=== current hotfix key methods ==='
grep -nE 'tickMeaningfulParticles|boundaryPoint|verticalCorner|ring\(|onComplete|emitFireworkBurst|play\(|stabiliseEventMobs|register\(' /opt/brigada-hotfix-src/src/main/java/dev/brigada13/hotfix/RuntimeFixes.java | head -n 120
