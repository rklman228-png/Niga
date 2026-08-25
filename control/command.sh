set -euo pipefail
HOT=/opt/brigada-hotfix-src
SRC="$HOT/src/main/java/dev/brigada13/hotfix/RuntimeFixes.java"
MIX="$HOT/src/main/java/dev/brigada13/hotfix/mixin/ChallengeServiceMixin.java"
MIXJSON="$HOT/src/main/resources/brigada_hotfix.mixins.json"
SERVER=/opt/minecraft/server
MOD="$SERVER/mods/brigada-hotfix-1.0.0.jar"
PACK=/opt/minecraft/resourcepack/world-ui-26.3-snapshot-9.zip
MCJAR=/root/.gradle/caches/fabric-loom/26.3-snapshot-9/minecraft-merged.jar
STAMP=$(date -u +%Y%m%dT%H%M%SZ)

cp -a "$SRC" "$SRC.bak-$STAMP"
cp -a "$MIX" "$MIX.bak-$STAMP"
cp -a "$MIXJSON" "$MIXJSON.bak-$STAMP"
cp -a "$PACK" "$PACK.bak-$STAMP"

python3 - <<'PY'
from pathlib import Path
import re
p=Path('/opt/brigada-hotfix-src/src/main/java/dev/brigada13/hotfix/RuntimeFixes.java')
s=p.read_text()

def once(old,new,name):
    global s
    if old not in s:
        raise SystemExit(f'missing patch anchor: {name}')
    s=s.replace(old,new,1)

once('import net.fabricmc.fabric.api.event.lifecycle.v1.ServerTickEvents;\n',
     'import net.fabricmc.fabric.api.event.lifecycle.v1.ServerTickEvents;\nimport net.fabricmc.fabric.api.event.lifecycle.v1.ServerEntityEvents;\n', 'ServerEntityEvents import')
once('import net.minecraft.core.particles.ParticleTypes;\n',
     'import net.minecraft.core.particles.ParticleTypes;\nimport net.minecraft.core.particles.ParticleOptions;\n', 'ParticleOptions import')
once('import net.minecraft.world.entity.Mob;\n',
     'import net.minecraft.world.entity.Mob;\nimport net.minecraft.world.entity.monster.cubemob.MagmaCube;\n', 'MagmaCube import')
once('import java.util.UUID;\n',
     'import java.util.UUID;\nimport java.nio.file.Files;\nimport java.nio.file.Path;\n', 'nio imports')
once('    private static int observedPhase = -1;\n',
     '    private static int observedPhase = -1;\n    private static long magmaLineageEvent = Long.MIN_VALUE;\n    private static boolean magmaLineageSeen;\n', 'magma fields')
once('        ServerLivingEntityEvents.AFTER_DAMAGE.register(RuntimeFixes::afterDamage);\n        ServerTickEvents.END_SERVER_TICK.register(RuntimeFixes::tick);\n',
     '        ServerLivingEntityEvents.AFTER_DAMAGE.register(RuntimeFixes::afterDamage);\n        ServerEntityEvents.ENTITY_LOAD.register(RuntimeFixes::onEntityLoad);\n        ServerTickEvents.END_SERVER_TICK.register(RuntimeFixes::tick);\n        dumpItemRegistry();\n', 'register')

anchor='    private static boolean allowDamage(LivingEntity entity, DamageSource source, float amount) {\n'
insert='''    private static void dumpItemRegistry() {
        try {
            StringBuilder out = new StringBuilder();
            for (var item : BuiltInRegistries.ITEM) {
                Identifier key = BuiltInRegistries.ITEM.getKey(item);
                if (key == null) continue;
                int rawId = BuiltInRegistries.ITEM.getId(item);
                out.append(rawId).append('\\t').append(key).append('\\n');
            }
            Files.writeString(Path.of("brigada-item-registry.tsv"), out.toString());
        } catch (Exception e) {
            System.err.println("[brigada_hotfix] item registry dump failed: " + e);
        }
    }

    private static void onEntityLoad(Entity entity, ServerLevel level) {
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

'''
if anchor not in s: raise SystemExit('missing allowDamage anchor')
s=s.replace(anchor,insert+anchor,1)

