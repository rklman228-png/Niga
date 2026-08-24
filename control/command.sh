#!/usr/bin/env bash
set -Eeuo pipefail
mc=/root/.gradle/caches/fabric-loom/minecraftMaven/net/minecraft/minecraft-merged-deobf/26.3-snapshot-9/minecraft-merged-deobf-26.3-snapshot-9.jar
cp="$mc"
while IFS= read -r -d '' jarfile; do cp="$cp:$jarfile"; done < <(find /root/.gradle/caches/modules-2/files-2.1 -type f -name '*.jar' -print0)

echo "=== CALLBACKS ==="
for cls in \
 'net.fabricmc.fabric.api.event.lifecycle.v1.ServerTickEvents$EndTick' \
 'net.fabricmc.fabric.api.entity.event.v1.ServerLivingEntityEvents$AllowDeath' \
 'net.fabricmc.fabric.api.entity.event.v1.ServerLivingEntityEvents$AfterDamage' \
 'net.fabricmc.fabric.api.entity.event.v1.ServerLivingEntityEvents$AfterDeath' \
 'net.fabricmc.fabric.api.entity.event.v1.ServerPlayerEvents$AfterRespawn' \
 'net.fabricmc.fabric.api.entity.event.v1.ServerPlayerEvents$Join' \
 'net.fabricmc.fabric.api.networking.v1.ServerPlayConnectionEvents$Join'; do
 echo "--- $cls"; javap -classpath "$cp" -public "$cls" | sed -n '1,120p'
done

echo "=== SERIALIZATION / UI ==="
for cls in \
 'net.minecraft.core.RegistryAccess' \
 'net.minecraft.core.HolderLookup$Provider' \
 'net.minecraft.resources.RegistryOps' \
 'net.minecraft.world.item.ItemStack' \
 'net.minecraft.network.chat.Component' \
 'net.minecraft.network.chat.MutableComponent' \
 'net.minecraft.network.chat.Style' \
 'net.minecraft.network.chat.TextColor' \
 'net.minecraft.world.entity.Entity' \
 'net.minecraft.server.players.PlayerList' \
 'net.minecraft.commands.Commands'; do
 echo "--- $cls"
 javap -classpath "$cp" -public "$cls" |
  grep -E 'class |interface |createSerialization|CODEC|copy\(|isEmpty|setCount|getCount|getHoverName|getStyledHoverName|literal|translatable|append|withStyle|color|getColor|getValue|getUUID|getName|getString|position\(|getX\(|getY\(|getZ\(|getRemovalReason|isRemoved|addTag|getTags|getPlayers|getPlayerByName|performPrefixedCommand|sendSystemMessage|displayClientMessage' |
  sed -n '1,220p'
done
echo "SIGNATURES_2_OK"
