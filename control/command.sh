set -euo pipefail
sleep 25
systemctl is-active minecraft.service
systemctl show minecraft.service -p NRestarts --value
ss -ltn | grep ':25565'
journalctl -u minecraft.service --since '2026-08-25 05:46:00' --no-pager | grep -E 'Done \(|Started fake player|WorldKeeper|ERROR|Exception|Couldn.t load|failed|Can.t keep up' || true
