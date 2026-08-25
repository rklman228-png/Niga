set -euo pipefail
systemctl cat minecraft.service
find /opt/minecraft -maxdepth 3 -type f -name server.properties -print
find /opt/minecraft -maxdepth 3 -type d -name mods -print
systemctl is-active minecraft.service
