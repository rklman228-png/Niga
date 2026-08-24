#!/usr/bin/env bash
set -Eeuo pipefail
src=/opt/brigada-core-src
test -d "$src"
sed -i 's/^loom_version=.*/loom_version=1.17.19/' "$src/gradle.properties"
cd "$src"
echo "=== TOOLCHAIN ==="
grep -E '^(minecraft|loader|loom|fabric_api)_version=' gradle.properties
./gradlew --no-daemon clean build
echo "=== ARTIFACTS ==="
find build/libs -maxdepth 1 -type f -printf '%f %s bytes\n' | sort
sha256sum build/libs/*.jar
echo "BOOTSTRAP_BUILD_OK"
