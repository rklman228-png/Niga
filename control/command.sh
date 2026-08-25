set -euo pipefail
HOT=/opt/brigada-hotfix-src
SRC="$HOT/src/main/java/dev/brigada13/hotfix/RuntimeFixes.java"
MIX="$HOT/src/main/java/dev/brigada13/hotfix/mixin/ChallengeServiceMixin.java"
SERVER=/opt/minecraft/server
MOD="$SERVER/mods/brigada-hotfix-1.0.0.jar"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)

cp -a "$SRC" "$SRC.bak-$STAMP"
cp -a "$MIX" "$MIX.bak-$STAMP"
cp -a "$MOD" "$MOD.bak-$STAMP"

python3 - <<'PY'
from pathlib import Path
import re
p=Path('/opt/brigada-hotfix-src/src/main/java/dev/brigada13/hotfix/RuntimeFixes.java')
s=p.read_text()

def once(old,new,name):
    global s
    if old not in s:
        raise SystemExit(f'missing runtime anchor: {name}')
    s=s.replace(old,new,1)

# Imports.
if 'import net.fabricmc.fabric.api.event.player.PlayerBlockBreakEvents;' not in s:
    once('import net.fabricmc.fabric.api.event.lifecycle.v1.ServerEntityEvents;\n',
         'import net.fabricmc.fabric.api.event.lifecycle.v1.ServerEntityEvents;\nimport net.fabricmc.fabric.api.event.player.PlayerBlockBreakEvents;\n', 'block break import')
if 'import net.minecraft.world.level.block.state.BlockState;' not in s:
    once('import net.minecraft.world.level.block.Blocks;\n',
         'import net.minecraft.world.level.block.Blocks;\nimport net.minecraft.world.level.block.state.BlockState;\n', 'blockstate import')
if 'import java.io.BufferedInputStream;' not in s:
    once('import java.nio.file.Path;\n',
         'import java.nio.file.Path;\nimport java.io.BufferedInputStream;\nimport java.io.BufferedOutputStream;\nimport java.io.DataInputStream;\nimport java.io.DataOutputStream;\n', 'io imports')

s=s.replace('private static final int COMPLETION_BURST_DELAY = 100;',
            'private static final int COMPLETION_BURST_DELAY = 0;')

once('    private static final List<CompletionBurst> BURSTS = new ArrayList<>();\n',
'''    private static final List<CompletionBurst> BURSTS = new ArrayList<>();
    private static final List<WavePulse> WAVE_PULSES = new ArrayList<>();
    private static final Map<Long, Integer> BOUNDARY_ORIGINALS = new HashMap<>();
    private static final Path BOUNDARY_BACKUP = Path.of("brigada-boundary-backup.bin");
    private static long boundaryEvent = Long.MIN_VALUE;
    private static String boundaryDimension;
''', 'runtime fields')

once('        ServerEntityEvents.ENTITY_LOAD.register(RuntimeFixes::onEntityLoad);\n        ServerTickEvents.END_SERVER_TICK.register(RuntimeFixes::tick);\n        dumpItemRegistry();\n',
'''        ServerEntityEvents.ENTITY_LOAD.register(RuntimeFixes::onEntityLoad);
        PlayerBlockBreakEvents.BEFORE.register((level, player, pos, blockState, blockEntity) ->
                !isFullBoundaryPosition(level, pos));
        ServerTickEvents.END_SERVER_TICK.register(RuntimeFixes::tick);
        loadBoundaryBackup();
        dumpItemRegistry();
''', 'register barrier')

# Add persistent boundary helpers before allowDamage.
anchor='    private static boolean allowDamage(LivingEntity entity, DamageSource source, float amount) {\n'
if anchor not in s: raise SystemExit('missing allowDamage anchor')
helpers=r'''    private static void loadBoundaryBackup() {
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

'''
s=s.replace(anchor,helpers+anchor,1)

