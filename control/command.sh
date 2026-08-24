set -euo pipefail
printf 'STATE\n'
cat /opt/minecraft/server/config/brigada-core/state.json 2>/dev/null || true
printf '\nDEATH_LOGS\n'
journalctl -u minecraft.service --since '2026-08-24 23:30:00' --no-pager | grep -Ei 'died|slain|fell|burned|death|Otezi|doch|lost|World Core|Exception|ERROR' | tail -n 160 || true
printf '\nPLAYERS\n'
journalctl -u minecraft.service --since '2026-08-24 23:30:00' --no-pager | grep -E 'joined the game|left the game|logged in' | tail -n 80 || true
printf '\nWORLD_ITEMS\n'
find /opt/minecraft/server/world -maxdepth 2 -type f -printf '%p %s\n' | sort | tail -n 30
printf '\nPACK_HTTP_LOG\n'
journalctl -u brigada-pack.service --since '2026-08-24 23:30:00' --no-pager | tail -n 80 || true
