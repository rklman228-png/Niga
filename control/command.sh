set -euo pipefail
echo STATUS
systemctl is-active minecraft.service
echo PORT
ss -ltnp | grep ':25565' || true
echo SHA256
sha256sum /opt/minecraft/server/mods/brigada-core-0.1.0.jar
echo PAUSE_BUTTON
unzip -p /opt/minecraft/server/mods/brigada-core-0.1.0.jar data/minecraft/tags/dialog/pause_screen_additions.json
echo READY
journalctl -u minecraft.service --since '2026-08-24 23:58:00' --no-pager | grep -E 'Loading Minecraft|brigada_core|fabric-api|World Core initialized|Done \(|ERROR|Exception|Starting Minecraft server on' | tail -n 80
