set -euo pipefail
cd /opt/brigada-core-src
MINE=$(find ~/.gradle/caches/fabric-loom -type f \( -name '*minecraft*.jar' -o -name '*merged*.jar' \) | head -n1 || true)
if [ -z "$MINE" ]; then MINE=$(find ~/.gradle/caches -type f -name '*.jar' | while read -r j; do jar tf "$j" 2>/dev/null | grep -q 'net/minecraft/server/level/ServerPlayer.class' && { echo "$j"; break; }; done); fi
echo "MINE=$MINE"
jar tf "$MINE" | grep -E 'net/minecraft/resources/(ResourceLocation|Identifier)\.class' || true
for C in net.minecraft.resources.Identifier net.minecraft.server.level.ServerPlayer net.minecraft.world.entity.LivingEntity net.minecraft.server.level.ServerLevel net.minecraft.server.MinecraftServer net.minecraft.network.chat.Style; do
 echo "=== $C ==="
 javap -classpath "$MINE" "$C" 2>&1 | grep -E 'class |interface |parse|fromNamespace|getServer|serverLevel|level\(|sendSystemMessage|displayClientMessage|withFont|font' | head -n 120 || true
done
