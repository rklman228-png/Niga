set -euo pipefail
HOT=/opt/brigada-hotfix-src
RUNTIME="$HOT/src/main/java/dev/brigada13/hotfix/RuntimeFixes.java"
MIXIN="$HOT/src/main/java/dev/brigada13/hotfix/mixin/ChallengeServiceMixin.java"

cat > "$RUNTIME" <<'JAVA'
package dev.brigada13.hotfix;

import dev.brigada13.core.BrigadaCore;
import dev.brigada13.core.challenge.ChallengeDefinition;
import dev.brigada13.core.challenge.ChallengeKind;
import dev.brigada13.core.challenge.MiniEventMechanic;
import dev.brigada13.core.particle.ParticleOptimizer;
import dev.brigada13.core.state.ActiveChallengeState;
import net.fabricmc.fabric.api.entity.event.v1.ServerLivingEntityEvents;
import net.fabricmc.fabric.api.event.lifecycle.v1.ServerTickEvents;
import net.minecraft.core.BlockPos;
import net.minecraft.core.particles.DustParticleOptions;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.core.registries.Registries;
import net.minecraft.resources.Identifier;
import net.minecraft.resources.ResourceKey;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvent;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.damagesource.DamageSource;
import net.minecraft.world.damagesource.DamageTypes;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.entity.Mob;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.minecraft.world.level.block.Blocks;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

public final class RuntimeFixes {
    private static final int COMPLETION_BURST_DELAY = 100;
    private static final double MOB_EDGE_MARGIN = 2.35;
    private static final Set<UUID> PREPARED_OBJECTIVES = new HashSet<>();
    private static final Map<UUID, Integer> OBJECTIVE_HEAL_STAGE = new HashMap<>();
    private static final Set<UUID> PREPARED_ELITES = new HashSet<>();
    private static final List<CompletionBurst> BURSTS = new ArrayList<>();

    private static long tick;
    private static long observedEvent = Long.MIN_VALUE;
    private static int observedWave = -1;
    private static int observedPhase = -1;

    private RuntimeFixes() {}

    public static void register() {
        ServerLivingEntityEvents.ALLOW_DAMAGE.register(RuntimeFixes::allowDamage);
        ServerLivingEntityEvents.AFTER_DAMAGE.register(RuntimeFixes::afterDamage);
        ServerTickEvents.END_SERVER_TICK.register(RuntimeFixes::tick);
    }

    private static boolean allowDamage(LivingEntity entity, DamageSource source, float amount) {
        ActiveChallengeState state = BrigadaCore.stateStore().state().activeChallenge;
        if (!isTrackedEventEntity(state, entity.getUUID())) return true;
        if (source.is(DamageTypes.FALL)) return false;
        if (source.is(DamageTypes.ON_FIRE) && entity.level() instanceof ServerLevel level
                && level.isDay() && level.canSeeSky(entity.blockPosition())) return false;
        return true;
    }

    private static boolean isTrackedEventEntity(ActiveChallengeState state, UUID id) {
        if (state == null || !state.arenaLocked) return false;
        try {
            if (BrigadaCore.challenges().require(state.challengeId).kind() != ChallengeKind.MINI_EVENT) return false;
        } catch (RuntimeException ignored) {
            return false;
        }
        return state.eventEntities.contains(id) || (state.targetEntityId != null && state.targetEntityId.equals(id));
    }

    public static void onComplete(MinecraftServer server, ActiveChallengeState state) {
        if (state == null || state.contribution == null) return;
        for (String participant : state.contribution.keySet()) {
            ServerPlayer player = server.getPlayerList().getPlayerByName(participant);
            if (player == null) continue;
            play(player.level(), player.getX(), player.getY(), player.getZ(),
                    SoundEvents.UI_TOAST_CHALLENGE_COMPLETE, 1.0F, 1.0F);
            play(player.level(), player.getX(), player.getY(), player.getZ(),
                    SoundEvents.PLAYER_LEVELUP, 0.9F, 1.05F);
        }
        BURSTS.add(new CompletionBurst(List.copyOf(state.contribution.keySet()), tick + COMPLETION_BURST_DELAY));
    }

