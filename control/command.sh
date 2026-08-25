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

# imports for challenge-wide item restrictions / projectile blocking
anchor='import net.minecraft.world.entity.Mob;\n'
add='import net.minecraft.world.entity.Mob;\nimport net.minecraft.world.entity.projectile.Projectile;\nimport net.minecraft.world.item.ItemStack;\n'
if 'import net.minecraft.world.entity.projectile.Projectile;' not in s:
    if anchor not in s: raise SystemExit('import anchor missing')
    s=s.replace(anchor, add, 1)

# Projectile restrictions happen before magma-cube lineage handling.
old='''    private static void onEntityLoad(Entity entity, ServerLevel level) {\n        if (!(entity instanceof MagmaCube cube) || !cube.isAlive()) return;'''
new='''    private static void onEntityLoad(Entity entity, ServerLevel level) {\n        if (entity instanceof Projectile projectile && isForbiddenChallengeProjectile(entity)) {\n            Entity owner = projectile.getOwner();\n            if (owner instanceof ServerPlayer player && isChallengeParticipant(player)) {\n                entity.discard();\n                return;\n            }\n        }\n        if (!(entity instanceof MagmaCube cube) || !cube.isAlive()) return;'''
if old in s:
    s=s.replace(old,new,1)
elif 'isForbiddenChallengeProjectile(entity)' not in s:
    raise SystemExit('onEntityLoad anchor missing')

# Block mace and other explicitly banned attack items for every challenge, not just mini-events.
old='''    private static boolean allowDamage(LivingEntity entity, DamageSource source, float amount) {\n        ActiveChallengeState state = BrigadaCore.stateStore().state().activeChallenge;'''
new='''    private static boolean allowDamage(LivingEntity entity, DamageSource source, float amount) {\n        if (source.getEntity() instanceof ServerPlayer attacker\n                && isChallengeParticipant(attacker)\n                && isForbiddenChallengeItem(attacker.getMainHandItem())) return false;\n        ActiveChallengeState state = BrigadaCore.stateStore().state().activeChallenge;'''
if old in s:
    s=s.replace(old,new,1)
elif 'isForbiddenChallengeItem(attacker.getMainHandItem())' not in s:
    raise SystemExit('allowDamage anchor missing')

# Enforce restrictions on every active challenge before mini-event-only logic.
old='''    private static void tick(MinecraftServer server) {\n        tick++;\n        ActiveChallengeState state = activeEvent();'''
new='''    private static void tick(MinecraftServer server) {\n        tick++;\n        enforceChallengeRestrictions(server);\n        ActiveChallengeState state = activeEvent();'''
if old in s:
    s=s.replace(old,new,1)
elif 'enforceChallengeRestrictions(server);' not in s:
    raise SystemExit('tick anchor missing')

# Generalize pressure from split-only to mechanics that are supposed to pressure continuously.
s=s.replace('tickSplitPressure(level, definition, state);', 'tickContinuousPressure(level, definition, state);')
s=s.replace('private static void tickSplitPressure(ServerLevel level, ChallengeDefinition definition,',
            'private static void tickContinuousPressure(ServerLevel level, ChallengeDefinition definition,')
s=s.replace('''        if (definition.mechanic() != MiniEventMechanic.SPLIT_OBJECTIVES) return;\n        if (splitPressureEvent != state.startedAtEpochMillis) {''',
'''        if (!continuousPressureMechanic(definition.mechanic())) return;\n        if (splitPressureEvent != state.startedAtEpochMillis) {''',1)

# Continuous pressure: Easy remains approachable; Normal is busy; Hard never lets the arena go empty for long.
old='''        int interval = switch (definition.difficulty()) {\n            case EASY -> 240;\n            case NORMAL -> 160;\n            case HARD -> 120;\n        };'''
new='''        int interval = switch (definition.difficulty()) {\n            case EASY -> 200;\n            case NORMAL -> 120;\n            case HARD -> 80;\n        };'''
if old not in s: raise SystemExit('pressure interval anchor missing')
s=s.replace(old,new,1)
old='''        int cap = switch (definition.difficulty()) {\n            case EASY -> 6;\n            case NORMAL -> 10;\n            case HARD -> 14;\n        };'''
new='''        int cap = switch (definition.difficulty()) {\n            case EASY -> 8;\n            case NORMAL -> 14;\n            case HARD -> 20;\n        };'''
if old not in s: raise SystemExit('pressure cap anchor missing')
s=s.replace(old,new,1)
old='''        int amount = switch (definition.difficulty()) {\n            case EASY -> 2;\n            case NORMAL -> 3;\n            case HARD -> 4;\n        } + (state.singleMode ? 0 : 1);'''
new='''        int amount = switch (definition.difficulty()) {\n            case EASY -> 2;\n            case NORMAL -> 4;\n            case HARD -> 6;\n        } + (state.singleMode ? 0 : 1);'''
if old not in s: raise SystemExit('pressure amount anchor missing')
s=s.replace(old,new,1)

