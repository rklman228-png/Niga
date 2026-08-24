set -euo pipefail
find /root/.gradle/caches -type f -name '*.jar' | grep -E 'fabric-entity-events|fabric-events-interaction|fabric-lifecycle-events' | tail -n 20
printf '\nSERVER_EVENTS\n'
for J in $(find /root/.gradle/caches -type f -name '*.jar' | grep 'fabric-entity-events' | tail -n 5); do
  echo "$J"
  jar tf "$J" | grep -E 'ServerLivingEntityEvents|Player.*Item|Pickup' || true
done