# Active tick: maintain real wall, never draw/clear it as particles.
once('                clearPhysicalBoundary(level, state);\n                confineParticipants(server, level, state);\n',
     '                ensureFullHeightBoundary(level, state);\n                confineParticipants(server, level, state);\n', 'tick ensure boundary')
once('            magmaLineageEvent = Long.MIN_VALUE;\n            magmaLineageSeen = false;\n        }\n        tickBursts(server);\n',
     '            magmaLineageEvent = Long.MIN_VALUE;\n            magmaLineageSeen = false;\n            restoreOrphanedBoundary(server);\n        }\n        tickWavePulses();\n        tickBursts(server);\n', 'tick effects and orphan restore')

# Replace old boundary clearing implementation with full-height snapshot/restore logic.
pattern=re.compile(r'    public static void clearPhysicalBoundary\(ServerLevel level, ActiveChallengeState state\) \{.*?\n    private static void confineParticipants\(', re.S)
replacement=r'''    public static void ensureFullHeightBoundary(ServerLevel level, ActiveChallengeState state) {
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

    private static void confineParticipants('''
s,n=pattern.subn(replacement,s,1)
if n != 1: raise SystemExit(f'boundary block replacement count={n}')

# Remove the permanent particle perimeter entirely; real glass is now the visible border.
pattern=re.compile(r'(    private static void renderMeaningfulParticles\(ServerLevel level, ChallengeDefinition definition,\n\s+ActiveChallengeState state\) \{\n\s+if \(tick % 4 != 0\) return;\n).*?(\n\s+if \(state\.targetEntityId == null\) return;)', re.S)
s,n=pattern.subn(r'\1        // The arena border is a real full-height glass wall; do not duplicate it with airborne/ground particles.\2', s, 1)
if n != 1: raise SystemExit(f'particle border replacement count={n}')

# Wave transition starts a visible expanding ender pulse.
once('        if (state.eventWave > observedWave) {\n            observedWave = state.eventWave;\n            playCenter(level, state, SoundEvents.EXPERIENCE_ORB_PICKUP, 0.8F,\n                    Math.min(1.55F, 0.95F + state.eventWave * 0.08F));\n        }\n',
'''        if (state.eventWave > observedWave) {
            observedWave = state.eventWave;
            playCenter(level, state, SoundEvents.EXPERIENCE_ORB_PICKUP, 0.8F,
                    Math.min(1.55F, 0.95F + state.eventWave * 0.08F));
            scheduleWavePulse(level, state);
        }
''', 'wave pulse scheduling')

# Replace firework completion block with ender-themed victory animation and wave pulse renderer.
pattern=re.compile(r'    private static void tickBursts\(MinecraftServer server\) \{.*?\n    private static void playCenter\(', re.S)
replacement=r'''    private static void tickBursts(MinecraftServer server) {
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

    private static void playCenter('''
s,n=pattern.subn(replacement,s,1)
if n != 1: raise SystemExit(f'victory block replacement count={n}')

# Add WavePulse record next to CompletionBurst.
once('    private record CompletionBurst(List<String> participants, long fireAt) {}\n',
     '    private record CompletionBurst(List<String> participants, long fireAt) {}\n    private record WavePulse(ServerLevel level, double cx, double cz, int anchorY, double maxRadius, long startedAt) {}\n', 'wave record')

p.write_text(s)
print('RuntimeFixes patched')
PY

python3 - <<'PY'
from pathlib import Path
p=Path('/opt/brigada-hotfix-src/src/main/java/dev/brigada13/hotfix/mixin/ChallengeServiceMixin.java')
s=p.read_text()

def once(old,new,name):
    global s
    if old not in s:
        raise SystemExit(f'missing mixin anchor: {name}')
    s=s.replace(old,new,1)

if 'import org.spongepowered.asm.mixin.Shadow;' not in s:
    once('import org.spongepowered.asm.mixin.Mixin;\n', 'import org.spongepowered.asm.mixin.Mixin;\nimport org.spongepowered.asm.mixin.Shadow;\n', 'shadow import')
