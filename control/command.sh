set -euo pipefail
ps -o pid,pcpu,pmem,etime,cmd -C java
find /opt/minecraft/server -maxdepth 4 -type f \( -iname '*brigada*json' -o -iname 'state.json' \) -print
journalctl -u minecraft.service --since '2026-08-25 05:47:00' --no-pager | grep -E 'Can.t keep up|ERROR|Exception' || true
