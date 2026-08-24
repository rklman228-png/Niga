set -euo pipefail
J=$(find /root/.gradle/caches -type f -name '*.jar' | grep -E 'minecraft.*26\.3|minecraft-merged|client-intermediary' | tail -n 1)
echo "$J"
javap -classpath "$J" net.minecraft.server.level.ServerLevel 2>/dev/null | grep -A2 -B2 'sendParticles' || true
