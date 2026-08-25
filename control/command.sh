set -euo pipefail
echo '=== status ==='
systemctl status minecraft.service --no-pager -l || true
echo '=== port ==='
ss -ltnp | grep ':25565 ' || true
echo '=== journal ==='
journalctl -u minecraft.service -n 260 --no-pager || true
