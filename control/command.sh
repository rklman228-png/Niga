set -euo pipefail
systemctl is-active minecraft
ps -p $(systemctl show -p MainPID --value minecraft) -o pid,etimes,%cpu,%mem,rss,vsz,stat,cmd
journalctl -u minecraft --since '2026-08-25 06:40:00' --no-pager | grep -E 'ERROR|Exception|Can.t keep up|Done \(|Started fake player' || true
