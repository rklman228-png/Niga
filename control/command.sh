set -euo pipefail
J=/root/.gradle/caches/fabric-loom/minecraftMaven/net/minecraft/minecraft-merged-deobf/26.3-snapshot-9/minecraft-merged-deobf-26.3-snapshot-9.jar
for C in  net.minecraft.server.dialog.CommonDialogData  net.minecraft.server.dialog.CommonButtonData  net.minecraft.server.dialog.ActionButton  net.minecraft.server.dialog.MultiActionDialog  net.minecraft.server.dialog.Dialog  net.minecraft.server.dialog.DialogAction  net.minecraft.server.dialog.action.StaticAction  net.minecraft.server.dialog.action.Action  net.minecraft.server.dialog.body.PlainMessage  net.minecraft.server.dialog.body.ItemBody  net.minecraft.network.protocol.common.ClientboundShowDialogPacket  net.minecraft.world.waypoints.Waypoint  net.minecraft.world.waypoints.Waypoint\$Icon  net.minecraft.world.waypoints.WaypointTransmitter  net.minecraft.world.waypoints.WaypointTransmitter\$BlockConnection  net.minecraft.server.waypoints.ServerWaypointManager; do
 echo "===== $C"
 javap -classpath "$J" -p "$C" 2>/dev/null || true
done
