set -euo pipefail
echo "---- service user"
systemctl show minecraft.service -p User -p Group
echo "---- before"
namei -l /opt/minecraft/server/config/brigada-core/state.json
SERVICE_USER=$(systemctl show minecraft.service -p User --value)
SERVICE_GROUP=$(systemctl show minecraft.service -p Group --value)
test -n "$SERVICE_USER"
if [ -z "$SERVICE_GROUP" ]; then SERVICE_GROUP="$SERVICE_USER"; fi
chown -R "$SERVICE_USER:$SERVICE_GROUP" /opt/minecraft/server/config/brigada-core
chmod 0750 /opt/minecraft/server/config/brigada-core
chmod 0640 /opt/minecraft/server/config/brigada-core/state.json
sleep 8
echo "---- after"
namei -l /opt/minecraft/server/config/brigada-core/state.json
stat -c '%U:%G %a %s %y' /opt/minecraft/server/config/brigada-core/state.json
journalctl -u minecraft.service --since '-12 seconds' --no-pager
systemctl is-active minecraft.service
