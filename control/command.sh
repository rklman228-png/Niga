set -euo pipefail
CP=/root/.gradle/caches/fabric-loom/26.3-snapshot-9/minecraft-merged.jar

echo '=== magma class ==='
jar tf "$CP" | grep -E '/MagmaCube\.class$|/Slime\.class$' | head -n 20

echo '=== registry methods ==='
javap -classpath "$CP" -p net.minecraft.core.Registry | grep -E 'getId|getKey|getValue|iterator' || true
javap -classpath "$CP" -p net.minecraft.core.MappedRegistry | grep -E 'getId|getKey|getValue|iterator' || true
