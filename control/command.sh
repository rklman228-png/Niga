set -euo pipefail
find /opt/minecraft/server/world/players -maxdepth 2 -type f -printf '%f
' | sort
