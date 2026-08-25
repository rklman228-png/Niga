set -euo pipefail
find /opt/minecraft/server/world/players -maxdepth 3 -printf '%y %p
' | sort
