set -euo pipefail
JAR=/root/.gradle/caches/fabric-loom/26.3-snapshot-9/minecraft-merged.jar
echo 'DIALOG CLASSES'
unzip -l "$JAR" | awk '{print $4}' | grep -E 'network/protocol/.+Dialog.+class$' | sort
echo 'COMMON DIALOG PACKETS'
for c in $(unzip -l "$JAR" | awk '{print $4}' | grep -E 'network/protocol/.+Dialog.+class$' | sed 's#/#.#g;s#.class$##' | grep -v '\$'); do javap -classpath "$JAR" "$c" | head -20; done
echo 'STRUCTURE TAG FILES'
unzip -l "$JAR" | awk '{print $4}' | grep '^data/minecraft/tags/worldgen/structure/.*json$' | sort
echo 'STRUCTURE KEYS'
javap -classpath "$JAR" -constants net.minecraft.world.level.levelgen.structure.BuiltinStructures | sed -n '1,240p' || true
