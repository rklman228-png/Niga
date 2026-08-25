package dev.brigada13.core.mixin;

import dev.brigada13.core.BrigadaCore;
import dev.brigada13.core.challenge.ChallengeDefinition;
import dev.brigada13.core.challenge.ChallengeService;
import dev.brigada13.core.state.ActiveChallengeState;
import dev.brigada13.core.challenge.ChallengeRuntimeFixes;
import net.minecraft.core.BlockPos;
import net.minecraft.core.particles.ParticleOptions;
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
import org.spongepowered.asm.mixin.Shadow;
import org.spongepowered.asm.mixin.Unique;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Constant;
import org.spongepowered.asm.mixin.injection.ModifyConstant;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.ModifyArg;
import org.spongepowered.asm.mixin.injection.Redirect;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

import java.util.Map;

@Mixin(ChallengeService.class)
public abstract class ChallengeServiceMixin {
    @Shadow private Map<String, Long> celebrations;
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

    // Full-height physical arena wall. RuntimeFixes snapshots and restores every replaced BlockState.
    @Redirect(method = "tickEvent",
            at = @At(value = "INVOKE",
                    target = "Ldev/brigada13/core/challenge/ChallengeService;ensurePhysicalBoundary(Lnet/minecraft/server/MinecraftServer;Lnet/minecraft/server/level/ServerLevel;Ldev/brigada13/core/state/ActiveChallengeState;)V"),
            require = 0)
    private void fullHeightBoundary(MinecraftServer server, ServerLevel level, ActiveChallengeState state) {
        ChallengeRuntimeFixes.ensureFullHeightBoundary(level, state);
    }

    @Redirect(method = {"tickHold", "tickSplit", "tickExtraction"},
            at = @At(value = "INVOKE",
                    target = "Ldev/brigada13/core/challenge/ChallengeService;renderZone(Lnet/minecraft/server/level/ServerLevel;IIIILnet/minecraft/core/particles/ParticleOptions;)V"),
            require = 0)
    private void renderGroundObjectiveZone(ServerLevel level, int x, int y, int z, int radius,
                                           ParticleOptions particle) {
        ChallengeRuntimeFixes.renderGroundZone(level, x, y, z, radius, particle);
    }

    @Inject(method = "tickSplit", at = @At("HEAD"), require = 0)
    private void prepareBalancedSplit(MinecraftServer server, ServerLevel level, ChallengeDefinition definition,
                                      ActiveChallengeState state, CallbackInfo ci) {
        ChallengeRuntimeFixes.prepareSplitBalance(definition, state);
    }

    @ModifyConstant(method = "tickSplit", constant = @Constant(intValue = 100), require = 0)
    private int extendSoloSplitPoint(int original) {
        ActiveChallengeState state = BrigadaCore.stateStore().state().activeChallenge;
        if (state == null) return original;
        try {
            ChallengeDefinition definition = BrigadaCore.challenges().require(state.challengeId);
            if (definition.mechanic() != dev.brigada13.core.challenge.MiniEventMechanic.SPLIT_OBJECTIVES)
                return original;
            return ChallengeRuntimeFixes.splitSoloPointTicks(definition);
        } catch (RuntimeException ignored) {
            return original;
        }
    }

    @Inject(method = "complete", at = @At("HEAD"), require = 0)
    private void completionEffects(MinecraftServer server, ChallengeDefinition definition,
                                   ActiveChallengeState state, CallbackInfo ci) {
        ChallengeRuntimeFixes.restoreBoundary(server, state);
        ChallengeRuntimeFixes.onComplete(server, state);
    }

    @Inject(method = "complete", at = @At("TAIL"), require = 0)
    private void replaceCoreVictoryParticles(MinecraftServer server, ChallengeDefinition definition,
                                             ActiveChallengeState state, CallbackInfo ci) {
        for (String name : state.contribution.keySet()) celebrations.remove(name);
    }

    @Inject(method = "cancel", at = @At("HEAD"), require = 0)
    private void restoreBoundaryOnCancel(MinecraftServer server, CallbackInfo ci) {
        ChallengeRuntimeFixes.restoreActiveBoundary(server);
    }
}
