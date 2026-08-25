set -euo pipefail
cd /opt/brigada-core-src
git pull --ff-only origin main
./gradlew clean build --no-daemon
find build/libs -maxdepth 1 -type f -name '*.jar' -printf '%f %s bytes\n'
sha256sum build/libs/*.jar