    private static void tick(MinecraftServer server) {
        tick++;
        ActiveChallengeState state = activeEvent();
        if (state != null) {
            ChallengeDefinition definition = BrigadaCore.challenges().require(state.challengeId);
            ServerLevel level = eventLevel(server, state);
            if (level != null) {
                clearPhysicalBoundary(level, state);
                stabiliseEventMobs(level, state);
                fixDefense(level, definition, state);
                fixElite(level, definition, state);
                soundProgress(level, definition, state);
                renderMeaningfulParticles(level, definition, state);
            }
        } else {
            observedEvent = Long.MIN_VALUE;
            observedWave = -1;
            observedPhase = -1;
        }
        tickBursts(server);
    }

    private static ActiveChallengeState activeEvent() {
        ActiveChallengeState state = BrigadaCore.stateStore().state().activeChallenge;
        if (state == null || !state.arenaLocked || state.arenaDimension == null) return null;
        try {
            return BrigadaCore.challenges().require(state.challengeId).kind() == ChallengeKind.MINI_EVENT ? state : null;
        } catch (RuntimeException ignored) {
            return null;
        }
    }

    private static ServerLevel eventLevel(MinecraftServer server, ActiveChallengeState state) {
        return server.getLevel(ResourceKey.create(Registries.DIMENSION, Identifier.parse(state.arenaDimension)));
    }

    public static void clearPhysicalBoundary(ServerLevel level, ActiveChallengeState state) {
        if (state.boundaryBlocks == null || state.boundaryBlocks.isEmpty()) return;
        boolean changed = false;
        for (long packed : new ArrayList<>(state.boundaryBlocks)) {
            BlockPos pos = BlockPos.of(packed);
            var block = level.getBlockState(pos).getBlock();
            if (block == Blocks.GRAY_STAINED_GLASS || block == Blocks.BROWN_STAINED_GLASS
                    || block == Blocks.LIME_STAINED_GLASS) {
                level.setBlock(pos, Blocks.AIR.defaultBlockState(), 2);
                changed = true;
            }
        }
        state.boundaryBlocks.clear();
        state.boundaryBottomY = 0;
        state.boundaryTopY = 0;
        if (changed) BrigadaCore.stateStore().save();
    }

    private static void stabiliseEventMobs(ServerLevel level, ActiveChallengeState state) {
        Set<UUID> ids = new HashSet<>(state.eventEntities);
        if (state.targetEntityId != null) ids.add(state.targetEntityId);
        for (UUID id : ids) {
            Entity raw = level.getEntity(id);
            if (!(raw instanceof Mob mob) || !mob.isAlive()) continue;

            // No event mob may use the old perimeter as a ladder/path. Keep a real inner margin.
            double minX = state.arenaMinX + MOB_EDGE_MARGIN;
            double maxX = state.arenaMaxX + 1.0 - MOB_EDGE_MARGIN;
            double minZ = state.arenaMinZ + MOB_EDGE_MARGIN;
            double maxZ = state.arenaMaxZ + 1.0 - MOB_EDGE_MARGIN;
            if (minX > maxX) minX = maxX = (state.arenaMinX + state.arenaMaxX + 1.0) * 0.5;
            if (minZ > maxZ) minZ = maxZ = (state.arenaMinZ + state.arenaMaxZ + 1.0) * 0.5;
            double x = Math.max(minX, Math.min(maxX, mob.getX()));
            double z = Math.max(minZ, Math.min(maxZ, mob.getZ()));
            if (Math.abs(x - mob.getX()) > 0.001 || Math.abs(z - mob.getZ()) > 0.001) {
                mob.setPos(x, mob.getY(), z);
                mob.setDeltaMovement(0.0, Math.min(0.0, mob.getDeltaMovement().y), 0.0);
                mob.getNavigation().stop();
            }

            // If something still ends up on a roof/tower way above the combat floor, put it back on
            // a walkable surface near the arena anchor instead of letting it spend 15 seconds falling.
            if (mob.getY() > state.arenaY + 12.0 || mob.getY() < state.arenaY - 14.0) {
                BlockPos safe = findSafeFeet(level, (int) Math.floor(x), (int) Math.floor(z), state.arenaY);
                if (safe != null) {
                    mob.setPos(safe.getX() + 0.5, safe.getY(), safe.getZ() + 0.5);
                    mob.setDeltaMovement(0.0, 0.0, 0.0);
                    mob.getNavigation().stop();
                }
            }

            // Sunlight is not part of the encounter difficulty. Do not let undead slowly self-delete.
            if (level.isDay() && level.canSeeSky(mob.blockPosition()) && mob.isOnFire()) {
                mob.setRemainingFireTicks(0);
            }
        }
    }

