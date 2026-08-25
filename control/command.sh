set -euo pipefail
SINCE='2026-08-25 15:26:40'

echo '=== wait for Done ==='
for i in $(seq 1 90); do
  if ! systemctl is-active --quiet minecraft; then
    echo SERVICE_DIED
    exit 1
  fi
  if journalctl -u minecraft --since "$SINCE" --no-pager | grep -q 'Done ('; then
    break
  fi
  sleep 1
done

echo '=== service ==='
systemctl is-active minecraft
ss -ltnp | grep ':25565 '

echo '=== startup/runtime ==='
journalctl -u minecraft --since "$SINCE" --no-pager | grep -E 'brigada_hotfix|Starting Minecraft server|Done \(|ERROR|Exception|MixinApplyError|InjectionError|InvalidMixin|NoSuchMethodError' | tail -n 200 || true

echo '=== hard checks ==='
test "$(systemctl is-active minecraft)" = active
ss -ltn | grep -q ':25565 '
journalctl -u minecraft --since "$SINCE" --no-pager | grep -q 'Done ('
! journalctl -u minecraft --since "$SINCE" --no-pager | grep -Eqi 'InjectionError|InvalidMixin|MixinApplyError|Could not execute entrypoint|ModResolutionException|Exception in server tick loop|Failed to start the minecraft server|NoSuchMethodError'
echo HARD_BORDER_TELEPORT_RUNTIME_OK
