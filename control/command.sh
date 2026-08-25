set -euo pipefail
SERVER=/opt/minecraft/server
BUILD=/opt/brigada-core-src/build/libs/brigada-core-0.1.0.jar
EXPECTED=daf2150d68533b08cbb8aad8c6c69d1ccd91bc48381177f800053af148501efc
test "$(sha256sum "$BUILD" | awk '{print $1}')" = "$EXPECTED"
systemctl stop minecraft.service
install -o minecraft -g minecraft -m 0644 "$BUILD" "$SERVER/mods/brigada-core-0.1.0.jar"
systemctl start minecraft.service
sleep 72
echo '=== final'
systemctl is-active minecraft.service
systemctl show minecraft.service -p NRestarts
sha256sum "$SERVER/mods/brigada-core-0.1.0.jar"
grep -E '^(require-resource-pack|resource-pack-id|resource-pack-sha1)=' "$SERVER/server.properties"
echo '=== runtime'
journalctl -u minecraft.service -n 160 --no-pager | grep -E 'Done \(|Started fake player|WorldKeeper\[local\]|ERROR|Exception|Caused by' || true
