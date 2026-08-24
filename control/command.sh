set -euo pipefail
systemctl --no-pager --full status minecraft.service || true
printf '\n=== FINAL STARTUP ===\n'
journalctl -u minecraft.service --since '2026-08-24 21:21:45' --no-pager -o cat | tail -n 320
printf '\n=== PORT ===\n'
ss -ltnp | grep ':25565' || true
