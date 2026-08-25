set -euo pipefail
J=/root/.gradle/caches/fabric-loom/minecraftMaven/net/minecraft/minecraft-merged-deobf/26.3-snapshot-9/minecraft-merged-deobf-26.3-snapshot-9.jar
javap -classpath "$J" -p net.minecraft.world.entity.player.Inventory
jar tf "$J" | grep '/Prediction.class$' | head -30