    private static BlockPos findSafeFeet(ServerLevel level, int x, int z, int anchorY) {
        int top = Math.min(level.getMaxY() - 2, anchorY + 5);
        int bottom = Math.max(level.getMinY() + 1, anchorY - 12);
        for (int y = top; y >= bottom; y--) {
            BlockPos feet = new BlockPos(x, y, z);
            if (level.getBlockState(feet).isAir() && level.getBlockState(feet.above()).isAir()
                    && !level.getBlockState(feet.below()).isAir()) return feet;
        }
        return null;
    }

    private static void fixDefense(ServerLevel level, ChallengeDefinition definition, ActiveChallengeState state) {
        if (definition.mechanic() != MiniEventMechanic.DEFEND_OBJECTIVE || state.targetEntityId == null) return;
        Entity raw = level.getEntity(state.targetEntityId);
        if (!(raw instanceof LivingEntity objective) || !objective.isAlive()) return;
        if (raw instanceof Mob objectiveMob && PREPARED_OBJECTIVES.add(raw.getUUID())) {
            objectiveMob.setNoAi(true);
            objectiveMob.setPersistenceRequired();
            OBJECTIVE_HEAL_STAGE.put(raw.getUUID(), state.stage);
        }
        for (UUID id : state.eventEntities) {
            Entity entity = level.getEntity(id);
            if (entity instanceof Mob mob && mob.isAlive()) mob.setTarget(objective);
        }
        int previous = OBJECTIVE_HEAL_STAGE.getOrDefault(raw.getUUID(), state.stage);
        if (state.stage > previous) {
            float fraction = switch (definition.difficulty()) {
                case EASY -> 0.10F;
                case NORMAL -> 0.15F;
                case HARD -> 0.20F;
            };
            objective.heal(objective.getMaxHealth() * fraction);
            OBJECTIVE_HEAL_STAGE.put(raw.getUUID(), state.stage);
        }
    }

    private static void fixElite(ServerLevel level, ChallengeDefinition definition, ActiveChallengeState state) {
        boolean elite = definition.mechanic() == MiniEventMechanic.ELITE_BOSS
                || (definition.mechanic() == MiniEventMechanic.MULTI_PHASE_ASSAULT && state.eventPhase >= 2);
        if (!elite || state.targetEntityId == null) return;
        Entity raw = level.getEntity(state.targetEntityId);
        if (!(raw instanceof LivingEntity boss) || !boss.isAlive()) return;
        if (!PREPARED_ELITES.add(raw.getUUID())) return;
        double hp = switch (definition.difficulty()) {
            case EASY -> state.singleMode ? 240.0 : 360.0;
            case NORMAL -> state.singleMode ? 480.0 : 720.0;
            case HARD -> state.singleMode ? 760.0 : 1000.0;
        };
        var attribute = boss.getAttribute(Attributes.MAX_HEALTH);
        if (attribute != null) attribute.setBaseValue(Math.max(hp, boss.getMaxHealth()));
        boss.setHealth(boss.getMaxHealth());
        boss.setGlowingTag(true);
        if (raw instanceof Mob mob) mob.setPersistenceRequired();
    }

    private static void soundProgress(ServerLevel level, ChallengeDefinition definition, ActiveChallengeState state) {
        if (observedEvent != state.startedAtEpochMillis) {
            observedEvent = state.startedAtEpochMillis;
            observedWave = state.eventWave;
            observedPhase = state.eventPhase;
            playCenter(level, state, SoundEvents.BEACON_ACTIVATE, 0.9F, 1.15F);
            return;
        }
        if (state.eventPhase > observedPhase) {
            observedPhase = state.eventPhase;
            playCenter(level, state, SoundEvents.BEACON_ACTIVATE, 0.85F, 1.35F);
        }
        if (state.eventWave > observedWave) {
            observedWave = state.eventWave;
            playCenter(level, state, SoundEvents.EXPERIENCE_ORB_PICKUP, 0.8F,
                    Math.min(1.55F, 0.95F + state.eventWave * 0.08F));
        }
    }

