set -euo pipefail
cd /opt/brigada-core-src
git fetch origin main
git checkout main
git merge --ff-only origin/main
./gradlew --no-daemon clean build
install -m 0644 build/libs/brigada-core-0.1.0.jar /opt/minecraft/server/mods/brigada-core-0.1.0.jar
PACK=/opt/minecraft/server-resource-pack/world-ui-26.3-snapshot-9.zip
cd /opt/brigada-core-src/resource-pack/WorldUI
zip -qr "$PACK.new" .
mv "$PACK.new" "$PACK"
SHA1=$(sha1sum "$PACK" | awk '{print $1}')
sed -i "s/^resource-pack-sha1=.*/resource-pack-sha1=$SHA1/" /opt/minecraft/server/server.properties
sed -i "s/^require-resource-pack=.*/require-resource-pack=true/" /opt/minecraft/server/server.properties
systemctl restart minecraft.service
sleep 15
echo "PACK_SHA1=$SHA1"
sha256sum /opt/minecraft/server/mods/brigada-core-0.1.0.jar
systemctl is-active minecraft.service
systemctl show minecraft.service -p NRestarts --value
journalctl -u minecraft.service -n 100 --no-pager
