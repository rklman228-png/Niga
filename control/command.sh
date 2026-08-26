set -euo pipefail
HOT=/opt/brigada-hotfix-src
SRC="$HOT/src/main/java/dev/brigada13/hotfix/RuntimeFixes.java"
MOD=/opt/minecraft/server/mods/brigada-hotfix-1.0.0.jar
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
cp -a "$SRC" "$SRC.bak-$STAMP"
cp -a "$MOD" "$MOD.bak-$STAMP"

python3 - <<'PY'
from pathlib import Path
p=Path('/opt/brigada-hotfix-src/src/main/java/dev/brigada13/hotfix/RuntimeFixes.java')
s=p.read_text()

def add_import(anchor, text):
    global s
    if text.strip() not in s:
        if anchor not in s: raise SystemExit(f'import anchor missing: {anchor!r}')
        s=s.replace(anchor, anchor+text, 1)

add_import('import net.fabricmc.fabric.api.event.player.PlayerBlockBreakEvents;\n',
           'import net.fabricmc.fabric.api.event.player.UseItemCallback;\nimport net.fabricmc.fabric.api.event.player.UseBlockCallback;\n')
add_import('import net.minecraft.core.BlockPos;\n', 'import net.minecraft.core.component.DataComponents;\n')
add_import('import net.minecraft.world.entity.projectile.Projectile;\n', 'import net.minecraft.world.entity.projectile.AbstractArrow;\n')
add_import('import net.minecraft.world.item.ItemStack;\n', 'import net.minecraft.world.item.BlockItem;\n')
add_import('import net.minecraft.world.level.block.Block;\n', 'import net.minecraft.world.InteractionResult;\n')

# Register immediate use/place/break restrictions. This closes the wind-charge/perl instant-use hole.
old='''        PlayerBlockBreakEvents.BEFORE.register((level, player, pos, blockState, blockEntity) ->\n                !(level instanceof ServerLevel serverLevel) || !isFullBoundaryPosition(serverLevel, pos));\n        ServerTickEvents.END_SERVER_TICK.register(RuntimeFixes::tick);'''
new='''        PlayerBlockBreakEvents.BEFORE.register((level, player, pos, blockState, blockEntity) -> {\n            if (!(level instanceof ServerLevel serverLevel)) return true;\n            if (player instanceof ServerPlayer serverPlayer && isMiniEventParticipant(serverPlayer)) return false;\n            return !isFullBoundaryPosition(serverLevel, pos);\n        });\n        UseItemCallback.EVENT.register((player, level, hand) -> {\n            if (!(player instanceof ServerPlayer serverPlayer) || !isChallengeParticipant(serverPlayer))\n                return InteractionResult.PASS;\n            ItemStack stack = player.getItemInHand(hand);\n            return isForbiddenChallengeUse(serverPlayer, stack) ? InteractionResult.FAIL : InteractionResult.PASS;\n        });\n        UseBlockCallback.EVENT.register((player, level, hand, hitResult) -> {\n            if (!(player instanceof ServerPlayer serverPlayer) || !isMiniEventParticipant(serverPlayer))\n                return InteractionResult.PASS;\n            return player.getItemInHand(hand).getItem() instanceof BlockItem ? InteractionResult.FAIL : InteractionResult.PASS;\n        });\n        ServerTickEvents.END_SERVER_TICK.register(RuntimeFixes::tick);'''
if old in s:
    s=s.replace(old,new,1)
elif 'UseItemCallback.EVENT.register' not in s:
    raise SystemExit('register anchor missing')

# Scale arrows/bolts shot by tracked event mobs. ATTACK_DAMAGE does not affect crossbow projectiles.
old='''    private static void onEntityLoad(Entity entity, ServerLevel level) {\n        if (entity instanceof Projectile projectile && isForbiddenChallengeProjectile(entity)) {'''
new='''    private static void onEntityLoad(Entity entity, ServerLevel level) {\n        if (entity instanceof AbstractArrow arrow) scaleEventArrow(level, arrow);\n        if (entity instanceof Projectile projectile && isForbiddenChallengeProjectile(entity)) {'''
if old in s:
    s=s.replace(old,new,1)
elif 'scaleEventArrow(level, arrow)' not in s:
    raise SystemExit('onEntityLoad anchor missing')

# Tick: outsider expulsion immediately after participant confinement.
old='''                ensureFullHeightBoundary(level, state);\n                confineParticipants(server, level, state);\n                scaleEventMobs(level, definition, state);'''
new='''                ensureFullHeightBoundary(level, state);\n                confineParticipants(server, level, state);\n                expelOutsiders(level, state);\n                scaleEventMobs(level, definition, state);'''
if old in s:
    s=s.replace(old,new,1)
elif 'expelOutsiders(level, state);' not in s:
    raise SystemExit('tick confinement anchor missing')

# Tick fallback also stops all food in mini-events, not merely the old banned list.
old='''            if (player.isUsingItem() && isForbiddenChallengeItem(player.getUseItem())) {\n                player.stopUsingItem();\n            }'''
new='''            if (player.isUsingItem() && isForbiddenChallengeUse(player, player.getUseItem())) {\n                player.stopUsingItem();\n            }'''
if old in s:
    s=s.replace(old,new,1)
elif 'isForbiddenChallengeUse(player, player.getUseItem())' not in s:
    raise SystemExit('restriction tick anchor missing')

