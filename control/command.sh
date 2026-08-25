set -euo pipefail
(printf '%s' "$(sed -n '1p' control/payload-00.b64)"; printf '%s' "$(sed -n '1p' control/payload-01.b64)"; printf '%s' "$(sed -n '1p' control/payload-02.b64)") | base64 -d > /tmp/brigada-full.tar.gz
mkdir -p /opt/brigada-core-src
tar -xzf /tmp/brigada-full.tar.gz -C /opt/brigada-core-src
cd /opt/brigada-core-src
./gradlew clean build --no-daemon
find build/libs -maxdepth 1 -type f -name '*.jar' -printf '%f %s bytes\n'
sha256sum build/libs/*.jar
