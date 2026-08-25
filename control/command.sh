set -euo pipefail
J=/root/.gradle/caches/fabric-loom/minecraftMaven/net/minecraft/minecraft-merged-deobf/26.3-snapshot-9/minecraft-merged-deobf-26.3-snapshot-9.jar
jar tf "$J" | grep -E 'Click(Type|Action)\.class$|AbstractContainerMenu.class$'
javap -classpath "$J" net.minecraft.world.inventory.AbstractContainerMenu | grep -E 'clicked|quickMoveStack|stillValid'
