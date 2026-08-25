set -euo pipefail
SERVER=/opt/minecraft/server
MOD="$SERVER/mods/brigada-hotfix-1.0.0.jar"
echo '=== restart minecraft.service ==='
systemctl restart minecraft.service
for i in $(seq 1 100); do
  if systemctl is-active --quiet minecraft.service && journalctl -u minecraft.service -n 140 --no-pager | grep -q 'Done ('; then break; fi
  sleep 2
done

echo '=== verify ==='
systemctl is-active minecraft.service
ss -ltnp | grep ':25565 '
sha256sum "$MOD"
journalctl -u minecraft.service -n 220 --no-pager | grep -E 'brigada_hotfix|full-height boundary|boundary restored|boundary backup|loaded boundary|Done \(' | tail -n 100 || true
if [ -f "$SERVER/brigada-boundary-backup.bin" ]; then stat -c 'boundary_backup_bytes=%s' "$SERVER/brigada-boundary-backup.bin"; else echo 'boundary_backup=none'; fi
echo FULL_HEIGHT_ENDER_EFFECTS_ACTIVE
