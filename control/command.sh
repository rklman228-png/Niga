set -euo pipefail
sleep 8
systemctl is-active minecraft
ss -ltn 'sport = :25565'
grep -n -A55 -B2 '"activeChallenge"\|"activeExpedition"' /opt/minecraft/server/config/brigada-core/state.json || true
journalctl -u minecraft --since '5 minutes ago' --no-pager | grep -E 'ERROR|Exception|Can.t keep up|Done \(|Started fake player' || true
sha256sum /opt/minecraft/server/mods/brigada-core-0.1.0.jar