once('                    SoundEvents.UI_TOAST_CHALLENGE_COMPLETE, 1.0F, 1.0F);\n',
     '                    SoundEvents.BEACON_ACTIVATE, 1.45F, 1.38F);\n', 'completion sound')
once('                    SoundEvents.PLAYER_LEVELUP, 0.9F, 1.05F);\n',
     '                    SoundEvents.PLAYER_LEVELUP, 1.15F, 0.96F);\n', 'levelup sound')

once('        if (state != null) {\n            ChallengeDefinition definition = BrigadaCore.challenges().require(state.challengeId);\n',
     '        if (state != null) {\n            if (magmaLineageEvent != state.startedAtEpochMillis) {\n                magmaLineageEvent = state.startedAtEpochMillis;\n                magmaLineageSeen = false;\n            }\n            ChallengeDefinition definition = BrigadaCore.challenges().require(state.challengeId);\n', 'event lineage reset')
once('            observedPhase = -1;\n        }\n        tickBursts(server);\n',
     '            observedPhase = -1;\n            magmaLineageEvent = Long.MIN_VALUE;\n            magmaLineageSeen = false;\n        }\n        tickBursts(server);\n', 'inactive lineage reset')

once('            if (!(raw instanceof Mob mob) || !mob.isAlive()) continue;\n\n            // No event mob may use the old perimeter as a ladder/path. Keep a real inner margin.\n',
     '            if (!(raw instanceof Mob mob) || !mob.isAlive()) continue;\n\n            mob.setPersistenceRequired();\n            if (mob instanceof MagmaCube) {\n                magmaLineageEvent = state.startedAtEpochMillis;\n                magmaLineageSeen = true;\n            }\n\n            // No event mob may use the old perimeter as a ladder/path. Keep a real inner margin.\n', 'stabilise persistence')

pattern=re.compile(r'    private static void renderMeaningfulParticles\(ServerLevel level, ChallengeDefinition definition,\n.*?\n    private static void afterDamage\(', re.S)
replacement=r'''    private static void renderMeaningfulParticles(ServerLevel level, ChallengeDefinition definition,
                                                   ActiveChallengeState state) {
        if (tick % 4 != 0) return;
        DustParticleOptions red = new DustParticleOptions(0xFF204A, 1.35F);
        DustParticleOptions white = new DustParticleOptions(0xF8FFFF, 1.20F);

        // A thick, terrain-following perimeter. One point per block plus an inward white rail makes the
        // invisible hard wall readable from both ground level and from above without creating a climbable wall.
        for (int x = state.arenaMinX; x <= state.arenaMaxX; x++) {
            boundaryDot(level, red, x + 0.5, state.arenaMinZ + 0.45, state.arenaY);
            boundaryDot(level, white, x + 0.5, state.arenaMinZ + 0.95, state.arenaY);
            boundaryDot(level, red, x + 0.5, state.arenaMaxZ + 0.55, state.arenaY);
            boundaryDot(level, white, x + 0.5, state.arenaMaxZ + 0.05, state.arenaY);
            if ((x - state.arenaMinX) % 6 == 0) {
                shortMarker(level, red, x + 0.5, state.arenaMinZ + 0.55, state.arenaY);
                shortMarker(level, red, x + 0.5, state.arenaMaxZ + 0.45, state.arenaY);
            }
        }
        for (int z = state.arenaMinZ; z <= state.arenaMaxZ; z++) {
            boundaryDot(level, red, state.arenaMinX + 0.45, z + 0.5, state.arenaY);
            boundaryDot(level, white, state.arenaMinX + 0.95, z + 0.5, state.arenaY);
            boundaryDot(level, red, state.arenaMaxX + 0.55, z + 0.5, state.arenaY);
            boundaryDot(level, white, state.arenaMaxX + 0.05, z + 0.5, state.arenaY);
            if ((z - state.arenaMinZ) % 6 == 0) {
                shortMarker(level, red, state.arenaMinX + 0.55, z + 0.5, state.arenaY);
                shortMarker(level, red, state.arenaMaxX + 0.45, z + 0.5, state.arenaY);
            }
        }

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

    private static void afterDamage('''
