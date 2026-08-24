set -euo pipefail
sleep 15
echo STATUS
systemctl is-active minecraft.service
echo PORT
ss -ltnp | grep ':25565' || true
echo LOG
journalctl -u minecraft.service --since '2026-08-24 23:55:15' --no-pager | tail -n 120
