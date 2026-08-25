set -euo pipefail
BUILD_DIR=/opt/brigada-build-n0QScY
PACK_DIR=$(mktemp -d /opt/brigada-pack-XXXXXX)
(cd "$BUILD_DIR/resource-pack/WorldUI" && zip -qr "$PACK_DIR/world-ui.zip" .)
PACK_SHA1=$(sha1sum "$PACK_DIR/world-ui.zip" | awk '{print $1}')
systemctl stop minecraft.service
cp -a /opt/minecraft/server/mods/brigada-core-0.1.0.jar /opt/minecraft/server/mods/brigada-core-0.1.0.jar.previous
install -m 0644 "$BUILD_DIR/build/libs/brigada-core-0.1.0.jar" /opt/minecraft/server/mods/brigada-core-0.1.0.jar
install -m 0644 "$PACK_DIR/world-ui.zip" /opt/minecraft/resourcepack/world-ui-26.3-snapshot-9.zip
sed -i -E "s/^resource-pack-sha1=.*/resource-pack-sha1=$PACK_SHA1/" /opt/minecraft/server/server.properties
sed -i -E 's/^require-resource-pack=.*/require-resource-pack=true/' /opt/minecraft/server/server.properties
systemctl start minecraft.service
sleep 55
echo "PACK_SHA1=$PACK_SHA1"
systemctl is-active minecraft.service
systemctl show minecraft.service -p NRestarts --value
sha256sum /opt/minecraft/server/mods/brigada-core-0.1.0.jar
sha1sum /opt/minecraft/resourcepack/world-ui-26.3-snapshot-9.zip
journalctl -u minecraft.service --since '-90 seconds' --no-pager | grep -E 'Done \(|World Core initialized|WorldKeeper|ERROR|Exception|Unknown|Missing|tag|Tag|failed|Can.t keep up' || true
