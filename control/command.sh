set -euo pipefail

echo '=== health ==='
systemctl is-active minecraft
ss -ltnp | grep ':25565 '

echo '=== latest warnings/errors ==='
journalctl -u minecraft --since '2026-08-25 14:37:20' --no-pager | grep -Ei 'Can.t keep up|WARN|ERROR|Exception|crash|brigada_hotfix' | tail -n 120 || true

echo '=== process ==='
ps -p "$(systemctl show minecraft -p MainPID --value)" -o pid,etime,%cpu,%mem,rss,vsz,cmd

echo HEALTH_OK