    private static void renderMeaningfulParticles(ServerLevel level, ChallengeDefinition definition,
                                                   ActiveChallengeState state) {
        if (tick % 4 != 0) return;
        DustParticleOptions boundary = new DustParticleOptions(0xFF365E, 1.05F);
        DustParticleOptions corner = new DustParticleOptions(0xF3FBFF, 1.15F);

        // Dotted perimeter exactly on the arena footprint; no airborne carpet/cloud.
        for (int x = state.arenaMinX; x <= state.arenaMaxX; x += 4) {
            boundaryPoint(level, boundary, x, state.arenaMinZ, state.arenaY);
            boundaryPoint(level, boundary, x, state.arenaMaxZ, state.arenaY);
        }
        for (int z = state.arenaMinZ; z <= state.arenaMaxZ; z += 4) {
            boundaryPoint(level, boundary, state.arenaMinX, z, state.arenaY);
            boundaryPoint(level, boundary, state.arenaMaxX, z, state.arenaY);
        }
        verticalCorner(level, corner, state.arenaMinX, state.arenaMinZ, state.arenaY);
        verticalCorner(level, corner, state.arenaMinX, state.arenaMaxZ, state.arenaY);
        verticalCorner(level, corner, state.arenaMaxX, state.arenaMinZ, state.arenaY);
        verticalCorner(level, corner, state.arenaMaxX, state.arenaMaxZ, state.arenaY);

        if (state.targetEntityId == null) return;
        Entity raw = level.getEntity(state.targetEntityId);
        if (!(raw instanceof LivingEntity target) || !target.isAlive()) return;
        if (definition.mechanic() == MiniEventMechanic.DEFEND_OBJECTIVE) {
            ring(level, new DustParticleOptions(0xFFD34E, 1.2F), target.getX(), target.getY() + 0.12,
                    target.getZ(), 1.65, 18);
        } else if (definition.mechanic() == MiniEventMechanic.ELITE_BOSS
                || (definition.mechanic() == MiniEventMechanic.MULTI_PHASE_ASSAULT && state.eventPhase >= 2)) {
            ring(level, new DustParticleOptions(0xFF4C6A, 1.25F), target.getX(), target.getY() + 0.12,
                    target.getZ(), 1.35, 16);
            ParticleOptimizer.emit(level, ParticleTypes.ENCHANTED_HIT,
                    target.getX(), target.getY() + target.getBbHeight() * 0.55, target.getZ(),
                    12, 0.65, Math.max(0.55, target.getBbHeight() * 0.45), 0.65, 0.02);
        }
    }

    private static void boundaryPoint(ServerLevel level, DustParticleOptions particle, int x, int z, int anchorY) {
        double y = nearbySurfaceY(level, x, z, anchorY);
        ParticleOptimizer.emit(level, particle, x + 0.5, y, z + 0.5, 1, 0.0, 0.0, 0.0, 0.0);
    }

    private static void verticalCorner(ServerLevel level, DustParticleOptions particle, int x, int z, int anchorY) {
        double base = nearbySurfaceY(level, x, z, anchorY);
        for (int i = 0; i < 4; i++) {
            ParticleOptimizer.emit(level, particle, x + 0.5, base + i * 0.75, z + 0.5,
                    1, 0.0, 0.0, 0.0, 0.0);
        }
    }

    private static double nearbySurfaceY(ServerLevel level, int x, int z, int anchorY) {
        int top = Math.min(level.getMaxY() - 2, anchorY + 6);
        int bottom = Math.max(level.getMinY() + 1, anchorY - 8);
        for (int y = top; y >= bottom; y--) {
            BlockPos feet = new BlockPos(x, y, z);
            if (level.getBlockState(feet).isAir() && !level.getBlockState(feet.below()).isAir()) return y + 0.12;
        }
        return anchorY + 0.12;
    }

    private static void ring(ServerLevel level, DustParticleOptions particle,
                             double x, double y, double z, double radius, int points) {
        for (int i = 0; i < points; i++) {
            double angle = Math.PI * 2.0 * i / points;
            ParticleOptimizer.emit(level, particle, x + Math.cos(angle) * radius, y,
                    z + Math.sin(angle) * radius, 1, 0.0, 0.0, 0.0, 0.0);
        }
    }