s,n=pattern.subn(replacement,s,1)
if n != 1: raise SystemExit(f'render block replacements={n}')

once('        play(level, x, y, z, SoundEvents.FIREWORK_ROCKET_LARGE_BLAST, 1.2F, 0.95F);\n        play(level, x, y, z, SoundEvents.FIREWORK_ROCKET_TWINKLE, 1.0F, 1.12F);\n',
     '        play(level, x, y, z, SoundEvents.FIREWORK_ROCKET_LARGE_BLAST, 2.2F, 0.95F);\n        play(level, x, y, z, SoundEvents.FIREWORK_ROCKET_TWINKLE, 1.8F, 1.12F);\n        // The visual burst is high in the sky; duplicate its audio at the participant so distance never eats it.\n        play(level, player.getX(), player.getY(), player.getZ(), SoundEvents.FIREWORK_ROCKET_LARGE_BLAST, 4.0F, 0.92F);\n        play(level, player.getX(), player.getY(), player.getZ(), SoundEvents.FIREWORK_ROCKET_TWINKLE, 3.2F, 1.10F);\n', 'firework sounds')

p.write_text(s)
print('RuntimeFixes patched')
PY

python3 - <<'PY'
from pathlib import Path
p=Path('/opt/brigada-hotfix-src/src/main/java/dev/brigada13/hotfix/mixin/ChallengeServiceMixin.java')
s=p.read_text()
if 'net.minecraft.core.particles.ParticleOptions;' not in s:
    s=s.replace('import net.minecraft.core.BlockPos;\n','import net.minecraft.core.BlockPos;\nimport net.minecraft.core.particles.ParticleOptions;\n',1)
anchor='''    @Inject(method = "complete", at = @At("HEAD"), require = 0)
'''
method='''    @Redirect(method = {"tickHold", "tickSplit", "tickExtraction"},
            at = @At(value = "INVOKE",
                    target = "Ldev/brigada13/core/challenge/ChallengeService;renderZone(Lnet/minecraft/server/level/ServerLevel;IIIILnet/minecraft/core/particles/ParticleOptions;)V"),
            require = 0)
    private void renderGroundObjectiveZone(ServerLevel level, int x, int y, int z, int radius,
                                           ParticleOptions particle) {
        RuntimeFixes.renderGroundZone(level, x, y, z, radius, particle);
    }

'''
if 'renderGroundObjectiveZone' not in s:
    if anchor not in s: raise SystemExit('complete injection anchor missing')
    s=s.replace(anchor,method+anchor,1)
p.write_text(s)
print('ChallengeServiceMixin patched')
PY

cat > "$HOT/src/main/java/dev/brigada13/hotfix/mixin/WorldMenuServiceMixin.java" <<'JAVA'
package dev.brigada13.hotfix.mixin;

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
JAVA

cat > "$MIXJSON" <<'JSON'
{
  "required": true,
  "package": "dev.brigada13.hotfix.mixin",
  "compatibilityLevel": "JAVA_25",
  "mixins": ["ChallengeServiceMixin", "WorldMenuServiceMixin"],
  "injectors": {"defaultRequire": 1}
}
JSON

echo '=== patched source checks ==='
grep -nE 'ENTITY_LOAD|MagmaCube|renderGroundZone|BEACON_ACTIVATE, 1.45|FIREWORK_ROCKET_LARGE_BLAST, 4.0|dumpItemRegistry' "$SRC"
grep -nE 'renderGroundObjectiveZone|renderZone' "$MIX"
cat "$MIXJSON"

echo '=== build hotfix on VPS ==='
cd "$HOT"
./gradlew clean build --no-daemon --stacktrace
JAR=$(find build/libs -maxdepth 1 -type f -name 'brigada-hotfix-*.jar' ! -name '*sources*' ! -name '*dev*' -print -quit)
test -n "$JAR" -a -s "$JAR"
sha256sum "$JAR"
jar tf "$JAR" | grep -E 'RuntimeFixes|ChallengeServiceMixin|WorldMenuServiceMixin|brigada_hotfix.mixins.json'

install -m 0644 "$JAR" "$MOD"
rm -f "$SERVER/brigada-item-registry.tsv"
FIRST_SINCE=$(date '+%Y-%m-%d %H:%M:%S')
systemctl restart minecraft

