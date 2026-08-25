set -euo pipefail

BASE=/opt/brigada-core-src
HOT=/opt/brigada-hotfix-src
SERVER=/opt/minecraft/server
CORE_JAR="$SERVER/mods/brigada-core-0.1.0.jar"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)

echo '=== prepare local hotfix project ==='
rm -rf "$HOT"
cp -a "$BASE" "$HOT"
rm -rf "$HOT/build" "$HOT/.gradle" "$HOT/src/main/java" "$HOT/src/main/resources"
mkdir -p "$HOT/src/main/java/dev/brigada13/hotfix/mixin" "$HOT/src/main/resources"

# Same Minecraft/Fabric/Loom toolchain as the real plugin, but compile against the jar that is
# ACTUALLY deployed. GitHub only transports this script; Gradle runs here on the VPS.
sed -i 's/^archives_base_name=.*/archives_base_name=brigada-hotfix/' "$HOT/gradle.properties"
cat >> "$HOT/build.gradle" <<'GRADLE'

dependencies {
    modCompileOnly files('/opt/minecraft/server/mods/brigada-core-0.1.0.jar')
}
GRADLE

cat > "$HOT/src/main/resources/fabric.mod.json" <<'JSON'
{
  "schemaVersion": 1,
  "id": "brigada_hotfix",
  "version": "1.0.0",
  "name": "Brigada Event Hotfix",
  "environment": "server",
  "entrypoints": {
    "main": ["dev.brigada13.hotfix.BrigadaHotfix"]
  },
  "mixins": ["brigada_hotfix.mixins.json"],
  "depends": {
    "fabricloader": ">=0.19.0",
    "minecraft": "*",
    "brigada_core": "*"
  }
}
JSON

cat > "$HOT/src/main/resources/brigada_hotfix.mixins.json" <<'JSON'
{
  "required": true,
  "package": "dev.brigada13.hotfix.mixin",
  "compatibilityLevel": "JAVA_25",
  "mixins": ["ChallengeServiceMixin"],
  "injectors": {"defaultRequire": 1}
}
JSON

cat > "$HOT/src/main/java/dev/brigada13/hotfix/BrigadaHotfix.java" <<'JAVA'
package dev.brigada13.hotfix;

import net.fabricmc.api.ModInitializer;

public final class BrigadaHotfix implements ModInitializer {
    @Override
    public void onInitialize() {
        RuntimeFixes.register();
    }
}
JAVA

cat > "$HOT/src/main/java/dev/brigada13/hotfix/RuntimeFixes.java" <<'JAVA'
package dev.brigada13.hotfix;

import dev.brigada13.core.BrigadaCore;
import dev.brigada13.core.challenge.ChallengeDefinition;
import dev.brigada13.core.challenge.ChallengeKind;
import dev.brigada13.core.challenge.MiniEventMechanic;
import dev.brigada13.core.particle.ParticleOptimizer;
import dev.brigada13.core.state.ActiveChallengeState;
import net.fabricmc.fabric.api.entity.event.v1.ServerLivingEntityEvents;
import net.fabricmc.fabric.api.event.lifecycle.v1.ServerTickEvents;
import net.minecraft.core.particles.DustParticleOptions;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.core.registries.Registries;
import net.minecraft.resources.Identifier;
import net.minecraft.resources.ResourceKey;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.damagesource.DamageSource;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.entity.Mob;
import net.minecraft.world.entity.ai.attributes.Attributes;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

public final class RuntimeFixes {
    private static final int COMPLETION_BURST_DELAY = 100;
    private static final Set<UUID> PREPARED_OBJECTIVES = new HashSet<>();
    private static final Map<UUID, Integer> OBJECTIVE_HEAL_STAGE = new HashMap<>();
    private static final Set<UUID> PREPARED_ELITES = new HashSet<>();
    private static final List<CompletionBurst> BURSTS = new ArrayList<>();
    private static long tick;

