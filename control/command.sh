set -euo pipefail
printf 'LEVEL_NAME\n'
grep '^level-name=' /opt/minecraft/server/server.properties || true
printf '\nWORLD_TARGETS\n'
find /opt/minecraft/server -maxdepth 1 -mindepth 1 -type d -printf '%f\n' | sort
printf '\nSIZES\n'
du -sh /opt/minecraft/server/world* 2>/dev/null || true
printf '\nSTATE\n'
ls -lh /opt/minecraft/server/config/brigada-core/state.json 2>/dev/null || true
printf '\nSERVICE\n'
systemctl is-active minecraft.service
