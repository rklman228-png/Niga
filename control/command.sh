set -u
sleep 45
printf 'SERVICE\n'
systemctl is-active minecraft.service
printf '\nPORT\n'
ss -ltnp | grep ':25565' || true
printf '\nLOG\n'
journalctl -u minecraft.service -n 180 --no-pager | grep -E 'Brigada|Done|ERROR|Exception|120|Stopping|Starting' | tail -n 60 || true
printf '\nARTIFACT\n'
sha256sum /opt/minecraft/server/mods/brigada-core-0.1.0.jar
