set -euo pipefail
J=/root/.gradle/caches/fabric-loom/minecraftMaven/net/minecraft/minecraft-merged-deobf/26.3-snapshot-9/minecraft-merged-deobf-26.3-snapshot-9.jar
for C in  net.minecraft.server.level.ServerPlayer  net.minecraft.world.inventory.ChestMenu  net.minecraft.world.SimpleContainer  net.minecraft.world.MenuProvider  net.minecraft.world.SimpleMenuProvider  net.minecraft.world.item.ItemStack  net.minecraft.core.component.DataComponents  net.minecraft.world.item.component.ResolvableProfile  net.minecraft.world.item.component.ItemLore  net.minecraft.world.inventory.ClickType  net.minecraft.world.item.Items; do
  echo "===== $C"
  javap -classpath "$J" "$C" 2>/dev/null | grep -E 'openMenu|ChestMenu|rows|Row|clicked|quickMoveStack|SimpleContainer|SimpleMenuProvider|set\(|PROFILE|CUSTOM_NAME|LORE|ResolvableProfile|ItemLore|PLAYER_HEAD|BARRIER|LIME|RED|experience|removeItem|setItem|getItem|getContainerSize|stillValid|createMenu' || true
done
