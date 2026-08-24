set -euo pipefail
echo PROJECT
ls -la /opt/brigada-core-src
find /opt/brigada-core-src -maxdepth 3 -type f \( -name 'gradlew' -o -name 'gradle-wrapper.properties' -o -name 'build.gradle' \) -print
echo GRADLE
find /root/.gradle /opt /usr/local /usr -type f -path '*/bin/gradle' -perm -u+x 2>/dev/null | head -30
find /root/.gradle/wrapper/dists -maxdepth 5 -type f -name gradle 2>/dev/null | head -30
