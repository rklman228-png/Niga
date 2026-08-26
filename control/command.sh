set -euo pipefail
HOT=/opt/brigada-hotfix-src

echo '=== locate Fabric API sources/classes ==='
find /root/.gradle/caches -type f \( -name '*fabric-events-interaction*jar' -o -name '*minecraft*client*jar' -o -name '*minecraft*server*jar' \) 2>/dev/null | head -n 40

echo '=== callback signatures from caches ==='
for j in $(find /root/.gradle/caches -type f -name '*fabric-events-interaction*jar' 2>/dev/null | head -n 12); do
  echo JAR=$j
  jar tf "$j" | grep -E 'Use(Item|Block)Callback|AttackBlockCallback' || true
  javap -classpath "$j" net.fabricmc.fabric.api.event.player.UseItemCallback 2>/dev/null || true
  javap -classpath "$j" net.fabricmc.fabric.api.event.player.UseBlockCallback 2>/dev/null || true
  javap -classpath "$j" net.fabricmc.fabric.api.event.player.AttackBlockCallback 2>/dev/null || true
done

echo '=== minecraft class signatures from compile classpath ==='
cd "$HOT"
./gradlew -q dependencies --configuration compileClasspath > /tmp/brigada-deps.txt || true
find /root/.gradle/caches -type f -name '*.jar' 2>/dev/null | grep -E 'minecraft|intermediary|mapped' | head -n 80

echo '=== source text probes ==='
grep -R --include='*.java' -n 'class AbstractArrow\|class WindCharge\|FOOD' "$HOT/.gradle" /root/.gradle/caches/fabric-loom 2>/dev/null | head -n 80 || true

echo API_INSPECT_OK
