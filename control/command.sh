set -euo pipefail
MINE=/root/.gradle/caches/fabric-loom/26.3-snapshot-9/minecraft-merged.jar
for C in net.minecraft.server.players.PlayerList net.minecraft.server.players.UserWhiteList net.minecraft.world.entity.EntityType net.minecraft.world.entity.EntitySpawnReason net.minecraft.world.entity.monster.Vindicator net.minecraft.world.entity.monster.Evoker net.minecraft.server.level.ServerLevel; do
 echo "=== $C ==="
 javap -classpath "$MINE" "$C" 2>&1 | grep -E 'class |interface |White|white|create\(|addFresh|finalizeSpawn|moveTo|setPos|getUser|isWhite|EntitySpawnReason|VINDICATOR|EVOKER' | head -n 180 || true
done