echo '=== first restart: registry dump ==='
for i in $(seq 1 120); do
  systemctl is-active --quiet minecraft || { echo SERVER_DIED_FIRST; exit 31; }
  if [ -s "$SERVER/brigada-item-registry.tsv" ] && journalctl -u minecraft --since "$FIRST_SINCE" --no-pager | grep -q 'Done ('; then break; fi
  sleep 1
done
test -s "$SERVER/brigada-item-registry.tsv"
journalctl -u minecraft --since "$FIRST_SINCE" --no-pager | grep -E 'brigada_hotfix|Done \(|ERROR|Exception|MixinApplyError|InjectionError|InvalidMixin|NoSuchMethodError' | tail -n 160 || true
! journalctl -u minecraft --since "$FIRST_SINCE" --no-pager | grep -Eqi 'InjectionError|InvalidMixin|MixinApplyError|Could not execute entrypoint|ModResolutionException|Exception in server tick loop|Failed to start the minecraft server|NoSuchMethodError'
wc -l "$SERVER/brigada-item-registry.tsv"

echo '=== regenerate item font for the whole vanilla registry ==='
python3 - <<'PY'
from pathlib import Path
import json, zipfile, shutil, os, re
pack=Path('/opt/minecraft/resourcepack/world-ui-26.3-snapshot-9.zip')
mcjar=Path('/root/.gradle/caches/fabric-loom/26.3-snapshot-9/minecraft-merged.jar')
registry=Path('/opt/minecraft/server/brigada-item-registry.tsv')
new=pack.with_suffix('.zip.new')
with zipfile.ZipFile(mcjar) as z:
    names=set(z.namelist())

item_tex=sorted(n for n in names if n.startswith('assets/minecraft/textures/item/') and n.endswith('.png'))
block_tex=sorted(n for n in names if n.startswith('assets/minecraft/textures/block/') and n.endswith('.png'))
item_set=set(item_tex); block_set=set(block_tex)

aliases={
 'enchanted_golden_apple':'assets/minecraft/textures/item/golden_apple.png',
 'crossbow':'assets/minecraft/textures/item/crossbow_standby.png',
 'compass':'assets/minecraft/textures/item/compass_00.png',
 'recovery_compass':'assets/minecraft/textures/item/recovery_compass_00.png',
 'clock':'assets/minecraft/textures/item/clock_00.png',
 'fishing_rod':'assets/minecraft/textures/item/fishing_rod.png',
 'filled_map':'assets/minecraft/textures/item/map.png',
 'map':'assets/minecraft/textures/item/map.png',
 'tipped_arrow':'assets/minecraft/textures/item/tipped_arrow_base.png',
 'potion':'assets/minecraft/textures/item/potion_overlay.png',
 'splash_potion':'assets/minecraft/textures/item/potion_overlay.png',
 'lingering_potion':'assets/minecraft/textures/item/potion_overlay.png',
 'trident':'assets/minecraft/textures/entity/trident.png',
 'shield':'assets/minecraft/textures/entity/shield_base_nopattern.png',
}
strip_suffixes=['_stairs','_slab','_wall','_fence_gate','_fence','_button','_pressure_plate','_trapdoor','_door','_sign','_hanging_sign','_carpet']

def resource_name(path):
    marker='assets/minecraft/textures/'
    return 'minecraft:'+path.split(marker,1)[1]

