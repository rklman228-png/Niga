set -euo pipefail
MINE=/root/.gradle/caches/fabric-loom/26.3-snapshot-9/minecraft-merged.jar
for C in net.minecraft.network.chat.FontDescription net.minecraft.network.protocol.game.ClientboundSetActionBarTextPacket net.minecraft.core.registries.BuiltInRegistries net.minecraft.core.Registry; do
 echo "=== $C ==="; javap -classpath "$MINE" "$C" 2>&1 | head -n 160; done