# Broaden wind-charge entity fallback; mappings may use breeze_wind_charge for the actual projectile.
s=s.replace('''            case "minecraft:ender_pearl", "minecraft:wind_charge",\n                    "minecraft:potion", "minecraft:firework_rocket" -> true;''',
'''            case "minecraft:ender_pearl", "minecraft:wind_charge", "minecraft:breeze_wind_charge",\n                    "minecraft:potion", "minecraft:firework_rocket" -> true;''')

# Add helpers before continuousPressureMechanic.
marker='''    private static boolean continuousPressureMechanic(MiniEventMechanic mechanic) {'''
helpers='''    private static boolean isMiniEventParticipant(ServerPlayer player) {\n        ActiveChallengeState state = activeEvent();\n        return state != null && state.contribution != null\n                && state.contribution.containsKey(player.getName().getString());\n    }\n\n    private static boolean isForbiddenChallengeUse(ServerPlayer player, ItemStack stack) {\n        if (isForbiddenChallengeItem(stack)) return true;\n        return isMiniEventParticipant(player) && stack != null && !stack.isEmpty() && stack.has(DataComponents.FOOD);\n    }\n\n    private static void scaleEventArrow(ServerLevel level, AbstractArrow arrow) {\n        Entity owner = arrow.getOwner();\n        if (owner == null) return;\n        ActiveChallengeState state = activeEvent();\n        if (state == null || eventLevel(level.getServer(), state) != level) return;\n        if (!state.eventEntities.contains(owner.getUUID())\n                && (state.targetEntityId == null || !state.targetEntityId.equals(owner.getUUID()))) return;\n        ChallengeDefinition definition;\n        try { definition = BrigadaCore.challenges().require(state.challengeId); }\n        catch (RuntimeException ignored) { return; }\n        double multiplier = switch (definition.difficulty()) {\n            case EASY -> 1.00;\n            case NORMAL -> 1.65;\n            case HARD -> 2.50;\n        };\n        if (multiplier != 1.0) arrow.setBaseDamage(arrow.getBaseDamage() * multiplier);\n    }\n\n    private static void expelOutsiders(ServerLevel level, ActiveChallengeState state) {\n        if (state.contribution == null) return;\n        double minX = state.arenaMinX;\n        double maxX = state.arenaMaxX + 1.0;\n        double minZ = state.arenaMinZ;\n        double maxZ = state.arenaMaxZ + 1.0;\n        for (ServerPlayer player : level.players()) {\n            if (state.contribution.containsKey(player.getName().getString())) continue;\n            double x = player.getX(), z = player.getZ();\n            if (x < minX || x > maxX || z < minZ || z > maxZ) continue;\n\n            double left = x - minX, right = maxX - x, top = z - minZ, bottom = maxZ - z;\n            double nx=x, nz=z;\n            if (left <= right && left <= top && left <= bottom) nx = minX - 1.35;\n            else if (right <= top && right <= bottom) nx = maxX + 1.35;\n            else if (top <= bottom) nz = minZ - 1.35;\n            else nz = maxZ + 1.35;\n\n            BlockPos safe = findSafeFeet(level, (int)Math.floor(nx), (int)Math.floor(nz), (int)Math.floor(player.getY()));\n            double ny = safe != null ? safe.getY() : player.getY();\n            if (safe != null) { nx = safe.getX() + 0.5; nz = safe.getZ() + 0.5; }\n            player.teleportTo(nx, ny, nz);\n            player.setDeltaMovement(0.0, Math.min(0.0, player.getDeltaMovement().y), 0.0);\n        }\n    }\n\n'''
if 'private static void scaleEventArrow' not in s:
    if marker not in s: raise SystemExit('helper marker missing')
    s=s.replace(marker,helpers+marker,1)

p.write_text(s)
print('patched projectile damage, food/place/break bans, wind-charge hard block, outsider expulsion')
PY

cd "$HOT"
echo '=== build locally on VPS ==='
set +e
./gradlew clean build --no-daemon --stacktrace > /tmp/brigada-build.log 2>&1
STATUS=$?
set -e
cat /tmp/brigada-build.log
if [ "$STATUS" -ne 0 ]; then
  echo BUILD_FAILED_NO_DEPLOY
  exit "$STATUS"
fi
JAR=build/libs/brigada-hotfix-0.1.0.jar
test -s "$JAR"
sha256sum "$JAR"
install -m 0644 "$JAR" "$MOD"

systemctl restart minecraft.service
sleep 2
START=$(systemctl show minecraft.service -p ActiveEnterTimestamp --value)
for i in $(seq 1 120); do
  if journalctl -u minecraft.service --since "$START" --no-pager | grep -q 'Done ('; then break; fi
  sleep 2
done

echo '=== verify ==='
systemctl is-active minecraft.service
ss -ltnp | grep ':25565 '
sha256sum "$MOD"
journalctl -u minecraft.service --since "$START" --no-pager | grep 'Done (' | tail -n 1
! journalctl -u minecraft.service --since "$START" --no-pager | grep -Eqi 'InjectionError|InvalidMixin|MixinApplyError|Could not execute entrypoint|Exception in server tick loop|Failed to start the minecraft server'

echo '=== live anchors ==='
grep -nA14 -B2 'scaleEventArrow' "$SRC" | head -n 45
grep -nA18 -B2 'UseItemCallback.EVENT' "$SRC" | head -n 50
grep -nA24 -B2 'expelOutsiders' "$SRC" | head -n 70
echo EVENT_COMBAT_LOCKDOWN_ACTIVE
