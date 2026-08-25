set -euo pipefail
work_dir=$(mktemp -d /opt/brigada-build.XXXXXX)
cp /opt/actions-runner/_work/Niga/Niga/control/payload.part00 "$work_dir/source-min.tar.gz"
dd if=/opt/actions-runner/_work/Niga/Niga/control/payload.part01 of="$work_dir/source-min.tar.gz" bs=240000 seek=1 conv=notrunc status=none
dd if=/opt/actions-runner/_work/Niga/Niga/control/payload.part02 of="$work_dir/source-min.tar.gz" bs=240000 seek=2 conv=notrunc status=none
echo "e08775d86007d6a859788512dd4b13e7fd7bd5fc046266e39877c18e250c789a  $work_dir/source-min.tar.gz" | sha256sum -c -
mkdir "$work_dir/source"
tar -xzf "$work_dir/source-min.tar.gz" -C "$work_dir/source"
gradle_bin=/root/.gradle/wrapper/dists/gradle-9.6.1-bin/4ticwg1pgcbps2hj28r8so764/gradle-9.6.1/bin/gradle
cd "$work_dir/source"
"$gradle_bin" --no-daemon clean build
jar_file=$(find build/libs -maxdepth 1 -type f -name '*.jar' ! -name '*-sources.jar' | head -n 1)
test -n "$jar_file"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
cp /opt/minecraft/server/mods/brigada-core-0.1.0.jar "/opt/minecraft/server/mods/brigada-core-0.1.0.jar.backup-$stamp"
systemctl stop minecraft
cp "$jar_file" /opt/minecraft/server/mods/brigada-core-0.1.0.jar
systemctl start minecraft
for attempt in $(seq 1 30); do
  if systemctl is-active --quiet minecraft && ss -ltn | grep -q ':25565 '; then break; fi
  sleep 2
done
systemctl is-active minecraft
ss -ltnp | grep ':25565 '
sha256sum /opt/minecraft/server/mods/brigada-core-0.1.0.jar
journalctl -u minecraft -n 100 --no-pager | grep -E 'World Core initialized|Loaded [0-9]+|Started fake player|Done \(|ERROR|Exception' || true