    private static void afterDamage(LivingEntity victim, DamageSource source, float baseDamageTaken,
                                    float damageTaken, boolean blocked) {
        if (damageTaken <= 0.0F) return;
        ActiveChallengeState state = BrigadaCore.stateStore().state().activeChallenge;
        if (state == null || state.targetEntityId == null || !state.targetEntityId.equals(victim.getUUID())) return;
        ChallengeDefinition definition;
        try { definition = BrigadaCore.challenges().require(state.challengeId); }
        catch (RuntimeException ignored) { return; }
        if (definition.kind() != ChallengeKind.MINI_EVENT
                || definition.mechanic() != MiniEventMechanic.DEFEND_OBJECTIVE) return;
        float restored = switch (definition.difficulty()) {
            case EASY -> 0.15F;
            case NORMAL -> 0.35F;
            case HARD -> 0.55F;
        };
        if (victim.isAlive()) victim.heal(damageTaken * restored);
    }

    private static void tickBursts(MinecraftServer server) {
        BURSTS.removeIf(burst -> {
            if (tick < burst.fireAt()) return false;
            for (String name : burst.participants()) {
                ServerPlayer player = server.getPlayerList().getPlayerByName(name);
                if (player != null) burst(player);
            }
            return true;
        });
    }

    private static void burst(ServerPlayer player) {
        ServerLevel level = player.level();
        double x = player.getX(), y = player.getY() + 18.4, z = player.getZ();
        DustParticleOptions gold = new DustParticleOptions(0xFFD34E, 1.45F);
        DustParticleOptions cyan = new DustParticleOptions(0x42F3FF, 1.30F);
        ParticleOptimizer.emit(level, ParticleTypes.FIREWORK, x, y, z, 120, 4.8, 3.6, 4.8, 0.22);
        ParticleOptimizer.emit(level, gold, x, y, z, 72, 4.2, 3.0, 4.2, 0.11);
        ParticleOptimizer.emit(level, cyan, x, y, z, 72, 4.2, 3.0, 4.2, 0.11);
        ParticleOptimizer.emit(level, ParticleTypes.END_ROD, x, y, z, 36, 3.4, 2.5, 3.4, 0.08);
        play(level, x, y, z, SoundEvents.FIREWORK_ROCKET_LARGE_BLAST, 1.2F, 0.95F);
        play(level, x, y, z, SoundEvents.FIREWORK_ROCKET_TWINKLE, 1.0F, 1.12F);
    }

    private static void playCenter(ServerLevel level, ActiveChallengeState state,
                                   SoundEvent sound, float volume, float pitch) {
        play(level, (state.arenaMinX + state.arenaMaxX + 1.0) * 0.5, state.arenaY + 1.0,
                (state.arenaMinZ + state.arenaMaxZ + 1.0) * 0.5, sound, volume, pitch);
    }

    private static void play(ServerLevel level, double x, double y, double z,
                             SoundEvent sound, float volume, float pitch) {
        level.playSound(null, x, y, z, sound, SoundSource.PLAYERS, volume, pitch);
    }

    private record CompletionBurst(List<String> participants, long fireAt) {}
}
JAVA

cat > "$MIXIN" <<'JAVA'
package dev.brigada13.hotfix.mixin;

import dev.brigada13.core.BrigadaCore;
import dev.brigada13.core.challenge.ChallengeDefinition;
import dev.brigada13.core.challenge.ChallengeService;
import dev.brigada13.core.state.ActiveChallengeState;
import dev.brigada13.hotfix.RuntimeFixes;
import net.minecraft.core.BlockPos;
import net.minecraft.core.registries.Registries;
import net.minecraft.resources.Identifier;
import net.minecraft.resources.ResourceKey;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.tags.TagKey;
import net.minecraft.world.level.StructureManager;
import net.minecraft.world.level.levelgen.structure.BoundingBox;
import net.minecraft.world.level.levelgen.structure.Structure;
import net.minecraft.world.level.levelgen.structure.StructureStart;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Unique;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.ModifyArg;
import org.spongepowered.asm.mixin.injection.Redirect;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(ChallengeService.class)
public abstract class ChallengeServiceMixin {
    @Unique private static final int MAX_LOCATE_RADIUS = 768;
    @Unique private static final double RESOLVE_DISTANCE_SQ = 192.0 * 192.0;
    @Unique private long resolvedStartedAt = Long.MIN_VALUE;