    private RuntimeFixes() {}

    public static void register() {
        ServerLivingEntityEvents.AFTER_DAMAGE.register(RuntimeFixes::afterDamage);
        ServerTickEvents.END_SERVER_TICK.register(RuntimeFixes::tick);
    }

    public static void scheduleCompletionBurst(Set<String> participants) {
        if (participants != null && !participants.isEmpty()) {
            BURSTS.add(new CompletionBurst(List.copyOf(participants), tick + COMPLETION_BURST_DELAY));
        }
    }

    private static void tick(MinecraftServer server) {
        tick++;
        ActiveChallengeState state = activeEvent();
        if (state != null) {
            ChallengeDefinition definition = BrigadaCore.challenges().require(state.challengeId);
            ServerLevel level = eventLevel(server, state);
            if (level != null) {
                fixDefense(level, definition, state);
                fixElite(level, definition, state);
                renderEvent(level, definition, state);
            }
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

    private static void renderEvent(ServerLevel level, ChallengeDefinition definition, ActiveChallengeState state) {
        // Deliberately every two ticks and deliberately dense. ParticleOptimizer batches packets;
        // none of these requested visible particles are dropped.
        if ((tick & 1L) != 0L) return;
        double cx = (state.arenaMinX + state.arenaMaxX + 1.0) * 0.5;
        double cz = (state.arenaMinZ + state.arenaMaxZ + 1.0) * 0.5;
        double width = Math.max(6.0, state.arenaMaxX - state.arenaMinX);
        double depth = Math.max(6.0, state.arenaMaxZ - state.arenaMinZ);
        double y0 = state.arenaY + 1.0;

        DustParticleOptions accent = switch (definition.difficulty()) {
            case EASY -> new DustParticleOptions(0x57F287, 1.10F);
            case NORMAL -> new DustParticleOptions(0x42C9FF, 1.20F);
            case HARD -> new DustParticleOptions(0xFF405D, 1.30F);
        };
        DustParticleOptions second = switch (definition.difficulty()) {
            case EASY -> new DustParticleOptions(0xC7FFB8, 0.90F);
            case NORMAL -> new DustParticleOptions(0xB6F4FF, 0.95F);
            case HARD -> new DustParticleOptions(0xFF9B55, 1.05F);
        };

        ParticleOptimizer.emit(level, accent, cx, y0 + 0.55, cz,
                64, width * 0.44, 0.55, depth * 0.44, 0.015);
        ParticleOptimizer.emit(level, ParticleTypes.END_ROD, cx, y0 + 1.2, cz,
                28, width * 0.38, 1.8, depth * 0.38, 0.025);

        double time = tick * 0.11;
        double radius = Math.max(4.0, Math.min(width, depth) * 0.32);
        for (int arm = 0; arm < 4; arm++) {
            double phase = time + arm * Math.PI * 0.5;
            for (int node = 0; node < 5; node++) {
                double angle = phase - node * 0.34;
                double y = y0 + 0.4 + node * 1.25 + (tick % 40) * 0.055;
                ParticleOptimizer.emit(level, (node & 1) == 0 ? accent : second,
                        cx + Math.cos(angle) * (radius + node * 0.20), y,
                        cz + Math.sin(angle) * (radius + node * 0.20),
                        3, 0.10, 0.18, 0.10, 0.01);
            }
        }

        boolean bossMechanic = definition.mechanic() == MiniEventMechanic.ELITE_BOSS
                || (definition.mechanic() == MiniEventMechanic.MULTI_PHASE_ASSAULT && state.eventPhase >= 2);
        if (bossMechanic && state.targetEntityId != null) {
            Entity raw = level.getEntity(state.targetEntityId);
            if (raw instanceof LivingEntity boss && boss.isAlive()) {
                double bx = boss.getX(), by = boss.getY() + boss.getBbHeight() * 0.55, bz = boss.getZ();
                ParticleOptimizer.emit(level, accent, bx, by, bz,
                        56, 1.25, Math.max(1.0, boss.getBbHeight() * 0.65), 1.25, 0.025);
                ParticleOptimizer.emit(level, second, bx, by + 0.35, bz,
                        34, 0.85, Math.max(0.8, boss.getBbHeight() * 0.50), 0.85, 0.015);
                ParticleOptimizer.emit(level, ParticleTypes.ENCHANTED_HIT, bx, by, bz,
                        22, 1.1, 1.4, 1.1, 0.03);
            }
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
    }

    private record CompletionBurst(List<String> participants, long fireAt) {}
}
JAVA

cat > "$HOT/src/main/java/dev/brigada13/hotfix/mixin/ChallengeServiceMixin.java" <<'JAVA'
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
    @Unique private static final double WALL_MARGIN = 1.25;
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

    @Redirect(method = "tickEvent",
            at = @At(value = "INVOKE",
                    target = "Ldev/brigada13/core/challenge/ChallengeService;allParticipantsInside(Lnet/minecraft/server/MinecraftServer;Lnet/minecraft/server/level/ServerLevel;Ldev/brigada13/core/state/ActiveChallengeState;)Z"),
            require = 0)
    private boolean clearOfWall(MinecraftServer server, ServerLevel level, ActiveChallengeState state) {
        double margin = state.arenaLocked ? 0.0 : WALL_MARGIN;
        for (String participant : state.contribution.keySet()) {
            ServerPlayer player = server.getPlayerList().getPlayerByName(participant);
            if (player == null || player.level() != level) return false;
            if (player.getX() < state.arenaMinX + margin || player.getX() > state.arenaMaxX - margin
                    || player.getZ() < state.arenaMinZ + margin || player.getZ() > state.arenaMaxZ - margin) return false;
        }
        return true;
    }

    @Inject(method = "complete", at = @At("HEAD"), require = 0)
    private void completionBurst(MinecraftServer server, ChallengeDefinition definition,
                                 ActiveChallengeState state, CallbackInfo ci) {
        RuntimeFixes.scheduleCompletionBurst(state.contribution.keySet());
    }
}
JAVA

echo '=== build locally on VPS ==='
cd "$HOT"
./gradlew clean build --no-daemon --stacktrace
JAR=$(find build/libs -maxdepth 1 -type f -name 'brigada-hotfix-*.jar' ! -name '*sources*' ! -name '*dev*' -print -quit)
test -n "$JAR" -a -s "$JAR"
echo "built=$JAR"
jar tf "$JAR" | grep -E 'BrigadaHotfix|RuntimeFixes|ChallengeServiceMixin|brigada_hotfix.mixins.json'

echo '=== deploy ==='
cp -a "$CORE_JAR" "$CORE_JAR.backup-$STAMP"
rm -f "$SERVER/mods/brigada-hotfix-"*.jar
install -m 0644 "$JAR" "$SERVER/mods/brigada-hotfix-1.0.0.jar"
sha256sum "$SERVER/mods/brigada-hotfix-1.0.0.jar"
systemctl restart minecraft

for i in $(seq 1 30); do
    if systemctl is-active --quiet minecraft && ss -ltn | grep -q ':25565 '; then break; fi
    sleep 1
done

echo '=== status ==='
systemctl is-active minecraft
ss -ltnp | grep ':25565 ' || true
journalctl -u minecraft --since '-2 min' --no-pager | tail -n 180

echo '=== fatal scan ==='
if journalctl -u minecraft --since '-2 min' --no-pager | grep -Eqi 'Mixin.*(failed|error)|InjectionError|InvalidMixin|Exception in server tick loop|Could not execute entrypoint|ModResolutionException'; then
    echo 'FATAL_STARTUP_ERROR_FOUND'
    exit 42
fi

echo 'DEPLOY_OK'
