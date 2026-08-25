package dev.brigada13.core.challenge;

import dev.brigada13.core.BrigadaCore;
import dev.brigada13.core.particle.ParticleOptimizer;
import dev.brigada13.core.state.ActiveChallengeState;
import net.fabricmc.fabric.api.entity.event.v1.ServerLivingEntityEvents;
import net.fabricmc.fabric.api.event.lifecycle.v1.ServerTickEvents;
import net.fabricmc.fabric.api.event.lifecycle.v1.ServerEntityEvents;
import net.fabricmc.fabric.api.event.player.PlayerBlockBreakEvents;
import net.minecraft.core.BlockPos;
import net.minecraft.core.particles.DustParticleOptions;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.core.particles.ParticleOptions;
import net.minecraft.core.registries.BuiltInRegistries;
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
import net.minecraft.world.entity.EntitySpawnReason;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.entity.Mob;
import net.minecraft.world.entity.projectile.Projectile;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.entity.monster.cubemob.MagmaCube;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.nio.file.Files;
import java.nio.file.Path;
import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.DataInputStream;
import java.io.DataOutputStream;

public final class ChallengeRuntimeFixes {
    private static final int COMPLETION_BURST_DELAY = 0;
    private static final double MOB_EDGE_MARGIN = 2.35;
    private static final double PLAYER_EDGE_MARGIN = 0.55;
    private static final Block GRAY_BOUNDARY = BuiltInRegistries.BLOCK.getValue(Identifier.parse("minecraft:gray_stained_glass"));
    private static final Block BROWN_BOUNDARY = BuiltInRegistries.BLOCK.getValue(Identifier.parse("minecraft:brown_stained_glass"));
    private static final Block LIME_BOUNDARY = BuiltInRegistries.BLOCK.getValue(Identifier.parse("minecraft:lime_stained_glass"));
    private static final Set<UUID> PREPARED_OBJECTIVES = new HashSet<>();
    private static final Map<UUID, Integer> OBJECTIVE_HEAL_STAGE = new HashMap<>();
    private static final Set<UUID> PREPARED_ELITES = new HashSet<>();
    private static final Set<UUID> PREPARED_COMBAT_MOBS = new HashSet<>();
    private static final List<CompletionBurst> BURSTS = new ArrayList<>();
    private static final List<WavePulse> WAVE_PULSES = new ArrayList<>();
    private static final Map<Long, Integer> BOUNDARY_ORIGINALS = new HashMap<>();
    private static final Path BOUNDARY_BACKUP = Path.of("brigada-boundary-backup.bin");
    private static long boundaryEvent = Long.MIN_VALUE;
    private static String boundaryDimension;

    private static long tick;
    private static long observedEvent = Long.MIN_VALUE;
    private static int observedWave = -1;
    private static int observedPhase = -1;
    private static long magmaLineageEvent = Long.MIN_VALUE;
    private static boolean magmaLineageSeen;
    private static long combatScaleEvent = Long.MIN_VALUE;
    private static long splitPressureEvent = Long.MIN_VALUE;
    private static int splitPressureElapsed = -1;

    private ChallengeRuntimeFixes() {}

    public static void register() {
        ServerLivingEntityEvents.ALLOW_DAMAGE.register(ChallengeRuntimeFixes::allowDamage);
        ServerLivingEntityEvents.AFTER_DAMAGE.register(ChallengeRuntimeFixes::afterDamage);
        ServerEntityEvents.ENTITY_LOAD.register(ChallengeRuntimeFixes::onEntityLoad);
        PlayerBlockBreakEvents.BEFORE.register((level, player, pos, blockState, blockEntity) ->
                !(level instanceof ServerLevel serverLevel) || !isFullBoundaryPosition(serverLevel, pos));
        ServerTickEvents.END_SERVER_TICK.register(ChallengeRuntimeFixes::tick);
        loadBoundaryBackup();
        dumpItemRegistry();
    }

    private static void dumpItemRegistry() {
        try {
            StringBuilder out = new StringBuilder();
            for (var item : BuiltInRegistries.ITEM) {
                Identifier key = BuiltInRegistries.ITEM.getKey(item);
                if (key == null) continue;
                int rawId = BuiltInRegistries.ITEM.getId(item);
                out.append(rawId).append('\t').append(key).append('\n');
            }
            Files.writeString(Path.of("brigada-item-registry.tsv"), out.toString());
        } catch (Exception e) {
            System.err.println("[brigada_hotfix] item registry dump failed: " + e);
        }
    }

    private static void onEntityLoad(Entity entity, ServerLevel level) {
        if (entity instanceof Projectile projectile && isForbiddenChallengeProjectile(entity)) {
            Entity owner = projectile.getOwner();
            if (owner instanceof ServerPlayer player && isChallengeParticipant(player)) {
                entity.discard();
                return;
            }
        }
        if (!(entity instanceof MagmaCube cube) || !cube.isAlive()) return;
        ActiveChallengeState state = activeEvent();
        if (state == null || eventLevel(level.getServer(), state) != level) return;
        if (magmaLineageEvent != state.startedAtEpochMillis || !magmaLineageSeen) return;

        double margin = 3.0;
        if (cube.getX() < state.arenaMinX - margin || cube.getX() > state.arenaMaxX + 1.0 + margin
                || cube.getZ() < state.arenaMinZ - margin || cube.getZ() > state.arenaMaxZ + 1.0 + margin
                || cube.getY() < state.arenaY - 20.0 || cube.getY() > state.arenaY + 28.0) return;

        UUID id = cube.getUUID();
        if (state.eventEntities.contains(id)
                || (state.targetEntityId != null && state.targetEntityId.equals(id))) return;

        // Magma cubes split after death. Their children belong to the same encounter: keep them alive,
        // keep them highlighted, and keep the wave open until the player actually deals with them.
        state.eventEntities.add(id);
        cube.setPersistenceRequired();
        cube.setGlowingTag(true);
        cube.setRemainingFireTicks(0);
        BrigadaCore.stateStore().save();
    }