# Difficulty curve applies only in active mini-events because scaleEventMobs is only called from activeEvent().
old='''        double healthMultiplier = switch (definition.difficulty()) {\n            case EASY -> 1.00;\n            case NORMAL -> 1.15;\n            case HARD -> 1.30;\n        };\n        double damageMultiplier = switch (definition.difficulty()) {\n            case EASY -> 1.00;\n            case NORMAL -> 1.15;\n            case HARD -> 1.42;\n        };\n        double speedMultiplier = switch (definition.difficulty()) {\n            case EASY -> 1.00;\n            case NORMAL -> 1.03;\n            case HARD -> 1.06;\n        };'''
new='''        double healthMultiplier = switch (definition.difficulty()) {\n            case EASY -> 1.00;\n            case NORMAL -> 1.25;\n            case HARD -> 1.50;\n        };\n        double damageMultiplier = switch (definition.difficulty()) {\n            case EASY -> 1.00;\n            case NORMAL -> 1.65;\n            case HARD -> 2.50;\n        };\n        double speedMultiplier = switch (definition.difficulty()) {\n            case EASY -> 1.00;\n            case NORMAL -> 1.06;\n            case HARD -> 1.10;\n        };'''
if old not in s:
    # also accept pre-42 source if hotfix was manually changed
    old_alt=old.replace('case NORMAL -> 1.15;\\n            case HARD -> 1.42;', 'case NORMAL -> 1.08;\\n            case HARD -> 1.16;')
    if old_alt in s: s=s.replace(old_alt,new,1)
    else: raise SystemExit('difficulty multiplier anchor missing')
else:
    s=s.replace(old,new,1)

# Preserve the old anti-one-shot intent only for naturally huge hitters; normal mobs get the full +150% Hard increase.
old='''                double appliedMultiplier = definition.difficulty() == ChallengeDifficulty.HARD && baseAttack >= 16.0\n                        ? 1.18 : damageMultiplier;'''
new='''                double appliedMultiplier = definition.difficulty() == ChallengeDifficulty.HARD && baseAttack >= 16.0\n                        ? 1.75 : damageMultiplier;'''
if old in s:
    s=s.replace(old,new,1)
elif '? 1.75 : damageMultiplier;' not in s:
    # Older source may still have the one-line multiplier. Replace that form.
    old2='''            var attack = mob.getAttribute(Attributes.ATTACK_DAMAGE);\n            if (attack != null && damageMultiplier != 1.0)\n                attack.setBaseValue(attack.getBaseValue() * damageMultiplier);'''
    new2='''            var attack = mob.getAttribute(Attributes.ATTACK_DAMAGE);\n            if (attack != null && damageMultiplier != 1.0) {\n                double baseAttack = attack.getBaseValue();\n                double appliedMultiplier = definition.difficulty() == ChallengeDifficulty.HARD && baseAttack >= 16.0\n                        ? 1.75 : damageMultiplier;\n                attack.setBaseValue(baseAttack * appliedMultiplier);\n            }'''
    if old2 not in s: raise SystemExit('attack multiplier anchor missing')
    s=s.replace(old2,new2,1)

