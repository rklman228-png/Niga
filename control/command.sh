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
p=Path('/opt/brigada-hotfix-src/src/main/java/dev/brigada13/hotfix/RuntimeFixes.java')
s=p.read_text()

def once(old,new,name):
    global s
    if old not in s:
        raise SystemExit('missing runtime anchor: '+name)
    s=s.replace(old,new,1)

if 'import net.minecraft.world.entity.EntitySpawnReason;' not in s:
    once('import net.minecraft.world.entity.Entity;\n',
         'import net.minecraft.world.entity.Entity;\nimport net.minecraft.world.entity.EntitySpawnReason;\n', 'EntitySpawnReason import')

once('    private static final Set<UUID> PREPARED_ELITES = new HashSet<>();\n',
'''    private static final Set<UUID> PREPARED_ELITES = new HashSet<>();
    private static final Set<UUID> PREPARED_COMBAT_MOBS = new HashSet<>();
''', 'combat mob set')
once('    private static boolean magmaLineageSeen;\n',
'''    private static boolean magmaLineageSeen;
    private static long combatScaleEvent = Long.MIN_VALUE;
    private static long splitPressureEvent = Long.MIN_VALUE;
    private static int splitPressureElapsed = -1;
''', 'balance state fields')

once('''                ensureFullHeightBoundary(level, state);
                confineParticipants(server, level, state);
                stabiliseEventMobs(level, state);
                fixDefense(level, definition, state);
''',
'''                ensureFullHeightBoundary(level, state);
                confineParticipants(server, level, state);
                scaleEventMobs(level, definition, state);
                stabiliseEventMobs(level, state);
                tickSplitPressure(level, definition, state);
                fixDefense(level, definition, state);
''', 'tick balance hooks')

anchor='    private static void stabiliseEventMobs(ServerLevel level, ActiveChallengeState state) {\n'
if anchor not in s: raise SystemExit('missing stabilise anchor')
helpers=r'''    private static void scaleEventMobs(ServerLevel level, ChallengeDefinition definition,
                                       ActiveChallengeState state) {
        if (combatScaleEvent != state.startedAtEpochMillis) {
            combatScaleEvent = state.startedAtEpochMillis;
            PREPARED_COMBAT_MOBS.clear();
        }
        double healthMultiplier = switch (definition.difficulty()) {
            case EASY -> 1.00;
            case NORMAL -> 1.15;
            case HARD -> 1.30;
        };
        double damageMultiplier = switch (definition.difficulty()) {
            case EASY -> 1.00;
            case NORMAL -> 1.08;
            case HARD -> 1.16;
        };
        double speedMultiplier = switch (definition.difficulty()) {
            case EASY -> 1.00;
            case NORMAL -> 1.03;
            case HARD -> 1.06;
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
            if (attack != null && damageMultiplier != 1.0)
                attack.setBaseValue(attack.getBaseValue() * damageMultiplier);
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

    private static void tickSplitPressure(ServerLevel level, ChallengeDefinition definition,
                                          ActiveChallengeState state) {
        if (definition.mechanic() != MiniEventMechanic.SPLIT_OBJECTIVES) return;
        if (splitPressureEvent != state.startedAtEpochMillis) {
            splitPressureEvent = state.startedAtEpochMillis;
            splitPressureElapsed = -1;
        }
        if (state.eventElapsedTicks < 40) return;

        int interval = switch (definition.difficulty()) {
            case EASY -> 240;
            case NORMAL -> 160;
            case HARD -> 120;
        };
        if (splitPressureElapsed >= 0 && state.eventElapsedTicks - splitPressureElapsed < interval) return;

        int cap = switch (definition.difficulty()) {
            case EASY -> 6;
            case NORMAL -> 10;
            case HARD -> 14;
        };
        int alive = 0;
        for (UUID id : state.eventEntities) {
            Entity entity = level.getEntity(id);
            if (entity instanceof Mob mob && mob.isAlive()) alive++;
        }
        if (alive >= cap) return;

        int amount = switch (definition.difficulty()) {
            case EASY -> 2;
            case NORMAL -> 3;
            case HARD -> 4;
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

'''
s=s.replace(anchor,helpers+anchor,1)

