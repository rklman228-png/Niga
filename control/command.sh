set -euo pipefail
MARK=$(date -u '+%Y-%m-%d %H:%M:%S')
sleep 35
echo "SINCE=$MARK"
journalctl -u minecraft.service --since "$MARK" --no-pager | grep -E 'ERROR|Exception|AccessDenied|Can.t keep up' || true
systemctl is-active minecraft.service
systemctl show minecraft.service -p NRestarts --value
ps -o pid,%cpu,%mem,rss,etime,cmd -p "$(systemctl show minecraft.service -p MainPID --value)"
