set -euo pipefail
echo PROJECTS
find /opt -maxdepth 4 -type f -name build.gradle -print
echo MODS
find /opt/minecraft -maxdepth 4 -type f -name '*.jar' -print 2>/dev/null | sort
echo SERVICES
systemctl list-unit-files --type=service | grep -Ei 'minecraft|fabric|paper' || true
systemctl list-units --type=service --all | grep -Ei 'minecraft|fabric|paper' || true
