set -euo pipefail
find /opt /usr/local -type f -path '*/bin/gradle' -perm -u+x 2>/dev/null | head -20
find /opt/minecraft -maxdepth 3 -type f \( -name 'gradle' -o -name 'gradlew' -o -name 'brigada-core-*.jar' \) -print 2>/dev/null | head -30
java -version
systemctl is-active minecraft
