set -euo pipefail

echo '=== service ==='
systemctl is-active minecraft
ss -ltnp | grep ':25565 '

echo '=== full startup marker ==='
journalctl -u minecraft --since '2026-08-25 15:02:35' --no-pager | grep -E 'Done \(|brigada_hotfix|Starting Minecraft server' | tail -n 80 || true

echo '=== post-start problems ==='
journalctl -u minecraft --since '2026-08-25 15:03:30' --no-pager | grep -Ei 'WARN|ERROR|Exception|MixinApplyError|InjectionError|InvalidMixin|crash' | tail -n 120 || true

test "$(systemctl is-active minecraft)" = active
ss -ltn | grep -q ':25565 '
journalctl -u minecraft --since '2026-08-25 15:02:35' --no-pager | grep -q 'Done ('
! journalctl -u minecraft --since '2026-08-25 15:02:35' --no-pager | grep -Eqi 'InjectionError|InvalidMixin|MixinApplyError|Could not execute entrypoint|ModResolutionException|Exception in server tick loop|Failed to start the minecraft server'
echo RUNTIME_V2_OK
