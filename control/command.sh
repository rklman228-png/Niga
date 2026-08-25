set -euo pipefail
for i in $(seq 1 120); do
  if ss -ltnp | grep -q ':25565 '; then break; fi
  sleep 2
done
echo '=== readiness ==='
systemctl is-active minecraft.service
ss -ltnp | grep ':25565 '
echo '=== new process journal ==='
journalctl -u minecraft.service --since '2026-08-25 18:20:50 UTC' --no-pager | tail -n 180
if [ -f /opt/minecraft/server/brigada-boundary-backup.bin ]; then stat -c 'boundary_backup_bytes=%s' /opt/minecraft/server/brigada-boundary-backup.bin; else echo 'boundary_backup=none'; fi
sha256sum /opt/minecraft/server/mods/brigada-hotfix-1.0.0.jar
echo READY_CHECK_OK