if 'import java.util.Map;' not in s:
    once('import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;\n',
         'import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;\n\nimport java.util.Map;\n', 'map import')

once('public abstract class ChallengeServiceMixin {\n',
'''public abstract class ChallengeServiceMixin {
    @Shadow private Map<String, Long> celebrations;
''', 'shadow field')

# Real wall instead of logical/no-wall redirect.
s=s.replace('    // The arena is logical now. Physical glass is what spiders were climbing and what created the\n'
            '    // absurd sky-high planes in the screenshots. RuntimeFixes keeps mobs inside without blocks.\n',
            '    // Full-height physical arena wall. RuntimeFixes snapshots and restores every replaced BlockState.\n')
s=s.replace('    private void noPhysicalBoundary(MinecraftServer server, ServerLevel level, ActiveChallengeState state) {\n'
            '        RuntimeFixes.clearPhysicalBoundary(level, state);\n'
            '    }\n',
            '    private void fullHeightBoundary(MinecraftServer server, ServerLevel level, ActiveChallengeState state) {\n'
            '        RuntimeFixes.ensureFullHeightBoundary(level, state);\n'
            '    }\n')

once('    private void completionEffects(MinecraftServer server, ChallengeDefinition definition,\n'
     '                                   ActiveChallengeState state, CallbackInfo ci) {\n'
     '        RuntimeFixes.onComplete(server, state);\n'
     '    }\n',
'''    private void completionEffects(MinecraftServer server, ChallengeDefinition definition,
                                   ActiveChallengeState state, CallbackInfo ci) {
        RuntimeFixes.restoreBoundary(server, state);
        RuntimeFixes.onComplete(server, state);
    }

    @Inject(method = "complete", at = @At("TAIL"), require = 0)
    private void replaceCoreVictoryParticles(MinecraftServer server, ChallengeDefinition definition,
                                             ActiveChallengeState state, CallbackInfo ci) {
        for (String name : state.contribution.keySet()) celebrations.remove(name);
    }

    @Inject(method = "cancel", at = @At("HEAD"), require = 0)
    private void restoreBoundaryOnCancel(MinecraftServer server, CallbackInfo ci) {
        RuntimeFixes.restoreActiveBoundary(server);
    }
''', 'completion/cancel hooks')

p.write_text(s)
print('ChallengeServiceMixin patched')
PY

echo '=== source checks ==='
grep -nE 'ensureFullHeightBoundary|restoreBoundary|BOUNDARY_BACKUP|PORTAL|REVERSE_PORTAL|scheduleWavePulse|tickWavePulses|replaceCoreVictoryParticles|restoreBoundaryOnCancel' "$SRC" "$MIX" | head -n 120

echo '=== build ==='
cd "$HOT"
./gradlew clean build --no-daemon
sha256sum build/libs/brigada-hotfix-0.1.0.jar
cp -f build/libs/brigada-hotfix-0.1.0.jar "$MOD"

echo '=== restart ==='
systemctl restart minecraft-server.service
for i in $(seq 1 90); do
  if systemctl is-active --quiet minecraft-server.service && journalctl -u minecraft-server.service -n 80 --no-pager | grep -q 'Done ('; then
    break
  fi
  sleep 2
done

echo '=== verify ==='
systemctl is-active minecraft-server.service
ss -ltnp | grep ':25565 '
sha256sum "$MOD"
journalctl -u minecraft-server.service -n 140 --no-pager | grep -E 'brigada_hotfix|full-height boundary|boundary restored|boundary backup|Done \(' | tail -n 50 || true
if [ -f "$SERVER/brigada-boundary-backup.bin" ]; then
  stat -c 'boundary_backup_bytes=%s' "$SERVER/brigada-boundary-backup.bin"
else
  echo 'boundary_backup=none (no active locked event after restart)'
fi

echo FULL_HEIGHT_ENDER_EFFECTS_OK
