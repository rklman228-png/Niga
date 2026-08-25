set -euo pipefail
MCJAR=/root/.gradle/caches/fabric-loom/26.3-snapshot-9/minecraft-merged.jar
javap -classpath "$MCJAR" -p net.minecraft.world.level.block.Block | grep -E 'getId|stateById|BLOCK_STATE_REGISTRY' || true
javap -classpath "$MCJAR" -p net.minecraft.core.particles.ParticleTypes | grep -E 'PORTAL|REVERSE_PORTAL|END_ROD|DRAGON_BREATH' || true
