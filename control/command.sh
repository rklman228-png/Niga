set -euo pipefail
J=/root/.gradle/caches/fabric-loom/minecraftMaven/net/minecraft/minecraft-merged-deobf/26.3-snapshot-9/minecraft-merged-deobf-26.3-snapshot-9.jar
for C in net.minecraft.network.chat.ClickEvent net.minecraft.network.chat.ClickEvent\$RunCommand net.minecraft.core.Holder net.minecraft.network.protocol.common.ClientboundClearDialogPacket net.minecraft.server.dialog.NoticeDialog; do
 echo "===== $C"
 javap -classpath "$J" -p "$C" 2>/dev/null || true
done
