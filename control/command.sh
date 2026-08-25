set -euo pipefail
find /opt/minecraft/server -maxdepth 2 -type d -printf '%p
' | sort
find /opt/minecraft/server -maxdepth 2 -type f -name 'level.dat' -printf '%p
' | sort
