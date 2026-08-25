set -euo pipefail
sleep 20
echo '=== status'
systemctl is-active minecraft.service
systemctl show minecraft.service -p MainPID -p NRestarts
echo '=== recent'
journalctl -u minecraft.service --since '2026-08-25 01:51:40' --no-pager
echo '=== process'
ps -o pid,etime,%cpu,%mem,cmd -p "$(systemctl show -p MainPID --value minecraft.service)"
