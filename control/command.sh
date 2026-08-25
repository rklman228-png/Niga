set -euo pipefail
echo '=== 25565 ==='
ss -ltnp | grep ':25565 ' || true
pid=$(ss -ltnp | sed -n 's/.*:25565 .*pid=\([0-9]*\).*/\1/p' | head -n1)
echo "pid=${pid:-none}"
if [ -n "${pid:-}" ]; then
  echo '=== cgroup ==='
  cat "/proc/$pid/cgroup" || true
  echo '=== cmd ==='
  tr '\0' ' ' < "/proc/$pid/cmdline"; echo
fi
echo '=== candidate units ==='
systemctl list-units --type=service --all --no-legend | grep -Ei 'mine|java|fabric|brigada|test1' || true
echo '=== unit files ==='
systemctl list-unit-files --type=service --no-legend | grep -Ei 'mine|java|fabric|brigada|test1' || true
