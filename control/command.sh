set -euo pipefail
J=/root/.gradle/caches/modules-2/files-2.1/net.fabricmc.fabric-api/fabric-entity-events-v1/6.0.3+3434d6d97a/18fcb4e5e6c7576cc5390732a50c677a124a41bd/fabric-entity-events-v1-6.0.3+3434d6d97a.jar
javap -classpath "$J" 'net.fabricmc.fabric.api.entity.event.v1.ServerLivingEntityEvents$AllowDeath'
javap -classpath "$J" 'net.fabricmc.fabric.api.entity.event.v1.ServerLivingEntityEvents$AfterDeath'
printf '\nPICKUP_CANDIDATES\n'
find /root/.gradle/caches/modules-2/files-2.1/net.fabricmc.fabric-api -type f -name '*.jar' -print0 | while IFS= read -r -d '' F; do
  if jar tf "$F" | grep -qiE 'pickup.*item|item.*pickup'; then
    echo "$F"
    jar tf "$F" | grep -iE 'pickup.*item|item.*pickup'
  fi
done
