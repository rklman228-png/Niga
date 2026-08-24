set -euo pipefail
MINE=/root/.gradle/caches/fabric-loom/26.3-snapshot-9/minecraft-merged.jar
for C in net.minecraft.server.level.ServerLevel net.minecraft.world.level.StructureManager net.minecraft.world.level.levelgen.structure.StructureStart net.minecraft.world.level.levelgen.structure.BoundingBox net.minecraft.tags.StructureTags net.minecraft.world.level.block.entity.RandomizableContainerBlockEntity net.minecraft.world.level.block.entity.BaseContainerBlockEntity net.minecraft.world.level.storage.loot.LootTable; do
 echo "=== $C ==="
 javap -classpath "$MINE" "$C" 2>&1 | grep -E 'class |interface |findNearest|structure|Structure|Bounding|BlockEntity|getEntities|Loot|loot|setLoot|isEmpty|fill|createTagKey|TagKey|spawn|Position' | head -n 220 || true
done
printf '\n=== STRUCTURE TAG FILES ===\n'
jar tf "$MINE" | grep '^data/minecraft/tags/worldgen/structure/.*\.json$' | head -n 100 || true
