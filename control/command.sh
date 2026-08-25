set -euo pipefail
systemctl is-active minecraft
ss -ltnp | grep ':25565 '
ps -p $(systemctl show -p MainPID --value minecraft) -o pid,etimes,%cpu,%mem,rss,vsz,stat,cmd
sha256sum /opt/minecraft/server/mods/brigada-core-0.1.0.jar
sha1sum /opt/minecraft/resourcepack/world-ui-26.3-snapshot-9.zip
journalctl -u minecraft --since '2026-08-25 07:32:20' --no-pager | grep -E 'World Core initialized|Loaded [0-9]+|Started fake player|Done \(|ERROR|Exception|Can.t keep up' || true