def pick(path):
    exact='assets/minecraft/textures/item/'+path+'.png'
    if exact in item_set: return exact
    a=aliases.get(path)
    if a in names: return a
    exactb='assets/minecraft/textures/block/'+path+'.png'
    if exactb in block_set: return exactb
    base=path
    changed=True
    while changed:
        changed=False
        for suf in strip_suffixes:
            if base.endswith(suf):
                base=base[:-len(suf)]; changed=True; break
    if base != path:
        for c in ('assets/minecraft/textures/item/'+base+'.png','assets/minecraft/textures/block/'+base+'.png'):
            if c in names: return c
    ip='assets/minecraft/textures/item/'+path+'_'
    cand=[n for n in item_tex if n.startswith(ip)]
    if cand:
        for hint in ('standby','base','00','0'):
            for n in cand:
                if hint in Path(n).stem: return n
        return cand[0]
    bp='assets/minecraft/textures/block/'+path+'_'
    cand=[n for n in block_tex if n.startswith(bp)]
    if cand:
        for hint in ('front','side','top'):
            for n in cand:
                if n.endswith('_'+hint+'.png'): return n
        return cand[0]
    if base != path:
        bp='assets/minecraft/textures/block/'+base+'_'
        cand=[n for n in block_tex if n.startswith(bp)]
        if cand:
            for hint in ('front','side','top'):
                for n in cand:
                    if n.endswith('_'+hint+'.png'): return n
            return cand[0]
    return None

providers=[]; missing=[]; total=0
for line in registry.read_text().splitlines():
    if not line.strip(): continue
    raw_s,key=line.split('\t',1); raw=int(raw_s); total+=1
    if not key.startswith('minecraft:'): continue
    cp=0xE300+raw
    if cp>0xF8FF: continue
    path=key.split(':',1)[1]
    tex=pick(path)
    if tex is None:
        missing.append(key); continue
    providers.append({'type':'bitmap','file':resource_name(tex),'ascent':13,'height':16,'chars':[chr(cp)]})

font=json.dumps({'providers':providers},ensure_ascii=False,separators=(',',':')).encode('utf-8')
with zipfile.ZipFile(pack,'r') as zin, zipfile.ZipFile(new,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as zout:
    for info in zin.infolist():
        if info.filename=='assets/brigada_core/font/item_icons.json': continue
        zout.writestr(info,zin.read(info.filename))
    zout.writestr('assets/brigada_core/font/item_icons.json',font)
os.replace(new,pack)
print(f'registry={total} providers={len(providers)} missing={len(missing)}')
print('missing_sample='+' '.join(missing[:80]))
PY

PACK_SHA=$(sha1sum "$PACK" | awk '{print $1}')
NEW_ID=$(cat /proc/sys/kernel/random/uuid)
sed -i "s/^resource-pack-sha1=.*/resource-pack-sha1=$PACK_SHA/" "$SERVER/server.properties"
sed -i "s/^resource-pack-id=.*/resource-pack-id=$NEW_ID/" "$SERVER/server.properties"
echo "pack_sha1=$PACK_SHA"
echo "pack_id=$NEW_ID"
unzip -p "$PACK" assets/brigada_core/font/item_icons.json | wc -c
curl -fsS http://127.0.0.1:8088/world-ui-26.3-snapshot-9.zip | sha1sum

echo '=== final restart ==='
FINAL_SINCE=$(date '+%Y-%m-%d %H:%M:%S')
systemctl restart minecraft
for i in $(seq 1 120); do
  systemctl is-active --quiet minecraft || { echo SERVER_DIED_FINAL; exit 41; }
  if ss -ltn | grep -q ':25565 ' && journalctl -u minecraft --since "$FINAL_SINCE" --no-pager | grep -q 'Done ('; then break; fi
  sleep 1
done

echo '=== final verification ==='
systemctl is-active minecraft
ss -ltnp | grep ':25565 '
grep -E '^(resource-pack|resource-pack-sha1|resource-pack-id|require-resource-pack)' "$SERVER/server.properties"
sha256sum "$MOD"
sha1sum "$PACK"
journalctl -u minecraft --since "$FINAL_SINCE" --no-pager | grep -E 'brigada_hotfix|Done \(|ERROR|Exception|MixinApplyError|InjectionError|InvalidMixin|NoSuchMethodError' | tail -n 200 || true
test "$(systemctl is-active minecraft)" = active
ss -ltn | grep -q ':25565 '
journalctl -u minecraft --since "$FINAL_SINCE" --no-pager | grep -q 'Done ('
! journalctl -u minecraft --since "$FINAL_SINCE" --no-pager | grep -Eqi 'InjectionError|InvalidMixin|MixinApplyError|Could not execute entrypoint|ModResolutionException|Exception in server tick loop|Failed to start the minecraft server|NoSuchMethodError'
echo FULL_EVENT_UI_FIX_OK
