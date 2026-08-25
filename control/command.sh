set -euo pipefail
find /opt/minecraft -type d -name playerdata -print 2>/dev/null
find /opt/minecraft -type f -path '*/playerdata/*.dat' -printf '%p
' 2>/dev/null | sort
systemctl show minecraft.service -p WorkingDirectory -p User
