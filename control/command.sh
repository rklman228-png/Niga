set -euo pipefail
systemctl is-active minecraft
ss -ltnp | grep ':25565 '
ps -p $(systemctl show -p MainPID --value minecraft) -o pid,etimes,%cpu,%mem,rss,vsz,stat,cmd
grep -E '^(resource-pack-sha1|require-resource-pack|online-mode)=' /opt/minecraft/server/server.properties
grep -F '"name": "Otezi"' /opt/minecraft/server/ops.json
journalctl -u minecraft --since '2026-08-25 07:21:00' --no-pager | grep -E 'World Core initialized|Loaded [0-9]+|Started fake player|Done \(|ERROR|Exception|Can.t keep up' || true
