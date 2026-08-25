set -euo pipefail
BUILD_DIR=$(find /opt -maxdepth 1 -type d -name 'brigada-build-*' -printf '%T@ %p
' | sort -nr | head -1 | cut -d' ' -f2-)
PACK=/opt/minecraft/resourcepack/world-ui-26.3-snapshot-9.zip
cd "$BUILD_DIR/resource-pack/WorldUI"
zip -qr "$PACK.new" .
mv "$PACK.new" "$PACK"
SHA1=$(sha1sum "$PACK" | awk '{print $1}')
sed -i "s/^resource-pack-sha1=.*/resource-pack-sha1=$SHA1/" /opt/minecraft/server/server.properties
sed -i "s/^require-resource-pack=.*/require-resource-pack=true/" /opt/minecraft/server/server.properties
systemctl restart minecraft.service
sleep 18
echo "PACK_SHA1=$SHA1"
sha256sum /opt/minecraft/server/mods/brigada-core-0.1.0.jar
systemctl is-active minecraft.service
systemctl show minecraft.service -p NRestarts --value
grep -E '^(resource-pack|resource-pack-sha1|resource-pack-id|require-resource-pack)=' /opt/minecraft/server/server.properties
journalctl -u minecraft.service --since '-2 minutes' --no-pager