    @ModifyArg(method = "locate",
            at = @At(value = "INVOKE",
                    target = "Lnet/minecraft/server/level/ServerLevel;findNearestMapStructure(Lnet/minecraft/tags/TagKey;Lnet/minecraft/core/BlockPos;IZ)Lnet/minecraft/core/BlockPos;"),
            index = 2, require = 0)
    private int capLocateRadius(int radius) {
        return Math.min(radius, MAX_LOCATE_RADIUS);
    }

    @Redirect(method = "locate",
            at = @At(value = "INVOKE",
                    target = "Lnet/minecraft/world/level/StructureManager;getStructureWithPieceAt(Lnet/minecraft/core/BlockPos;Lnet/minecraft/tags/TagKey;)Lnet/minecraft/world/level/levelgen/structure/StructureStart;"),
            require = 0)
    private StructureStart deferStructureLoad(StructureManager manager, BlockPos pos, TagKey<Structure> tag) {
        return StructureStart.INVALID_START;
    }

    @Inject(method = "tickEvent", at = @At("HEAD"), require = 0)
    private void resolveNearPlayers(MinecraftServer server, ChallengeDefinition definition,
                                    ActiveChallengeState state, CallbackInfo ci) {
        if (state.arenaLocked || state.arenaDimension == null || resolvedStartedAt == state.startedAtEpochMillis) return;
        ServerLevel level = server.getLevel(ResourceKey.create(Registries.DIMENSION, Identifier.parse(state.arenaDimension)));
        if (level == null) return;
        for (String participant : state.contribution.keySet()) {
            ServerPlayer player = server.getPlayerList().getPlayerByName(participant);
            if (player == null || player.level() != level) return;
            double dx = player.getX() - (state.arenaX + 0.5);
            double dz = player.getZ() - (state.arenaZ + 0.5);
            if (dx * dx + dz * dz > RESOLVE_DISTANCE_SQ) return;
        }
        TagKey<Structure> tag = TagKey.create(Registries.STRUCTURE, Identifier.parse(definition.structureTag()));
        StructureStart start = level.structureManager().getStructureWithPieceAt(
                new BlockPos(state.arenaX, state.arenaY, state.arenaZ), tag);
        if (start == StructureStart.INVALID_START) return;
        BoundingBox box = start.getBoundingBox().inflatedBy(3);
        state.arenaMinX = box.minX(); state.arenaMaxX = box.maxX();
        state.arenaMinZ = box.minZ(); state.arenaMaxZ = box.maxZ();
        resolvedStartedAt = state.startedAtEpochMillis;
        BrigadaCore.stateStore().save();
    }

    // The arena is logical now. Physical glass is what spiders were climbing and what created the
    // absurd sky-high planes in the screenshots. RuntimeFixes keeps mobs inside without blocks.
    @Redirect(method = "tickEvent",
            at = @At(value = "INVOKE",
                    target = "Ldev/brigada13/core/challenge/ChallengeService;ensurePhysicalBoundary(Lnet/minecraft/server/MinecraftServer;Lnet/minecraft/server/level/ServerLevel;Ldev/brigada13/core/state/ActiveChallengeState;)V"),
            require = 0)
    private void noPhysicalBoundary(MinecraftServer server, ServerLevel level, ActiveChallengeState state) {
        RuntimeFixes.clearPhysicalBoundary(level, state);
    }

    @Inject(method = "complete", at = @At("HEAD"), require = 0)
    private void completionEffects(MinecraftServer server, ChallengeDefinition definition,
                                   ActiveChallengeState state, CallbackInfo ci) {
        RuntimeFixes.onComplete(server, state);
    }
}
JAVA

cd "$HOT"
echo '=== compile hotfix v2 ==='
./gradlew clean build --no-daemon --stacktrace
JAR=$(find build/libs -maxdepth 1 -type f -name 'brigada-hotfix-*.jar' ! -name '*sources*' ! -name '*dev*' -print -quit)
test -n "$JAR" -a -s "$JAR"
sha256sum "$JAR"
jar tf "$JAR" | grep -E 'RuntimeFixes|ChallengeServiceMixin|brigada_hotfix.mixins.json'
echo BUILD_V2_OK
