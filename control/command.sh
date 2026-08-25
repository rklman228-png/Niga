set -euo pipefail
cd /opt/brigada-core-src
pack_dir=$(mktemp -d /tmp/world-ui-build-XXXXXX)
pack_tmp="$pack_dir/world-ui-26.3-snapshot-9.zip"
(cd resource-pack/WorldUI && zip -qr "$pack_tmp" .)
install -m 0644 "$pack_tmp" /opt/minecraft/resourcepack/world-ui-26.3-snapshot-9.zip
pack_sha=$(sha1sum /opt/minecraft/resourcepack/world-ui-26.3-snapshot-9.zip | cut -d' ' -f1)
sed -i "s|^resource-pack-sha1=.*|resource-pack-sha1=$pack_sha|" /opt/minecraft/server/server.properties
systemctl stop minecraft.service
install -m 0644 build/libs/brigada-core-0.1.0.jar /opt/minecraft/server/mods/brigada-core-0.1.0.jar
systemctl start minecraft.service
sleep 50
systemctl is-active minecraft.service
systemctl show minecraft.service -p NRestarts --value
printf 'jar '; sha256sum /opt/minecraft/server/mods/brigada-core-0.1.0.jar
printf 'pack '; sha1sum /opt/minecraft/resourcepack/world-ui-26.3-snapshot-9.zip
curl -fsS http://127.0.0.1:8088/world-ui-26.3-snapshot-9.zip | sha1sum
journalctl -u minecraft.service --since '2 minutes ago' --no-pager | grep -E 'Done \(|World Core|WorldKeeper|ERROR|Exception|Couldn.t load|failed' || true