    private static void loadBoundaryBackup() {
        BOUNDARY_ORIGINALS.clear();
        if (!Files.exists(BOUNDARY_BACKUP)) return;
        try (DataInputStream in = new DataInputStream(new BufferedInputStream(Files.newInputStream(BOUNDARY_BACKUP)))) {
            String magic = in.readUTF();
            if (!"BRIGADA_BOUNDARY_V1".equals(magic)) return;
            boundaryEvent = in.readLong();
            boundaryDimension = in.readUTF();
            int count = in.readInt();
            for (int i = 0; i < count; i++) BOUNDARY_ORIGINALS.put(in.readLong(), in.readInt());
            System.out.println("[brigada_hotfix] loaded boundary backup: " + count + " blocks");
        } catch (Exception e) {
            System.err.println("[brigada_hotfix] boundary backup load failed: " + e);
            BOUNDARY_ORIGINALS.clear();
            boundaryEvent = Long.MIN_VALUE;
            boundaryDimension = null;
        }
    }

    private static void saveBoundaryBackup() {
        try (DataOutputStream out = new DataOutputStream(new BufferedOutputStream(Files.newOutputStream(BOUNDARY_BACKUP)))) {
            out.writeUTF("BRIGADA_BOUNDARY_V1");
            out.writeLong(boundaryEvent);
            out.writeUTF(boundaryDimension == null ? "minecraft:overworld" : boundaryDimension);
            out.writeInt(BOUNDARY_ORIGINALS.size());
            for (Map.Entry<Long, Integer> entry : BOUNDARY_ORIGINALS.entrySet()) {
                out.writeLong(entry.getKey());
                out.writeInt(entry.getValue());
            }
        } catch (Exception e) {
            System.err.println("[brigada_hotfix] boundary backup save failed: " + e);
        }
    }

    private static boolean isFullBoundaryPosition(ServerLevel level, BlockPos pos) {
        ActiveChallengeState state = activeEvent();
        if (state == null || eventLevel(level.getServer(), state) != level) return false;
        if (pos.getY() < level.getMinY() || pos.getY() >= level.getMaxY()) return false;
        boolean xEdge = pos.getX() == state.arenaMinX || pos.getX() == state.arenaMaxX;
        boolean zEdge = pos.getZ() == state.arenaMinZ || pos.getZ() == state.arenaMaxZ;
        boolean inX = pos.getX() >= state.arenaMinX && pos.getX() <= state.arenaMaxX;
        boolean inZ = pos.getZ() >= state.arenaMinZ && pos.getZ() <= state.arenaMaxZ;
        return (xEdge && inZ) || (zEdge && inX);
    }

