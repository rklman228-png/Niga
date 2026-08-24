#!/usr/bin/env bash
set -Eeuo pipefail

SERVER="/opt/minecraft/server"
INSTALLER_URL="https://maven.fabricmc.net/net/fabricmc/fabric-installer/1.1.2/fabric-installer-1.1.2.jar"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl openjdk-25-jre-headless ca-certificates

echo "=== STOP CURRENT SERVER ==="
systemctl stop minecraft
cd "$SERVER"

if [[ ! -f server.jar.vanilla-26.3-snapshot-9 ]]; then
  cp -a server.jar server.jar.vanilla-26.3-snapshot-9
fi

echo "=== INSTALL OFFICIAL FABRIC SERVER ==="
curl -fL --retry 5 --retry-delay 2 "$INSTALLER_URL" -o fabric-installer-1.1.2.jar
java -jar fabric-installer-1.1.2.jar server -mcversion 26.3-snapshot-9 -downloadMinecraft

test -s fabric-server-launch.jar
mkdir -p mods
echo "fabric-26.3-snapshot-9-server-only" > server-core.txt
chown -R minecraft:minecraft "$SERVER"

cat > /etc/systemd/system/minecraft.service <<'EOF'
[Unit]
Description=Minecraft Fabric 26.3 Snapshot 9
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=minecraft
Group=minecraft
WorkingDirectory=/opt/minecraft/server
ExecStart=/usr/bin/java -Xms2G -Xmx5G -jar fabric-server-launch.jar nogui
Restart=on-failure
RestartSec=10
SuccessExitStatus=0 143
TimeoutStopSec=120
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now minecraft

echo "=== WAIT FOR FABRIC STARTUP ==="
for i in $(seq 1 240); do
  if grep -q 'Done (' "$SERVER/logs/latest.log" 2>/dev/null; then
    break
  fi
  if ! systemctl is-active --quiet minecraft; then
    break
  fi
  sleep 1
done

echo "=== VERIFY FABRIC ==="
systemctl is-active minecraft
systemctl is-enabled minecraft
ss -ltnp | grep ':25565'
grep -Ei 'fabric loader|loading minecraft|Starting minecraft server version|Done \(' "$SERVER/logs/latest.log" | tail -n 20 || true
echo "mods_count=$(find "$SERVER/mods" -maxdepth 1 -type f -name '*.jar' | wc -l)"
cat "$SERVER/server-core.txt"
grep -E '^(online-mode|white-list|enforce-whitelist|level-name|server-port)=' "$SERVER/server.properties"
cat "$SERVER/whitelist.json"
echo "FABRIC_SNAPSHOT9_SERVER_READY"
