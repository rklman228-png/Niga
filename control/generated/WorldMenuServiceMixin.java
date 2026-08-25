package dev.brigada13.core.mixin;

import dev.brigada13.core.menu.WorldMenuService;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.resources.Identifier;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

@Mixin(WorldMenuService.class)
public abstract class WorldMenuServiceMixin {
    @Inject(method = "itemIcon", at = @At("HEAD"), cancellable = true, require = 0)
    private static void brigada$vanillaItemIcon(String itemId, CallbackInfoReturnable<Character> cir) {
        if (itemId == null) return;
        try {
            Identifier key = Identifier.parse(itemId);
            var item = BuiltInRegistries.ITEM.getValue(key);
            if (item == null || !key.equals(BuiltInRegistries.ITEM.getKey(item))) return;
            int codepoint = 0xE300 + BuiltInRegistries.ITEM.getId(item);
            if (codepoint >= 0xE300 && codepoint <= 0xF8FF) {
                cir.setReturnValue((char) codepoint);
            }
        } catch (RuntimeException ignored) {
        }
    }
}
