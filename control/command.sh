set -euo pipefail
HOT=/opt/brigada-hotfix-src
RUNTIME="$HOT/src/main/java/dev/brigada13/hotfix/RuntimeFixes.java"
JAR="$HOT/build/libs/brigada-hotfix-0.1.0.jar"
MOD=/opt/minecraft/server/mods/brigada-hotfix-1.0.0.jar

python3 - <<'PY'
from pathlib import Path
p = Path('/opt/brigada-hotfix-src/src/main/java/dev/brigada13/hotfix/RuntimeFixes.java')
s = p.read_text()

if 'private static final double PLAYER_EDGE_MARGIN' not in s:
    s = s.replace('private static final double MOB_EDGE_MARGIN = 2.35;',
                  'private static final double MOB_EDGE_MARGIN = 2.35;\n    private static final double PLAYER_EDGE_MARGIN = 0.55;')

s = s.replace('clearPhysicalBoundary(level, state);\n                stabiliseEventMobs(level, state);',
              'clearPhysicalBoundary(level, state);\n                confineParticipants(server, level, state);\n                stabiliseEventMobs(level, state);')

needle = '    private static void stabiliseEventMobs(ServerLevel level, ActiveChallengeState state) {'
method = '''    private static void confineParticipants(MinecraftServer server, ServerLevel level, ActiveChallengeState state) {\n        double minX = state.arenaMinX + PLAYER_EDGE_MARGIN;\n        double maxX = state.arenaMaxX + 1.0 - PLAYER_EDGE_MARGIN;\n        double minZ = state.arenaMinZ + PLAYER_EDGE_MARGIN;\n        double maxZ = state.arenaMaxZ + 1.0 - PLAYER_EDGE_MARGIN;\n        if (minX > maxX) minX = maxX = (state.arenaMinX + state.arenaMaxX + 1.0) * 0.5;\n        if (minZ > maxZ) minZ = maxZ = (state.arenaMinZ + state.arenaMaxZ + 1.0) * 0.5;\n\n        for (String participant : state.contribution.keySet()) {\n            ServerPlayer player = server.getPlayerList().getPlayerByName(participant);\n            if (player == null || player.level() != level) continue;\n\n            double oldX = player.getX();\n            double oldZ = player.getZ();\n            double x = Math.max(minX, Math.min(maxX, oldX));\n            double z = Math.max(minZ, Math.min(maxZ, oldZ));\n            boolean blockedX = Math.abs(x - oldX) > 1.0E-4;\n            boolean blockedZ = Math.abs(z - oldZ) > 1.0E-4;\n            if (!blockedX && !blockedZ) continue;\n\n            var motion = player.getDeltaMovement();\n            double vx = motion.x;\n            double vz = motion.z;\n            if (blockedX && ((oldX < minX && vx < 0.0) || (oldX > maxX && vx > 0.0))) vx = 0.0;\n            if (blockedZ && ((oldZ < minZ && vz < 0.0) || (oldZ > maxZ && vz > 0.0))) vz = 0.0;\n\n            // Server-authoritative invisible wall: the player can touch the marked perimeter,\n            // but every attempted crossing is snapped to the inner face and outward momentum dies.\n            player.setPos(x, player.getY(), z);\n            player.setDeltaMovement(vx, motion.y, vz);\n        }\n    }\n\n'''
if 'private static void confineParticipants(' not in s:
    s = s.replace(needle, method + needle)

p.write_text(s)
PY

cd "$HOT"
echo '=== hard-border source check ==='
grep -nE 'PLAYER_EDGE_MARGIN|confineParticipants|Server-authoritative invisible wall' "$RUNTIME"

echo '=== build ==='
./gradlew clean build --no-daemon
sha256sum "$JAR"

echo '=== deploy ==='
install -m 0644 "$JAR" "$MOD"
sha256sum "$MOD"
systemctl restart minecraft

for i in $(seq 1 100); do
  if ! systemctl is-active --quiet minecraft; then
    echo SERVICE_DIED
    exit 1
  fi
  if journalctl -u minecraft --since '-2 min' --no-pager | grep -q 'Done ('; then
    break
  fi
  sleep 1
done

echo '=== verify ==='
systemctl is-active minecraft
ss -ltnp | grep ':25565 '
journalctl -u minecraft --since '-3 min' --no-pager | grep -E 'brigada_hotfix|Done \(|ERROR|Exception|MixinApplyError|InjectionError|InvalidMixin' | tail -n 160 || true
! journalctl -u minecraft --since '-3 min' --no-pager | grep -Eqi 'InjectionError|InvalidMixin|MixinApplyError|Could not execute entrypoint|ModResolutionException|Exception in server tick loop|Failed to start the minecraft server'
echo HARD_BORDER_OK