# Insert challenge-wide restrictions and spawn-mode classification before activeEvent().
marker='''    private static ActiveChallengeState activeEvent() {'''
helpers='''    private static void enforceChallengeRestrictions(MinecraftServer server) {\n        ActiveChallengeState state = BrigadaCore.stateStore().state().activeChallenge;\n        if (state == null || state.contribution == null || state.contribution.isEmpty()) return;\n        for (String name : state.contribution.keySet()) {\n            ServerPlayer player = server.getPlayerList().getPlayerByName(name);\n            if (player == null) continue;\n            if (player.isUsingItem() && isForbiddenChallengeItem(player.getUseItem())) {\n                player.stopUsingItem();\n            }\n            if (player.isFallFlying()) player.stopFallFlying();\n        }\n    }\n\n    private static boolean isChallengeParticipant(ServerPlayer player) {\n        ActiveChallengeState state = BrigadaCore.stateStore().state().activeChallenge;\n        return state != null && state.contribution != null\n                && state.contribution.containsKey(player.getName().getString());\n    }\n\n    private static boolean isForbiddenChallengeItem(ItemStack stack) {\n        if (stack == null || stack.isEmpty()) return false;\n        Identifier key = BuiltInRegistries.ITEM.getKey(stack.getItem());\n        if (key == null) return false;\n        return switch (key.toString()) {\n            case "minecraft:golden_apple", "minecraft:enchanted_golden_apple",\n                    "minecraft:potion", "minecraft:splash_potion", "minecraft:lingering_potion",\n                    "minecraft:ender_pearl", "minecraft:chorus_fruit",\n                    "minecraft:wind_charge", "minecraft:firework_rocket",\n                    "minecraft:elytra", "minecraft:mace", "minecraft:trident" -> true;\n            default -> false;\n        };\n    }\n\n    private static boolean isForbiddenChallengeProjectile(Entity entity) {\n        Identifier key = BuiltInRegistries.ENTITY_TYPE.getKey(entity.getType());\n        if (key == null) return false;\n        return switch (key.toString()) {\n            case "minecraft:ender_pearl", "minecraft:wind_charge",\n                    "minecraft:potion", "minecraft:firework_rocket" -> true;\n            default -> false;\n        };\n    }\n\n    private static boolean continuousPressureMechanic(MiniEventMechanic mechanic) {\n        return switch (mechanic) {\n            case HOLD_ZONE, SPLIT_OBJECTIVES, EXTRACTION, NO_DEATH_GAUNTLET -> true;\n            case WAVES, HUNT_TARGETS, DEFEND_OBJECTIVE, ELITE_BOSS, MULTI_PHASE_ASSAULT -> false;\n        };\n    }\n\n'''
if 'private static boolean isForbiddenChallengeItem' not in s:
    if marker not in s: raise SystemExit('activeEvent marker missing')
    s=s.replace(marker, helpers+marker,1)

# Add the loud firework blast back on top of the Enderman victory climax.
needle='''        if (age == 44) {\n            ParticleOptimizer.emit(level, ParticleTypes.PORTAL,'''
replace='''        if (age == 44) {\n            ParticleOptimizer.emit(level, ParticleTypes.FIREWORK,\n                    px, py + 2.2, pz, 180, 3.8, 2.7, 3.8, 0.24);\n            play(level, px, py + 1.0, pz, SoundEvents.FIREWORK_ROCKET_LARGE_BLAST, 4.2F, 0.96F);\n            play(level, px, py + 1.0, pz, SoundEvents.FIREWORK_ROCKET_TWINKLE, 3.4F, 1.04F);\n            ParticleOptimizer.emit(level, ParticleTypes.PORTAL,'''
if needle in s:
    s=s.replace(needle,replace,1)
elif 'FIREWORK_ROCKET_LARGE_BLAST' not in s:
    raise SystemExit('victory climax anchor missing')

p.write_text(s)
print('patched hardcore event difficulty, restrictions, spawn modes, firework victory')
PY

cd "$HOT"
echo '=== build locally on VPS ==='
./gradlew clean build --no-daemon --stacktrace
JAR=build/libs/brigada-hotfix-0.1.0.jar
test -s "$JAR"
sha256sum "$JAR"
install -m 0644 "$JAR" "$MOD"

echo '=== restart and verify ==='
systemctl restart minecraft.service
sleep 2
START=$(systemctl show minecraft.service -p ActiveEnterTimestamp --value)
for i in $(seq 1 120); do
  if journalctl -u minecraft.service --since "$START" --no-pager | grep -q 'Done ('; then break; fi
  sleep 2
done
systemctl is-active minecraft.service
ss -ltnp | grep ':25565 '
sha256sum "$MOD"
journalctl -u minecraft.service --since "$START" --no-pager | tail -n 180
journalctl -u minecraft.service --since "$START" --no-pager | grep -q 'Done ('
! journalctl -u minecraft.service --since "$START" --no-pager | grep -Eqi 'InjectionError|InvalidMixin|MixinApplyError|Could not execute entrypoint|Exception in server tick loop|Failed to start the minecraft server'

echo '=== active settings ==='
grep -nA12 -B2 'double healthMultiplier' "$SRC"
grep -nA30 -B2 'continuousPressureMechanic' "$SRC" | head -n 60
grep -nA30 -B2 'isForbiddenChallengeItem' "$SRC" | head -n 70
grep -nA8 -B2 'FIREWORK_ROCKET_LARGE_BLAST' "$SRC"
echo HARDCORE_EVENT_RULESET_ACTIVE