set -euo pipefail
sleep 8
systemctl --no-pager --full status minecraft.service || true
printf '\n=== STARTUP CHECK ===\n'
journalctl -u minecraft.service --since '2026-08-24 21:21:00' --no-pager -o cat | grep -E 'Brigada|Loaded [0-9]+ .*challenges|Done|ERROR|WARN|Failed|Exception|Could not|dialog|quick_actions' | tail -n 220 || true
printf '\n=== PORT ===\n'
ss -ltnp | grep ':25565' || true
