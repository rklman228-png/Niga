#!/usr/bin/env bash
set -Eeuo pipefail

echo "=== HOST ==="
date -u
uname -a
java -version 2>&1
command -v gradle || true
gradle --version 2>&1 | sed -n '1,30p' || true
find /opt -maxdepth 3 -type f \( -name 'gradle' -o -name 'gradlew' \) -print 2>/dev/null | sed -n '1,30p'

echo "=== SERVER ==="
systemctl is-active minecraft
find /opt/minecraft/server/mods -maxdepth 1 -type f -printf '%f\n' | sort
sha1sum /opt/minecraft/server/server.jar
df -h /opt

echo "=== FABRIC META ==="
curl -fsSL --max-time 30 'https://meta.fabricmc.net/v2/versions/yarn/26.3-snapshot-9' | head -c 12000
printf '\n'
curl -fsSL --max-time 30 'https://meta.fabricmc.net/v2/versions/loader/26.3-snapshot-9' | head -c 16000
printf '\n'
curl -fsSL --max-time 30 'https://maven.fabricmc.net/net/fabricmc/fabric-loom/maven-metadata.xml' | tail -n 80
echo "INSPECT_OK"
