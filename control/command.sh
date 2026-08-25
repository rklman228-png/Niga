set -euo pipefail
build_dir=$(mktemp -d)
project_dir="$build_dir/project"
mkdir -p "$project_dir"
payload_path="$(dirname "$0")/payload.tar.gz"
test -s "$payload_path"
tar -xzf "$payload_path" -C "$project_dir"
cd "$project_dir"
/root/.gradle/wrapper/dists/gradle-9.6.1-bin/4ticwg1pgcbps2hj28r8so764/gradle-9.6.1/bin/gradle clean build --no-daemon
jar_path=$(find build/libs -maxdepth 1 -type f -name 'brigada-core-*.jar' ! -name '*sources*' | head -1)
pack_path="$project_dir/resource-pack/world-ui-26.3-snapshot-9.zip"
test -s "$jar_path"
test -s "$pack_path"
jar_sha=$(sha256sum "$jar_path" | awk '{print $1}')
pack_sha=$(sha1sum "$pack_path" | awk '{print $1}')
stamp=$(date -u +%Y%m%dT%H%M%SZ)
mkdir -p /opt/minecraft/server/backups
cp /opt/minecraft/server/mods/brigada-core-0.1.0.jar "/opt/minecraft/server/backups/brigada-core-0.1.0-$stamp.jar"
cp /opt/minecraft/resourcepack/world-ui-26.3-snapshot-9.zip "/opt/minecraft/server/backups/world-ui-26.3-snapshot-9-$stamp.zip"
install -m 0644 "$jar_path" /opt/minecraft/server/mods/brigada-core-0.1.0.jar
install -m 0644 "$pack_path" /opt/minecraft/resourcepack/world-ui-26.3-snapshot-9.zip
sed -i -E "s|^resource-pack-sha1=.*$|resource-pack-sha1=$pack_sha|" /opt/minecraft/server/server.properties
sed -i -E "s|^require-resource-pack=.*$|require-resource-pack=true|" /opt/minecraft/server/server.properties
systemctl restart minecraft
sleep 15
systemctl is-active minecraft
ss -ltnp 'sport = :25565'
served_sha=$(curl -fsSL http://127.0.0.1:8088/world-ui-26.3-snapshot-9.zip | sha1sum | awk '{print $1}')
test "$served_sha" = "$pack_sha"
printf 'jar_sha=%s\npack_sha=%s\nserved_sha=%s\n' "$jar_sha" "$pack_sha" "$served_sha"
journalctl -u minecraft --since "$stamp" --no-pager | tail -100
