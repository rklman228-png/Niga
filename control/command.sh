set -euo pipefail
SRC=/opt/brigada-core-src
printf '%s' 'iVBORw0KGgoAAAANSUhEUgAAAIAAAAAQCAYAAADeWHeIAAAEXklEQVR42u1Y3WtURxT/rd1WV4gkFiEr3oW7FPLgBs26LpKKiKRxm6ppHxY1KOLDLUT6BzSGrnSL1EcfSoXcBxFLjCyi23w02hAasUHajVGSF6FkIVuSgMQNCZiIyPiwzO7c2Zn7sR+2Sn6w7L1zzsydOb9zzpwZYB3rAIArZJGEp1LESs+rqOTW2H1iJjf7rVv67cLK5hvoQ9wXwtmACjMn8Coq+emXa/jm1JnKO+CJB8TuAmS6lcBEOEhKkVUrAModa0avNZW76cN8Ju2K+0IkNpsCplLkr8aQS0b+fCbtEg22OtxkY1JNxBOZdPGEHu9pQGdfMfGx2RTivhBhv3m8pwHAA9LZt99VjUiZCAfJkfmsQT7grTPoyWwAAIfqPxS2jy68KilKE+cOFrVFf/7D9pq8ikpk83WzLzInsCKfXcChHz/Ot4/3BgAAzR3TBSN0LRYZsbNvv4uSz44Vm00BAJShBNAWzS9i65ZtLicGlIFfi9awGVguEB68fQAA8Oir+wYd/emLimeeke8+L2pr+eE3Rw5s5pQyfbfIKKwTZNqisIp8HoP9NwAAWQDplsMYHLkLAPji6Elbk6PEs1CGElAAkmmLCueR1OodGbxdX5DK/g1uBAAEufcdj17aGvu81iLOAA4IFUV84tzB/L+It9XhJuLXlorS/4xeC79WCJIZvRY0C2+QRUbcF0Ip5FezYKGOINNTlU1QlU3SvlZylmwAWJsaw9rUmFBmBTZ67UYy1RPpU9JF5FN4IpOuGb0W9MfXAvTHbsFuswmVUvCN9wZAd8+dO8MY8NYh3XIY6shdjPcGDAa1G/0sZBkAANKZNWmEJ7V6g1yE7699Jmw/1sg8A9D3JR2ldFF6N+tjV18Ev7aUJ3+1+R7qVi4iW9MNz3hrXi6tAfhIpOTnBswVeH5tyVE2CN4+YNhDy4l+MzSGOXJ1YO5hOwBg+76kUF5tDPz6BABw5NiussaxU/Cx2duvqYQ6Qbam2+AcPHdulgA2bVBlr6IS3mvMCo7mjmkM9hfeszXdUEe687LRrupEf0/PimlfKzkAXDjzO/Z8siX/3vplzmnu3SlsGxP/LDtK/wBw+cmc4z6lFn48j/w24NeMfdxs9PFEs5Uy1Ulq9aYFVKmgxacylAAAnA2ojsfoOKqgtz9Ttk41axieNKs+sU+vS2XxP0+bnvtp2uflnoggA9Aqul1fEEYZzQZ2DEGr/bmH7cDKRcMx0PJY1hYlylACV6fTBkdgo//58jNy8+un4O8BeGK3C/bqapGfLzTju03l6dhjYWEry3hOIDsF8MG9Oly4i3FXKnrpJc9o16Khis6d/c3P32aI+0JFbSLyeXy794PSbgKZFN+Kj2yn/f/DlS9/wUZrAX7v90RM7gHKOT97IpOWWcKKfDYL0Ajg+4jIv/T367KNyF/w6NoLvCtwekyn+m47xJb6Eae4ciJ3vUudwO73KjGvt3HP8d84RRN5H9e2jgoVpm8AhuN4/hiorowAAAAASUVORK5CYII=' | base64 -d > "$SRC/resource-pack/WorldUI/assets/brigada_core/textures/font/icons.png"
cd "$SRC"
python3 -m json.tool src/main/resources/data/brigada_core/dialog/main.json >/dev/null
python3 -m json.tool src/main/resources/data/brigada_core/dialog/challenges.json >/dev/null
./gradlew --no-daemon build
JAR=$(find build/libs -maxdepth 1 -type f -name '*.jar' ! -name '*sources*' ! -name '*dev*' | head -n 1)
test -n "$JAR"
cp /opt/minecraft/server/mods/brigada-core-0.1.0.jar "/opt/minecraft/server/backups/brigada-core-0.1.0-$(date -u +%Y%m%dT%H%M%SZ).jar"
install -m 0644 "$JAR" /opt/minecraft/server/mods/brigada-core-0.1.0.jar

PACK=/opt/minecraft/resourcepack/world-ui-26.3-snapshot-9.zip
TMP_PACK=/opt/minecraft/resourcepack/world-ui-26.3-snapshot-9.zip.new
(
  cd resource-pack/WorldUI
  zip -X -q -r "$TMP_PACK" .
)
PACK_SHA1=$(sha1sum "$TMP_PACK" | awk '{print $1}')
mv "$TMP_PACK" "$PACK"
sed -i "s/^resource-pack-sha1=.*/resource-pack-sha1=$PACK_SHA1/" /opt/minecraft/server/server.properties
sed -i 's/^resource-pack-id=.*/resource-pack-id=91fe1bb7-32c5-4207-b2d8-5ddfb82f89d5/' /opt/minecraft/server/server.properties

systemctl restart minecraft.service
sleep 70
echo BUILD_AND_PACK
sha256sum /opt/minecraft/server/mods/brigada-core-0.1.0.jar
sha1sum "$PACK"
unzip -p "$PACK" assets/brigada_core/font/icons.json
unzip -l "$PACK" | grep 'textures/font/icons.png'
echo PROPERTIES
grep -E '^(resource-pack|resource-pack-id|resource-pack-sha1)' /opt/minecraft/server/server.properties
echo STATUS
systemctl is-active minecraft.service
ss -ltnp | grep ':25565' || true
echo READY
journalctl -u minecraft.service -n 220 --no-pager | grep -E 'Loading Minecraft|brigada_core|World Core initialized|Done \(|ERROR|Exception' | tail -n 50
