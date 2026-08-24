#!/usr/bin/env bash
set -Eeuo pipefail

SERVER="/opt/minecraft/server"
ZIP="/root/uploads/Писькострелковая_бригада_13.zip"
JAR_URL="https://piston-data.mojang.com/v1/objects/9580afcd37c63cb01e81d5d9f836f21b4d21c540/server.jar"
JAR_SHA1="9580afcd37c63cb01e81d5d9f836f21b4d21c540"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl unzip openjdk-25-jre-headless ca-certificates

echo "=== DOWNLOAD OFFICIAL 26.3 SNAPSHOT 9 SERVER ==="
systemctl stop minecraft 2>/dev/null || true
mkdir -p "$SERVER"
curl -fL --retry 5 --retry-delay 2 "$JAR_URL" -o "$SERVER/server.jar"
cd "$SERVER"
echo "$JAR_SHA1  server.jar" | sha1sum -c -
echo "vanilla-26.3-snapshot-9" > "$SERVER/server-core.txt"

echo "=== INSTALL WORLD ==="
TMP="$(mktemp -d /tmp/mcworld.XXXXXX)"
unzip -q "$ZIP" -d "$TMP"
WORLD_SRC="$(find "$TMP" -type f -name level.dat -printf '%h\n' | head -n1)"
if [[ -z "$WORLD_SRC" ]]; then
  echo "ERROR: level.dat not found in archive" >&2
  exit 10
fi

if [[ -d "$SERVER/world" ]]; then
  mv "$SERVER/world" "$SERVER/world.backup.$(date +%Y%m%d-%H%M%S)"
fi
mkdir -p "$SERVER/world"
cp -a "$WORLD_SRC"/. "$SERVER/world"/

cat > "$SERVER/eula.txt" <<'EOF'
eula=true
EOF

cat > "$SERVER/server.properties" <<'EOF'
level-name=world
server-ip=
server-port=25565
motd=Писькострелковая бригада №13 | 26.3 Snapshot 9
online-mode=false
enforce-secure-profile=false
white-list=true
enforce-whitelist=true
max-players=20
view-distance=10
simulation-distance=8
spawn-protection=0
enable-status=true
enable-rcon=false
enable-query=false
EOF

cat > "$SERVER/whitelist.json" <<'EOF'
[
  {"uuid":"d5c369db-55e6-30e8-aac1-b9f9bdb92beb","name":"Otezi"},
  {"uuid":"2861cdcd-c1dd-3e01-818b-aacb305d5df3","name":"dochholodilnika"},
  {"uuid":"ef3ced57-6d17-3c35-aca7-aa47e5aefb4b","name":"dochholodilnikagopgop"}
]
EOF

id minecraft >/dev/null 2>&1 || useradd --system --home "$SERVER" --shell /usr/sbin/nologin minecraft
chown -R minecraft:minecraft "$SERVER"

cat > /etc/systemd/system/minecraft.service <<'EOF'
[Unit]
Description=Minecraft 26.3 Snapshot 9
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=minecraft
Group=minecraft
WorkingDirectory=/opt/minecraft/server
ExecStart=/usr/bin/java -Xms2G -Xmx5G -jar server.jar nogui
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

if command -v ufw >/dev/null && ufw status | grep -q 'Status: active'; then
  ufw allow 25565/tcp
fi

echo "=== WAIT FOR STARTUP ==="
for i in $(seq 1 240); do
  if grep -q 'Done (' "$SERVER/logs/latest.log" 2>/dev/null; then
    break
  fi
  if ! systemctl is-active --quiet minecraft; then
    break
  fi
  sleep 1
done

echo "=== VERIFY ==="
systemctl --no-pager --full status minecraft || true
echo
ss -ltnp | grep ':25565' || true
echo
tail -n 120 "$SERVER/logs/latest.log" 2>/dev/null || journalctl -u minecraft -n 120 --no-pager
echo
sha1sum "$SERVER/server.jar"
cat "$SERVER/server-core.txt"
grep -E '^(online-mode|white-list|enforce-whitelist|level-name|server-port)=' "$SERVER/server.properties"
echo "SNAPSHOT9_SERVER_DEPLOY_COMMAND_FINISHED"
