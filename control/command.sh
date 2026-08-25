set -euo pipefail

echo '=== 8088 listener ==='
ss -ltnp | grep ':8088 ' || true
pid=$(ss -ltnp | sed -n 's/.*:8088 .*pid=\([0-9]*\).*/\1/p' | head -n1)
if [ -n "${pid:-}" ] && [ -d "/proc/$pid" ]; then
  echo "pid=$pid"
  printf 'cmd='; tr '\0' ' ' < "/proc/$pid/cmdline"; echo
  printf 'cwd='; readlink -f "/proc/$pid/cwd" || true
  printf 'root='; readlink -f "/proc/$pid/root" || true
fi

echo '=== served pack ==='
curl -fsS http://127.0.0.1:8088/world-ui-26.3-snapshot-9.zip -o /tmp/live-world-ui.zip
sha1sum /tmp/live-world-ui.zip
stat -c '%s bytes' /tmp/live-world-ui.zip
unzip -l /tmp/live-world-ui.zip | grep -E 'font/(item_icons|icons)\.json|pack.mcmeta'

echo '=== current mixin source head ==='
sed -n '1,280p' /opt/brigada-hotfix-src/src/main/java/dev/brigada13/hotfix/mixin/ChallengeServiceMixin.java

echo PACK_HOST_OK