    private static boolean allowDamage(LivingEntity entity, DamageSource source, float amount) {
        if (source.getEntity() instanceof ServerPlayer attacker
                && isChallengeParticipant(attacker)
                && isForbiddenChallengeItem(attacker.getMainHandItem())) return false;
        ActiveChallengeState state = BrigadaCore.stateStore().state().activeChallenge;
        if (!isTrackedEventEntity(state, entity.getUUID())) return true;
        if (source.is(DamageTypes.FALL)) return false;
        if (source.is(DamageTypes.ON_FIRE) && entity.level() instanceof ServerLevel level
                && level.canSeeSky(entity.blockPosition())) return false;
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
                    SoundEvents.BEACON_ACTIVATE, 1.45F, 1.38F);
            play(player.level(), player.getX(), player.getY(), player.getZ(),
                    SoundEvents.PLAYER_LEVELUP, 1.15F, 0.96F);
        }
        BURSTS.add(new CompletionBurst(List.copyOf(state.contribution.keySet()), tick + COMPLETION_BURST_DELAY));
    }

    private static void tick(MinecraftServer server) {
        tick++;
        enforceChallengeRestrictions(server);
        ActiveChallengeState state = activeEvent();
        if (state != null) {
            if (magmaLineageEvent != state.startedAtEpochMillis) {
                magmaLineageEvent = state.startedAtEpochMillis;
                magmaLineageSeen = false;
            }
            ChallengeDefinition definition = BrigadaCore.challenges().require(state.challengeId);
            ServerLevel level = eventLevel(server, state);
            if (level != null) {
                ensureFullHeightBoundary(level, state);
                confineParticipants(server, level, state);
                scaleEventMobs(level, definition, state);
                stabiliseEventMobs(level, state);
                tickContinuousPressure(level, definition, state);
                fixDefense(level, definition, state);
                fixElite(level, definition, state);
                soundProgress(level, definition, state);
                renderMeaningfulParticles(level, definition, state);
            }
        } else {
            observedEvent = Long.MIN_VALUE;
            observedWave = -1;
            observedPhase = -1;
            magmaLineageEvent = Long.MIN_VALUE;
            magmaLineageSeen = false;
            restoreOrphanedBoundary(server);
        }
        tickWavePulses();
        tickBursts(server);
    }

    private static void enforceChallengeRestrictions(MinecraftServer server) {
        ActiveChallengeState state = BrigadaCore.stateStore().state().activeChallenge;
        if (state == null || state.contribution == null || state.contribution.isEmpty()) return;
        for (String name : state.contribution.keySet()) {
            ServerPlayer player = server.getPlayerList().getPlayerByName(name);
            if (player == null) continue;
            if (player.isUsingItem() && isForbiddenChallengeItem(player.getUseItem())) {
                player.stopUsingItem();
            }
            if (player.isFallFlying()) player.stopFallFlying();
        }
    }

    private static boolean isChallengeParticipant(ServerPlayer player) {
        ActiveChallengeState state = BrigadaCore.stateStore().state().activeChallenge;
        return state != null && state.contribution != null
                && state.contribution.containsKey(player.getName().getString());
    }

    private static boolean isForbiddenChallengeItem(ItemStack stack) {
        if (stack == null || stack.isEmpty()) return false;
        Identifier key = BuiltInRegistries.ITEM.getKey(stack.getItem());
        if (key == null) return false;
        return switch (key.toString()) {
            case "minecraft:golden_apple", "minecraft:enchanted_golden_apple",
                    "minecraft:potion", "minecraft:splash_potion", "minecraft:lingering_potion",
                    "minecraft:ender_pearl", "minecraft:chorus_fruit",
                    "minecraft:wind_charge", "minecraft:firework_rocket",
                    "minecraft:elytra", "minecraft:mace", "minecraft:trident" -> true;
            default -> false;
        };
    }

    private static boolean isForbiddenChallengeProjectile(Entity entity) {
        Identifier key = BuiltInRegistries.ENTITY_TYPE.getKey(entity.getType());
        if (key == null) return false;
        return switch (key.toString()) {
            case "minecraft:ender_pearl", "minecraft:wind_charge",
                    "minecraft:potion", "minecraft:firework_rocket" -> true;
            default -> false;
        };
    }

    private static boolean continuousPressureMechanic(MiniEventMechanic mechanic) {
        return switch (mechanic) {
            case HOLD_ZONE, SPLIT_OBJECTIVES, EXTRACTION, NO_DEATH_GAUNTLET -> true;
            case WAVES, HUNT_TARGETS, DEFEND_OBJECTIVE, ELITE_BOSS, MULTI_PHASE_ASSAULT -> false;
        };
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

    public static void ensureFullHeightBoundary(ServerLevel level, ActiveChallengeState state) {
        if (boundaryEvent != Long.MIN_VALUE && boundaryEvent != state.startedAtEpochMillis
                && !BOUNDARY_ORIGINALS.isEmpty()) {
            restoreOrphanedBoundary(level.getServer());
        }
        if (boundaryEvent == state.startedAtEpochMillis && !BOUNDARY_ORIGINALS.isEmpty()) return;

        boundaryEvent = state.startedAtEpochMillis;
        boundaryDimension = state.arenaDimension;
        BOUNDARY_ORIGINALS.clear();
        BlockState glass = GRAY_BOUNDARY.defaultBlockState();
        int minY = level.getMinY();
        int maxY = level.getMaxY() - 1;

        for (int x = state.arenaMinX; x <= state.arenaMaxX; x++) {
            buildFullBoundaryColumn(level, glass, x, state.arenaMinZ, minY, maxY);
            if (state.arenaMaxZ != state.arenaMinZ)
                buildFullBoundaryColumn(level, glass, x, state.arenaMaxZ, minY, maxY);
        }
        for (int z = state.arenaMinZ + 1; z < state.arenaMaxZ; z++) {
            buildFullBoundaryColumn(level, glass, state.arenaMinX, z, minY, maxY);
            if (state.arenaMaxX != state.arenaMinX)
                buildFullBoundaryColumn(level, glass, state.arenaMaxX, z, minY, maxY);
        }

        // Do not serialize tens of thousands of positions into ActiveChallengeState. The hotfix owns
        // the wall and blocks breaking by perimeter coordinates; the binary backup owns restoration.
        if (state.boundaryBlocks != null) state.boundaryBlocks.clear();
        state.boundaryBottomY = minY;
        state.boundaryTopY = maxY;
        saveBoundaryBackup();
        BrigadaCore.stateStore().save();
        System.out.println("[brigada_hotfix] full-height boundary built: " + BOUNDARY_ORIGINALS.size()
                + " blocks, y=" + minY + ".." + maxY);
    }

    private static void buildFullBoundaryColumn(ServerLevel level, BlockState glass,
                                                int x, int z, int minY, int maxY) {
        for (int y = minY; y <= maxY; y++) {
            BlockPos pos = new BlockPos(x, y, z);
            long packed = pos.asLong();
            BlockState current = level.getBlockState(pos);
            BOUNDARY_ORIGINALS.putIfAbsent(packed, Block.getId(current));
            if (!current.equals(glass)) level.setBlock(pos, glass, 2);
        }
    }

    public static void restoreBoundary(MinecraftServer server, ActiveChallengeState state) {
        if (state == null) return;
        ServerLevel level = eventLevel(server, state);
        if (level == null) return;
        if (boundaryEvent != state.startedAtEpochMillis || BOUNDARY_ORIGINALS.isEmpty()) {
            // Legacy wall from an older build: only its own tracked blocks may be cleared.
            clearLegacyPhysicalBoundary(level, state);
            return;
        }
        restoreBoundaryMap(level);
        if (state.boundaryBlocks != null) state.boundaryBlocks.clear();
        state.boundaryBottomY = 0;
        state.boundaryTopY = 0;
        BrigadaCore.stateStore().save();
    }

    public static void restoreActiveBoundary(MinecraftServer server) {
        restoreBoundary(server, BrigadaCore.stateStore().state().activeChallenge);
    }

    private static void restoreOrphanedBoundary(MinecraftServer server) {
        if (BOUNDARY_ORIGINALS.isEmpty() || boundaryDimension == null) return;
        ServerLevel level = server.getLevel(ResourceKey.create(
                Registries.DIMENSION, Identifier.parse(boundaryDimension)));
        if (level != null) restoreBoundaryMap(level);
    }

    private static void restoreBoundaryMap(ServerLevel level) {
        int restored = 0;
        for (Map.Entry<Long, Integer> entry : new ArrayList<>(BOUNDARY_ORIGINALS.entrySet())) {
            BlockPos pos = BlockPos.of(entry.getKey());
            BlockState original = Block.stateById(entry.getValue());
            if (original == null) original = Blocks.AIR.defaultBlockState();
            level.setBlock(pos, original, 2);
            restored++;
        }
        BOUNDARY_ORIGINALS.clear();
        boundaryEvent = Long.MIN_VALUE;
        boundaryDimension = null;
        try { Files.deleteIfExists(BOUNDARY_BACKUP); }
        catch (Exception e) { System.err.println("[brigada_hotfix] boundary backup delete failed: " + e); }
        System.out.println("[brigada_hotfix] boundary restored: " + restored + " blocks");
    }

    public static void clearPhysicalBoundary(ServerLevel level, ActiveChallengeState state) {
        clearLegacyPhysicalBoundary(level, state);
    }

    private static void clearLegacyPhysicalBoundary(ServerLevel level, ActiveChallengeState state) {
        if (state == null || state.boundaryBlocks == null || state.boundaryBlocks.isEmpty()) return;
        for (long packed : new ArrayList<>(state.boundaryBlocks)) {
            BlockPos pos = BlockPos.of(packed);
            var block = level.getBlockState(pos).getBlock();
            if (block == GRAY_BOUNDARY || block == BROWN_BOUNDARY || block == LIME_BOUNDARY)
                level.setBlock(pos, Blocks.AIR.defaultBlockState(), 2);
        }
        state.boundaryBlocks.clear();
        state.boundaryBottomY = 0;
        state.boundaryTopY = 0;
    }

    private static void confineParticipants(MinecraftServer server, ServerLevel level, ActiveChallengeState state) {
        double minX = state.arenaMinX + PLAYER_EDGE_MARGIN;
        double maxX = state.arenaMaxX + 1.0 - PLAYER_EDGE_MARGIN;
        double minZ = state.arenaMinZ + PLAYER_EDGE_MARGIN;
        double maxZ = state.arenaMaxZ + 1.0 - PLAYER_EDGE_MARGIN;
        if (minX > maxX) minX = maxX = (state.arenaMinX + state.arenaMaxX + 1.0) * 0.5;
        if (minZ > maxZ) minZ = maxZ = (state.arenaMinZ + state.arenaMaxZ + 1.0) * 0.5;

        for (String participant : state.contribution.keySet()) {
            ServerPlayer player = server.getPlayerList().getPlayerByName(participant);
            if (player == null || player.level() != level) continue;

            double oldX = player.getX();
            double oldZ = player.getZ();
            double x = Math.max(minX, Math.min(maxX, oldX));
            double z = Math.max(minZ, Math.min(maxZ, oldZ));
            boolean blockedX = Math.abs(x - oldX) > 1.0E-4;
            boolean blockedZ = Math.abs(z - oldZ) > 1.0E-4;
            if (!blockedX && !blockedZ) continue;

            var motion = player.getDeltaMovement();
            double vx = motion.x;
            double vz = motion.z;
            if (blockedX && ((oldX < minX && vx < 0.0) || (oldX > maxX && vx > 0.0))) vx = 0.0;
            if (blockedZ && ((oldZ < minZ && vz < 0.0) || (oldZ > maxZ && vz > 0.0))) vz = 0.0;

            // Hard invisible wall: teleportTo sends an immediate correction to the owning client,
            // so crossing never becomes an accepted player position; outward momentum is cancelled too.
            player.teleportTo(x, player.getY(), z);
            player.setDeltaMovement(vx, motion.y, vz);
        }
    }

    private static void scaleEventMobs(ServerLevel level, ChallengeDefinition definition,
                                       ActiveChallengeState state) {
        if (combatScaleEvent != state.startedAtEpochMillis) {
            combatScaleEvent = state.startedAtEpochMillis;
            PREPARED_COMBAT_MOBS.clear();
        }
        double healthMultiplier = switch (definition.difficulty()) {
            case EASY -> 1.00;
            case NORMAL -> 1.25;
            case HARD -> 1.50;
        };
        double damageMultiplier = switch (definition.difficulty()) {
            case EASY -> 1.00;
            case NORMAL -> 1.65;
            case HARD -> 2.50;
        };
        double speedMultiplier = switch (definition.difficulty()) {
            case EASY -> 1.00;
            case NORMAL -> 1.06;
            case HARD -> 1.10;
        };

        for (UUID id : new ArrayList<>(state.eventEntities)) {
            Entity raw = level.getEntity(id);
            if (!(raw instanceof Mob mob) || !mob.isAlive() || !PREPARED_COMBAT_MOBS.add(id)) continue;

            float oldMax = Math.max(1.0F, mob.getMaxHealth());
            float healthRatio = Math.max(0.05F, Math.min(1.0F, mob.getHealth() / oldMax));
            var maxHealth = mob.getAttribute(Attributes.MAX_HEALTH);
            if (maxHealth != null && healthMultiplier != 1.0) {
                maxHealth.setBaseValue(maxHealth.getBaseValue() * healthMultiplier);
                mob.setHealth(Math.max(1.0F, mob.getMaxHealth() * healthRatio));
            }
            var attack = mob.getAttribute(Attributes.ATTACK_DAMAGE);
            if (attack != null && damageMultiplier != 1.0) {
                double baseAttack = attack.getBaseValue();
                // Hard should hurt, but naturally brutal mobs must not become accidental one-shot machines.
                double appliedMultiplier = definition.difficulty() == ChallengeDifficulty.HARD && baseAttack >= 16.0
                        ? 1.75 : damageMultiplier;
                attack.setBaseValue(baseAttack * appliedMultiplier);
            }
            var speed = mob.getAttribute(Attributes.MOVEMENT_SPEED);
            if (speed != null && speedMultiplier != 1.0)
                speed.setBaseValue(speed.getBaseValue() * speedMultiplier);
            mob.setPersistenceRequired();
        }
    }

    public static int splitSoloPointTicks(ChallengeDefinition definition) {
        return switch (definition.difficulty()) {
            case EASY -> 240;   // 12 seconds per point
            case NORMAL -> 480; // 24 seconds per point
            case HARD -> 720;   // 36 seconds per point
        };
    }

    private static int splitDuoTicks(ChallengeDefinition definition) {
        return switch (definition.difficulty()) {
            case EASY -> 360;   // 18 seconds together
            case NORMAL -> 600; // 30 seconds together
            case HARD -> 840;   // 42 seconds together
        };
    }

    public static void prepareSplitBalance(ChallengeDefinition definition, ActiveChallengeState state) {
        if (definition.mechanic() != MiniEventMechanic.SPLIT_OBJECTIVES) return;
        int desired = state.singleMode ? splitSoloPointTicks(definition) * 2 : splitDuoTicks(definition);
        if (state.stageTarget == desired && state.eventTarget == desired) return;

        if (state.singleMode) {
            int oldPoint = Math.max(1, state.stageTarget > 1 ? state.stageTarget / 2 : 100);
            double ratio = Math.max(0.0, Math.min(1.0, state.eventHoldTicks / (double) oldPoint));
            int point = splitSoloPointTicks(definition);
            state.eventHoldTicks = (int) Math.round(ratio * point);
            state.stage = Math.min(desired, state.eventPhase * point + state.eventHoldTicks);
        } else {
            int oldTarget = Math.max(1, state.stageTarget);
            double ratio = Math.max(0.0, Math.min(1.0, state.eventHoldTicks / (double) oldTarget));
            state.eventHoldTicks = (int) Math.round(ratio * desired);
            state.stage = Math.min(desired, state.eventHoldTicks);
        }
        state.eventTarget = desired;
        state.stageTarget = desired;
        BrigadaCore.stateStore().save();
    }

    private static void tickContinuousPressure(ServerLevel level, ChallengeDefinition definition,
                                          ActiveChallengeState state) {
        if (!continuousPressureMechanic(definition.mechanic())) return;
        if (splitPressureEvent != state.startedAtEpochMillis) {
            splitPressureEvent = state.startedAtEpochMillis;
            splitPressureElapsed = -1;
        }
        if (state.eventElapsedTicks < 40) return;

        int interval = switch (definition.difficulty()) {
            case EASY -> 200;
            case NORMAL -> 120;
            case HARD -> 80;
        };
        if (splitPressureElapsed >= 0 && state.eventElapsedTicks - splitPressureElapsed < interval) return;

        int cap = switch (definition.difficulty()) {
            case EASY -> 8;
            case NORMAL -> 14;
            case HARD -> 20;
        };
        int alive = 0;
        for (UUID id : state.eventEntities) {
            Entity entity = level.getEntity(id);
            if (entity instanceof Mob mob && mob.isAlive()) alive++;
        }
        if (alive >= cap) return;

        int amount = switch (definition.difficulty()) {
            case EASY -> 2;
            case NORMAL -> 4;
            case HARD -> 6;
        } + (state.singleMode ? 0 : 1);
        amount = Math.min(amount, cap - alive);
        spawnPressureGroup(level, definition, state, amount);
        splitPressureElapsed = state.eventElapsedTicks;
        BrigadaCore.stateStore().save();
    }

    private static void spawnPressureGroup(ServerLevel level, ChallengeDefinition definition,
                                           ActiveChallengeState state, int amount) {
        String themeId = eventThemeId(definition);
        var theme = BrigadaCore.challenges().requireTheme(themeId);
        List<String> pool;
        if ("village".equals(themeId)) {
            pool = switch (definition.difficulty()) {
                case EASY -> List.of("minecraft:zombie", "minecraft:pillager");
                case NORMAL -> List.of("minecraft:pillager", "minecraft:vindicator", "minecraft:pillager");
                case HARD -> List.of("minecraft:pillager", "minecraft:vindicator", "minecraft:witch");
            };
        } else {
            pool = theme.primaryMobs();
        }
        for (int i = 0; i < amount; i++) {
            String id = pool.get(Math.floorMod(state.eventElapsedTicks / 20 + i, pool.size()));
            spawnPressureEntity(level, state, id);
        }
    }

    private static void reinforceHardVillageRaid(ServerLevel level, ChallengeDefinition definition,
                                                 ActiveChallengeState state) {
        if (definition.difficulty() != ChallengeDifficulty.HARD
                || definition.mechanic() != MiniEventMechanic.WAVES
                || !"village".equals(eventThemeId(definition))) return;
        int amount = state.singleMode ? 2 : 3;
        for (int i = 0; i < amount; i++) {
            String id;
            if (state.eventWave >= 5 && i == 0) id = "minecraft:ravager";
            else if (state.eventWave % 3 == 0 && i == 0) id = "minecraft:witch";
            else id = (i & 1) == 0 ? "minecraft:vindicator" : "minecraft:pillager";
            spawnPressureEntity(level, state, id);
        }
        BrigadaCore.stateStore().save();
    }

    private static String eventThemeId(ChallengeDefinition definition) {
        String[] parts = definition.id().split("/");
        return parts.length > 2 ? parts[2] : "outpost";
    }

    private static void spawnPressureEntity(ServerLevel level, ActiveChallengeState state, String entityId) {
        Identifier id = Identifier.parse(entityId);
        if (!BuiltInRegistries.ENTITY_TYPE.containsKey(id)) return;
        int minX = state.arenaMinX + 3;
        int maxX = state.arenaMaxX - 3;
        int minZ = state.arenaMinZ + 3;
        int maxZ = state.arenaMaxZ - 3;
        if (minX > maxX) minX = maxX = state.arenaX;
        if (minZ > maxZ) minZ = maxZ = state.arenaZ;

        for (int attempt = 0; attempt < 10; attempt++) {
            int x = minX + level.getRandom().nextInt(Math.max(1, maxX - minX + 1));
            int z = minZ + level.getRandom().nextInt(Math.max(1, maxZ - minZ + 1));
            BlockPos feet = findSafeFeet(level, x, z, state.arenaY);
            if (feet == null) continue;
            Entity spawned = BuiltInRegistries.ENTITY_TYPE.getValue(id)
                    .spawn(level, feet, EntitySpawnReason.EVENT);
            if (!(spawned instanceof Mob mob)) {
                if (spawned != null) spawned.discard();
                continue;
            }
            mob.setPersistenceRequired();
            mob.setGlowingTag(true);
            state.eventEntities.add(mob.getUUID());
            return;
        }
    }

    private static void stabiliseEventMobs(ServerLevel level, ActiveChallengeState state) {
        Set<UUID> ids = new HashSet<>(state.eventEntities);
        if (state.targetEntityId != null) ids.add(state.targetEntityId);
        for (UUID id : ids) {
            Entity raw = level.getEntity(id);
            if (!(raw instanceof Mob mob) || !mob.isAlive()) continue;

            mob.setPersistenceRequired();
            if (mob instanceof MagmaCube) {
                magmaLineageEvent = state.startedAtEpochMillis;
                magmaLineageSeen = true;
            }

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
            if (level.canSeeSky(mob.blockPosition()) && mob.isOnFire()) {
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
            scheduleWavePulse(level, state);
            reinforceHardVillageRaid(level, definition, state);
        }
    }

    private static void renderMeaningfulParticles(ServerLevel level, ChallengeDefinition definition,
                                                   ActiveChallengeState state) {
        if (tick % 4 != 0) return;
        // The arena border is a real full-height glass wall; do not duplicate it with airborne/ground particles.

        if (state.targetEntityId == null) return;
        Entity raw = level.getEntity(state.targetEntityId);
        if (!(raw instanceof LivingEntity target) || !target.isAlive()) return;
        if (definition.mechanic() == MiniEventMechanic.DEFEND_OBJECTIVE) {
            groundRing(level, new DustParticleOptions(0xFFD23F, 1.30F), new DustParticleOptions(0xFFFFFF, 1.05F),
                    target.getX(), target.getZ(), target.getY(), 1.75, 36);
        } else if (definition.mechanic() == MiniEventMechanic.ELITE_BOSS
                || (definition.mechanic() == MiniEventMechanic.MULTI_PHASE_ASSAULT && state.eventPhase >= 2)) {
            groundRing(level, new DustParticleOptions(0xFF3158, 1.35F), new DustParticleOptions(0xFFF0F5, 1.05F),
                    target.getX(), target.getZ(), target.getY(), 1.45, 32);
            ParticleOptimizer.emit(level, ParticleTypes.ENCHANTED_HIT,
                    target.getX(), target.getY() + target.getBbHeight() * 0.55, target.getZ(),
                    16, 0.7, Math.max(0.55, target.getBbHeight() * 0.48), 0.7, 0.02);
        }
    }

    /** Replaces ChallengeService's 12-point fixed-Y circles with dense terrain-following objective zones. */
    public static void renderGroundZone(ServerLevel level, int centerX, int anchorY, int centerZ,
                                        int radius, ParticleOptions original) {
        int primaryRgb;
        if (original == ParticleTypes.ENCHANTED_HIT) primaryRgb = 0xFF42D6;
        else if (original == ParticleTypes.END_ROD) primaryRgb = 0x34E8FF;
        else primaryRgb = 0x3CFFD0;

        DustParticleOptions primary = new DustParticleOptions(primaryRgb, 1.35F);
        DustParticleOptions white = new DustParticleOptions(0xFFFFFF, 1.15F);
        double cx = centerX + 0.5;
        double cz = centerZ + 0.5;
        int points = Math.max(56, radius * 12);

        groundRing(level, primary, white, cx, cz, anchorY, radius, points);
        groundRing(level, white, primary, cx, cz, anchorY, Math.max(0.75, radius - 0.55), points);

        // Sparse interior spokes make the playable area obvious instead of looking like random sparks.
        for (int spoke = 0; spoke < 12; spoke++) {
            double a = Math.PI * 2.0 * spoke / 12.0;
            for (double r = 1.0; r < radius - 0.25; r += 1.35) {
                double x = cx + Math.cos(a) * r;
                double z = cz + Math.sin(a) * r;
                groundDot(level, primary, x, z, anchorY);
            }
        }
        for (int i = 0; i < 12; i++) {
            double a = Math.PI * 2.0 * i / 12.0;
            groundDot(level, white, cx + Math.cos(a) * 0.7, cz + Math.sin(a) * 0.7, anchorY);
        }
    }

    private static void groundRing(ServerLevel level, DustParticleOptions outer, DustParticleOptions accent,
                                   double cx, double cz, double anchorY, double radius, int points) {
        for (int i = 0; i < points; i++) {
            double a = Math.PI * 2.0 * i / points;
            double x = cx + Math.cos(a) * radius;
            double z = cz + Math.sin(a) * radius;
            groundDot(level, (i & 3) == 0 ? accent : outer, x, z, (int) Math.round(anchorY));
        }
    }

    private static void boundaryDot(ServerLevel level, DustParticleOptions particle,
                                    double x, double z, int anchorY) {
        groundDot(level, particle, x, z, anchorY);
    }

    private static void groundDot(ServerLevel level, DustParticleOptions particle,
                                  double x, double z, int anchorY) {
        double y = nearestSurfaceY(level, (int) Math.floor(x), (int) Math.floor(z), anchorY);
        ParticleOptimizer.emit(level, particle, x, y, z, 1, 0.0, 0.0, 0.0, 0.0);
    }

    private static void shortMarker(ServerLevel level, DustParticleOptions particle,
                                    double x, double z, int anchorY) {
        double base = nearestSurfaceY(level, (int) Math.floor(x), (int) Math.floor(z), anchorY);
        for (int i = 0; i < 4; i++) {
            ParticleOptimizer.emit(level, particle, x, base + i * 0.42, z,
                    1, 0.0, 0.0, 0.0, 0.0);
        }
    }

    private static double nearestSurfaceY(ServerLevel level, int x, int z, int anchorY) {
        int center = Math.max(level.getMinY() + 1, Math.min(level.getMaxY() - 2, anchorY));
        for (int distance = 0; distance <= 14; distance++) {
            int up = center + distance;
            if (up < level.getMaxY() - 1 && isStandableSurface(level, x, up, z)) return up + 0.035;
            if (distance != 0) {
                int down = center - distance;
                if (down > level.getMinY() && isStandableSurface(level, x, down, z)) return down + 0.035;
            }
        }
        return anchorY + 0.035;
    }

    private static boolean isStandableSurface(ServerLevel level, int x, int feetY, int z) {
        BlockPos feet = new BlockPos(x, feetY, z);
        return level.getBlockState(feet).isAir() && !level.getBlockState(feet.below()).isAir();
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
            long age = tick - burst.fireAt();
            for (String name : burst.participants()) {
                ServerPlayer player = server.getPlayerList().getPlayerByName(name);
                if (player != null) enderVictoryFrame(player, age);
            }
            return age >= 64;
        });
    }

    private static void enderVictoryFrame(ServerPlayer player, long age) {
        ServerLevel level = player.level();
        double px = player.getX();
        double py = player.getY();
        double pz = player.getZ();
        DustParticleOptions purple = new DustParticleOptions(0xA94DFF, 1.35F);
        DustParticleOptions pale = new DustParticleOptions(0xF4E8FF, 1.05F);

        if (age < 44) {
            double collapse = 1.0 - age / 56.0;
            double radius = 0.75 + 2.35 * collapse;
            for (int arm = 0; arm < 5; arm++) {
                double angle = age * 0.42 + arm * Math.PI * 2.0 / 5.0;
                double x = px + Math.cos(angle) * radius;
                double z = pz + Math.sin(angle) * radius;
                double y = py + 0.25 + ((age * 0.14 + arm * 0.63) % 3.25);
                ParticleOptimizer.emit(level, ParticleTypes.PORTAL, x, y, z,
                        5, 0.16, 0.18, 0.16, 0.08);
                ParticleOptimizer.emit(level, (arm & 1) == 0 ? purple : pale, x, y, z,
                        2, 0.08, 0.08, 0.08, 0.0);
            }
            ParticleOptimizer.emit(level, ParticleTypes.REVERSE_PORTAL,
                    px, py + 1.1, pz, 10, 0.55, 1.05, 0.55, 0.05);
        }

        if (age == 44) {
            ParticleOptimizer.emit(level, ParticleTypes.FIREWORK,
                    px, py + 2.2, pz, 180, 3.8, 2.7, 3.8, 0.24);
            play(level, px, py + 1.0, pz, SoundEvents.FIREWORK_ROCKET_LARGE_BLAST, 4.2F, 0.96F);
            play(level, px, py + 1.0, pz, SoundEvents.FIREWORK_ROCKET_TWINKLE, 3.4F, 1.04F);
            ParticleOptimizer.emit(level, ParticleTypes.PORTAL,
                    px, py + 1.6, pz, 180, 3.5, 2.4, 3.5, 0.28);
            ParticleOptimizer.emit(level, ParticleTypes.REVERSE_PORTAL,
                    px, py + 1.6, pz, 100, 2.6, 2.0, 2.6, 0.18);
            ParticleOptimizer.emit(level, purple,
                    px, py + 1.6, pz, 90, 2.8, 2.2, 2.8, 0.07);
            ParticleOptimizer.emit(level, ParticleTypes.END_ROD,
                    px, py + 1.6, pz, 32, 2.0, 1.8, 2.0, 0.08);
        }

        if (age > 44 && age < 64 && (age & 1) == 0) {
            ParticleOptimizer.emit(level, ParticleTypes.PORTAL,
                    px, py + 0.8 + (age - 44) * 0.12, pz,
                    18, 1.1, 0.55, 1.1, 0.06);
        }
    }

    private static void scheduleWavePulse(ServerLevel level, ActiveChallengeState state) {
        double cx = (state.arenaMinX + state.arenaMaxX + 1.0) * 0.5;
        double cz = (state.arenaMinZ + state.arenaMaxZ + 1.0) * 0.5;
        double halfX = Math.max(2.5, (state.arenaMaxX - state.arenaMinX + 1.0) * 0.46);
        double halfZ = Math.max(2.5, (state.arenaMaxZ - state.arenaMinZ + 1.0) * 0.46);
        WAVE_PULSES.add(new WavePulse(level, cx, cz, state.arenaY, Math.min(halfX, halfZ), tick));

        for (UUID id : state.eventEntities) {
            Entity raw = level.getEntity(id);
            if (!(raw instanceof LivingEntity mob) || !mob.isAlive()) continue;
            ParticleOptimizer.emit(level, ParticleTypes.REVERSE_PORTAL,
                    mob.getX(), mob.getY() + mob.getBbHeight() * 0.5, mob.getZ(),
                    28, 0.5, Math.max(0.6, mob.getBbHeight() * 0.45), 0.5, 0.08);
        }
    }

    private static void tickWavePulses() {
        WAVE_PULSES.removeIf(pulse -> {
            long age = tick - pulse.startedAt();
            if (age < 0) return false;
            if (age > 18) return true;
            double radius = pulse.maxRadius() * (age + 1.0) / 19.0;
            DustParticleOptions purple = new DustParticleOptions(0x9A42FF, 1.20F);
            DustParticleOptions white = new DustParticleOptions(0xF8F0FF, 1.00F);
            int points = 56;
            for (int i = 0; i < points; i++) {
                double a = Math.PI * 2.0 * i / points;
                double x = pulse.cx() + Math.cos(a) * radius;
                double z = pulse.cz() + Math.sin(a) * radius;
                double y = nearestSurfaceY(pulse.level(), (int)Math.floor(x), (int)Math.floor(z), pulse.anchorY());
                ParticleOptimizer.emit(pulse.level(), (i % 5 == 0) ? white : purple,
                        x, y + 0.05, z, 1, 0.0, 0.0, 0.0, 0.0);
                if ((i & 1) == 0) ParticleOptimizer.emit(pulse.level(), ParticleTypes.PORTAL,
                        x, y + 0.12, z, 1, 0.04, 0.08, 0.04, 0.02);
            }
            if (age == 0) ParticleOptimizer.emit(pulse.level(), ParticleTypes.REVERSE_PORTAL,
                    pulse.cx(), nearestSurfaceY(pulse.level(), (int)Math.floor(pulse.cx()), (int)Math.floor(pulse.cz()), pulse.anchorY()) + 0.7,
                    pulse.cz(), 72, 1.2, 0.8, 1.2, 0.08);
            return false;
        });
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
    private record WavePulse(ServerLevel level, double cx, double cz, int anchorY, double maxRadius, long startedAt) {}
}