old='''        if (state.eventWave > observedWave) {
            observedWave = state.eventWave;
            playCenter(level, state, SoundEvents.EXPERIENCE_ORB_PICKUP, 0.8F,
                    Math.min(1.55F, 0.95F + state.eventWave * 0.08F));
            scheduleWavePulse(level, state);
        }
'''
new='''        if (state.eventWave > observedWave) {
            observedWave = state.eventWave;
            playCenter(level, state, SoundEvents.EXPERIENCE_ORB_PICKUP, 0.8F,
                    Math.min(1.55F, 0.95F + state.eventWave * 0.08F));
            scheduleWavePulse(level, state);
            reinforceHardVillageRaid(level, definition, state);
        }
'''
once(old,new,'hard village wave reinforcements')

p.write_text(s)
print('RuntimeFixes balance patched')

p=Path('/opt/brigada-hotfix-src/src/main/java/dev/brigada13/hotfix/mixin/ChallengeServiceMixin.java')
s=p.read_text()
if 'import org.spongepowered.asm.mixin.injection.Constant;' not in s:
    s=s.replace('import org.spongepowered.asm.mixin.injection.At;\n',
                'import org.spongepowered.asm.mixin.injection.At;\nimport org.spongepowered.asm.mixin.injection.Constant;\nimport org.spongepowered.asm.mixin.injection.ModifyConstant;\n',1)
anchor='''    @Inject(method = "complete", at = @At("HEAD"), require = 0)
'''
if anchor not in s: raise SystemExit('missing mixin complete anchor')
block='''    @Inject(method = "tickSplit", at = @At("HEAD"), require = 0)
    private void prepareBalancedSplit(MinecraftServer server, ServerLevel level, ChallengeDefinition definition,
                                      ActiveChallengeState state, CallbackInfo ci) {
        RuntimeFixes.prepareSplitBalance(definition, state);
    }

    @ModifyConstant(method = "tickSplit", constant = @Constant(intValue = 100), require = 0)
    private int extendSoloSplitPoint(int original) {
        ActiveChallengeState state = BrigadaCore.stateStore().state().activeChallenge;
        if (state == null) return original;
        try {
            ChallengeDefinition definition = BrigadaCore.challenges().require(state.challengeId);
            if (definition.mechanic() != dev.brigada13.core.challenge.MiniEventMechanic.SPLIT_OBJECTIVES)
                return original;
            return RuntimeFixes.splitSoloPointTicks(definition);
        } catch (RuntimeException ignored) {
            return original;
        }
    }

'''
s=s.replace(anchor,block+anchor,1)
p.write_text(s)
print('ChallengeServiceMixin balance patched')
PY

echo '=== source checks ==='
grep -nE 'splitSoloPointTicks|prepareSplitBalance|tickSplitPressure|reinforceHardVillageRaid|PREPARED_COMBAT_MOBS|ModifyConstant' "$SRC" "$MIX"

echo '=== build locally on VPS ==='
cd "$HOT"
./gradlew clean build --no-daemon --stacktrace
JAR=build/libs/brigada-hotfix-0.1.0.jar
test -s "$JAR"
sha256sum "$JAR"
install -m 0644 "$JAR" "$MOD"

echo '=== restart live server ==='
systemctl restart minecraft.service
for i in $(seq 1 100); do
  if ss -ltn | grep -q ':25565 '; then break; fi
  sleep 2
done
systemctl is-active minecraft.service
ss -ltnp | grep ':25565 '
sha256sum "$MOD"

START=$(systemctl show minecraft.service -p ActiveEnterTimestamp --value)
echo "service_started=$START"
journalctl -u minecraft.service --since "$START" --no-pager | tail -n 160
if journalctl -u minecraft.service --since "$START" --no-pager | grep -Eqi 'InjectionError|InvalidMixin|MixinApplyError|Could not execute entrypoint|Exception in server tick loop|Failed to start the minecraft server'; then
  echo FATAL_RUNTIME_ERROR
  exit 42
fi

echo BALANCE_REWORK_ACTIVE
