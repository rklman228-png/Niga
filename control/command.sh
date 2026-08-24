#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_DIR="/opt/minecraft-build/Paper"
SERVER="/opt/minecraft/server"
ZIP="/root/uploads/Писькострелковая_бригада_13.zip"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq git curl unzip openjdk-25-jdk-headless ca-certificates

echo "=== BUILD PAPER LOCALLY ON VPS ==="
cd "$SOURCE_DIR"
git reset --hard
git clean -fdx
if [[ "$(git rev-parse --is-shallow-repository)" == "true" ]]; then
  echo "Fetching missing Paper history..."
  git fetch --unshallow --tags origin
fi
git fetch origin dev/26.3
git checkout -f origin/dev/26.3
git clean -fdx

echo "Paper source commit:"
git rev-parse HEAD
grep -E '^(mcVersion|apiVersion|channel|updatingMinecraft)=' gradle.properties

export GRADLE_OPTS="-Dorg.gradle.jvmargs=-Xmx4G -Dfile.encoding=UTF-8"
./gradlew --no-daemon applyPatches
./gradlew --no-daemon createPaperclipJar

JAR="$(find paper-server/build/libs -maxdepth 1 -type f -name '*.jar' ! -name '*sources*' ! -name '*javadoc*' ! -name '*dev-bundle*' -printf '%s %p\n' | sort -nr | head -n1 | cut -d' ' -f2-)"
test -n "$JAR"
test -s "$JAR"

echo "=== DEPLOY SERVER ==="
systemctl stop minecraft 2>/dev/null || true
mkdir -p "$SERVER"
install -m 0644 "$JAR" "$SERVER/server.jar"
git rev-parse HEAD > "$SERVER/paper-source-commit.txt"
grep -E '^(mcVersion|apiVersion|channel|updatingMinecraft)=' gradle.properties > "$SERVER/paper-build.properties"

TMP="$(mktemp -d /tmp/mcworld.XXXXXX)"
unzip -q "$ZIP" -d "$TMP"
WORLD_SRC="$(find "$TMP" -type f -name level.dat -printf '%h\n' | head -n1)"
if [[ -z "$WORLD_SRC" ]]; then
  echo "ERROR: level.dat not found in world archive" >&2
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
Description=Minecraft Paper 26.3 Snapshot 9
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

echo "Waiting for server startup..."
for i in $(seq 1 180); do
  if grep -q 'Done (' "$SERVER/logs/latest.log" 2>/dev/null; then
    break
  fi
  if ! systemctl is-active --quiet minecraft; then
    break
  fi
  sleep 1
done

echo "=== RESULT ==="
systemctl is-active minecraft
ss -ltnp | grep ':25565'
tail -n 80 "$SERVER/logs/latest.log"
sha256sum "$SERVER/server.jar"
cat "$SERVER/paper-build.properties"
echo "PAPER_SNAPSHOT9_SERVER_READY"
