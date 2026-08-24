#!/usr/bin/env bash
set -Eeuo pipefail

BUILD_ROOT="/opt/minecraft-build"
SOURCE_DIR="$BUILD_ROOT/Paper"
INSTALL_DIR="/opt/minecraft/server"

export DEBIAN_FRONTEND=noninteractive

echo "Checking Java 25 toolchain..."
apt-get update -qq
if ! apt-get install -y -qq git openjdk-25-jdk-headless ca-certificates; then
  echo "ERROR: openjdk-25-jdk-headless is unavailable from configured Debian repositories." >&2
  apt-cache search '^openjdk-[0-9]+-jdk-headless$' || true
  exit 2
fi

java -version
javac -version

mkdir -p "$BUILD_ROOT" "$INSTALL_DIR"

if [[ -d "$SOURCE_DIR/.git" ]]; then
  git -C "$SOURCE_DIR" fetch --depth=1 origin dev/26.3
  git -C "$SOURCE_DIR" checkout -f FETCH_HEAD
  git -C "$SOURCE_DIR" clean -fdx
else
  rm -rf "$SOURCE_DIR"
  git clone --depth=1 --branch dev/26.3 https://github.com/PaperMC/Paper.git "$SOURCE_DIR"
fi

cd "$SOURCE_DIR"

echo "Pinned Paper source:"
git rev-parse HEAD
grep -E '^(mcVersion|apiVersion|channel|updatingMinecraft)=' gradle.properties

export GRADLE_OPTS="-Dorg.gradle.jvmargs=-Xmx4G -Dfile.encoding=UTF-8"
./gradlew --no-daemon createPaperclipJar

JAR="$(find paper-server/build/libs -maxdepth 1 -type f -name '*.jar' ! -name '*sources*' ! -name '*javadoc*' -printf '%s %p\n' | sort -nr | head -n1 | cut -d' ' -f2-)"
if [[ -z "$JAR" || ! -s "$JAR" ]]; then
  echo "ERROR: Paperclip jar not found after successful Gradle build." >&2
  find . -path '*/build/libs/*.jar' -type f -printf '%s %p\n' | sort -nr | head -n30
  exit 3
fi

install -m 0644 "$JAR" "$INSTALL_DIR/server.jar"
git rev-parse HEAD > "$INSTALL_DIR/paper-source-commit.txt"
grep -E '^(mcVersion|apiVersion|channel|updatingMinecraft)=' gradle.properties > "$INSTALL_DIR/paper-build.properties"

echo "Built server jar:"
ls -lh "$INSTALL_DIR/server.jar"
sha256sum "$INSTALL_DIR/server.jar"
cat "$INSTALL_DIR/paper-build.properties"
echo "PAPER_SNAPSHOT9_BUILD_OK"
