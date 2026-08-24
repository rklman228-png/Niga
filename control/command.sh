set -euo pipefail
MINE=/root/.gradle/caches/fabric-loom/26.3-snapshot-9/minecraft-merged.jar
for C in 'net.minecraft.network.chat.FontDescription$Resource' 'net.minecraft.network.chat.FontDescription$Unifont'; do
 echo "=== $C ==="; javap -classpath "$MINE" "$C" 2>&1 | head -n 120; done
