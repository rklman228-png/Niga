#!/usr/bin/env bash
set -Eeuo pipefail
mc=/root/.gradle/caches/fabric-loom/minecraftMaven/net/minecraft/minecraft-merged-deobf/26.3-snapshot-9/minecraft-merged-deobf-26.3-snapshot-9.jar
cp="$mc"
while IFS= read -r -d '' jarfile; do cp="$cp:$jarfile"; done < <(find /root/.gradle/caches/modules-2/files-2.1 -type f -name '*.jar' -print0)

echo "=== FABRIC SIGNATURES ==="
for cls in \
 'net.fabricmc.fabric.api.event.lifecycle.v1.ServerTickEvents' \
 'net.fabricmc.fabric.api.entity.event.v1.ServerLivingEntityEvents' \
 'net.fabricmc.fabric.api.entity.event.v1.ServerPlayerEvents' \
 'net.fabricmc.fabric.api.networking.v1.ServerPlayConnectionEvents' \
 'net.fabricmc.fabric.api.command.v2.CommandRegistrationCallback'; do
  echo "--- $cls"
  javap -classpath "$cp" -public "$cls" | sed -n '1,200p'
done

echo "=== MC SELECTED METHODS ==="
for cls in \
 'net.minecraft.server.level.ServerPlayer' \
 'net.minecraft.world.entity.item.ItemEntity' \
 'net.minecraft.world.item.ItemStack' \
 'net.minecraft.world.entity.player.Inventory' \
 'net.minecraft.server.level.ServerLevel' \
 'net.minecraft.server.MinecraftServer' \
 'net.minecraft.world.entity.LivingEntity'; do
  echo "--- $cls"
  javap -classpath "$cp" -public "$cls" |
    grep -E 'class | interface |displayClientMessage|sendSystemMessage|getMainHandItem|setItemInHand|getInventory|add\(|drop|die\(|hurtServer|kill|discard|remove\(|isRemoved|getItem\(|setItem\(|getCount|setCount|save|parse|CODEC|position\(|getPlayers|getPlayerList|registryAccess|sendParticles|experience|award|give|createCommandSourceStack|getCommands|performPrefixedCommand|level\(|getUUID|getName|getString|damage|DamageSource|tickCount|serverLevel|isDeadOrDying|spawnAtLocation' |
    sed -n '1,240p'
done
echo "JAVAP_OK"
