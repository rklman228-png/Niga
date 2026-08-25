set -euo pipefail
CP=$(find ~/.gradle/caches -type f -name 'minecraft-merged.jar' -print -quit)
echo "cp=$CP"
echo '=== ServerPlayer teleport ==='
javap -classpath "$CP" net.minecraft.server.level.ServerPlayer | grep -E 'teleport|setPos|connection' | head -n 80 || true
echo '=== ServerGamePacketListenerImpl teleport ==='
javap -classpath "$CP" net.minecraft.server.network.ServerGamePacketListenerImpl | grep -E 'teleport|resetPosition' | head -n 80 || true
echo '=== Entity movement ==='
javap -classpath "$CP" net.minecraft.world.entity.Entity | grep -E 'getRootVehicle|getDeltaMovement|setDeltaMovement|setPos\(' | head -n 80 || true
