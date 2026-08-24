#!/usr/bin/env bash
set -Eeuo pipefail

work=/tmp/brigada-meta
mkdir -p "$work"

curl -fsSL --max-time 60 'https://maven.fabricmc.net/net/fabricmc/fabric-loom/maven-metadata.xml' -o "$work/loom.xml"
curl -fsSL --max-time 60 'https://maven.fabricmc.net/net/fabricmc/fabric-api/fabric-api/maven-metadata.xml' -o "$work/fapi.xml"

echo "=== LOOM LATEST ==="
grep -E '<latest>|<release>|<version>1\.(17|18|19)' "$work/loom.xml" | tail -n 60

echo "=== FABRIC API 26.3 ==="
grep -E '<version>.*26\.3' "$work/fapi.xml" | tail -n 40

echo "=== EXAMPLE BUILD ==="
curl -fsSL --max-time 60 'https://raw.githubusercontent.com/FabricMC/fabric-example-mod/26.2/build.gradle' | sed -n '1,240p'
echo "=== EXAMPLE PROPS ==="
curl -fsSL --max-time 60 'https://raw.githubusercontent.com/FabricMC/fabric-example-mod/26.2/gradle.properties' | sed -n '1,200p'
echo "=== EXAMPLE SETTINGS ==="
curl -fsSL --max-time 60 'https://raw.githubusercontent.com/FabricMC/fabric-example-mod/26.2/settings.gradle' | sed -n '1,160p'
echo "META_OK"
