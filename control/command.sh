set -euo pipefail
cd /opt/brigada-hotfix-src

echo '=== ServerLivingEntityEvents API ==='
find ~/.gradle/caches -type f -name '*fabric-entity-events-v1*.jar' -print -quit | while read jar; do
  echo "$jar"
  javap -classpath "$jar" net.fabricmc.fabric.api.entity.event.v1.ServerLivingEntityEvents 2>/dev/null || true
done

echo '=== mapped server classes ==='
CP=$(find ~/.gradle/caches -type f \( -name '*minecraft*merged*.jar' -o -name '*minecraft*common*.jar' -o -name '*minecraft*server*.jar' \) -print | head -n 1)
echo "cp=$CP"
if [ -n "$CP" ]; then
  javap -classpath "$CP" net.minecraft.world.entity.LivingEntity 2>/dev/null | grep -E 'fall|Fire|fire|hurtServer|setRemainingFire|clearFire|resetFall' | head -n 80 || true
  javap -classpath "$CP" net.minecraft.server.level.ServerLevel 2>/dev/null | grep -E 'playSound|Height' | head -n 80 || true
  javap -classpath "$CP" net.minecraft.sounds.SoundEvents 2>/dev/null | grep -E 'PLAYER_LEVELUP|FIREWORK_ROCKET|BEACON_ACTIVATE|EXPERIENCE_ORB_PICKUP|UI_TOAST|RAID_HORN' | head -n 80 || true
fi
