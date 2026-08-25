set -euo pipefail
HOT=/opt/brigada-hotfix-src
RUNTIME="$HOT/src/main/java/dev/brigada13/hotfix/RuntimeFixes.java"
JAR="$HOT/build/libs/brigada-hotfix-0.1.0.jar"
MOD=/opt/minecraft/server/mods/brigada-hotfix-1.0.0.jar

python3 - <<'PY'
from pathlib import Path
p = Path('/opt/brigada-hotfix-src/src/main/java/dev/brigada13/hotfix/RuntimeFixes.java')
s = p.read_text()
s = s.replace('player.setPos(x, player.getY(), z);', 'player.teleportTo(x, player.getY(), z);')
s = s.replace('// Server-authoritative invisible wall: the player can touch the marked perimeter,\n            // but every attempted crossing is snapped to the inner face and outward momentum dies.',
              '// Hard invisible wall: teleportTo sends an immediate correction to the owning client,\n            // so crossing never becomes an accepted player position; outward momentum is cancelled too.')
p.write_text(s)
PY

cd "$HOT"
echo '=== teleport border source check ==='
grep -nE 'confineParticipants|teleportTo\(x|Hard invisible wall' "$RUNTIME"

echo '=== incremental build ==='
./gradlew build --no-daemon
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
echo HARD_BORDER_TELEPORT_OK
