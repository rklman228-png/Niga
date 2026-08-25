set -euo pipefail
JAR=$(find ~/.gradle/caches -type f -name '*fabric-entity-events-v1*.jar' -print -quit)
CP=$(find ~/.gradle/caches -type f -name 'minecraft-merged.jar' -print -quit)
echo '=== callback ==='
javap -classpath "$JAR:$CP" 'net.fabricmc.fabric.api.entity.event.v1.ServerLivingEntityEvents$AllowDamage' || true
echo '=== damage source/types ==='
javap -classpath "$CP" net.minecraft.world.damagesource.DamageSource | grep -E ' is\(|getMsgId|typeHolder' || true
javap -classpath "$CP" net.minecraft.world.damagesource.DamageTypes | grep -E 'FALL|IN_FIRE|ON_FIRE' || true
echo '=== sound play ==='
javap -classpath "$CP" net.minecraft.server.level.ServerLevel | grep 'playSound' | head -n 30 || true
