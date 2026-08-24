set -euo pipefail
SRC=/opt/brigada-core-src
cd "$SRC"
./gradlew --no-daemon clean build
JAR=$(find build/libs -maxdepth 1 -type f -name '*.jar' ! -name '*sources*' ! -name '*dev*' | head -n 1)
test -n "$JAR"
BACKUP="/opt/minecraft/server/backups/brigada-core-0.1.0-$(date -u +%Y%m%dT%H%M%SZ).jar"
cp /opt/minecraft/server/mods/brigada-core-0.1.0.jar "$BACKUP"
install -m 0644 "$JAR" /opt/minecraft/server/mods/brigada-core-0.1.0.jar
systemctl restart minecraft.service
sleep 12
echo STATUS
systemctl is-active minecraft.service
echo FABRIC_FILES
ls -l /opt/minecraft/server/fabric-server-launch.jar /opt/minecraft/server/mods/fabric-api-0.158.1+26.3.jar /opt/minecraft/server/mods/brigada-core-0.1.0.jar
echo PAUSE_BUTTON
unzip -p /opt/minecraft/server/mods/brigada-core-0.1.0.jar data/minecraft/tags/dialog/pause_screen_additions.json
echo SHA256
sha256sum /opt/minecraft/server/mods/brigada-core-0.1.0.jar
echo LOG
journalctl -u minecraft.service -n 160 --no-pager | grep -E 'Fabric|World Core|Done \(|ERROR|Exception' | tail -n 60
