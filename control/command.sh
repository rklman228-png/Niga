set -euo pipefail
MOD=/opt/minecraft/server/mods/brigada-hotfix-1.0.0.jar

echo '=== wait for full server startup ==='
for i in $(seq 1 90); do
  if ss -ltn | grep -q ':25565 '; then break; fi
  if ! systemctl is-active --quiet minecraft; then break; fi
  sleep 1
done

echo '=== hotfix jar ==='
test -s "$MOD"
sha256sum "$MOD"
jar tf "$MOD" | grep -E 'BrigadaHotfix|RuntimeFixes|ChallengeServiceMixin|brigada_hotfix.mixins.json'

echo '=== service ==='
systemctl --no-pager --full status minecraft | head -n 30 || true

echo '=== port ==='
ss -ltnp | grep ':25565 ' || true

echo '=== relevant startup ==='
journalctl -u minecraft --since '2026-08-25 14:35:50' --no-pager | grep -Ei 'brigada|Done \(|mixin|ERROR|Exception|25565|Starting Minecraft server' | tail -n 160 || true

echo '=== hard checks ==='
test "$(systemctl is-active minecraft)" = active
ss -ltn | grep -q ':25565 '
! journalctl -u minecraft --since '2026-08-25 14:35:50' --no-pager | grep -Eqi 'InjectionError|InvalidMixin|MixinApplyError|Could not execute entrypoint|ModResolutionException|Exception in server tick loop|Failed to start the minecraft server'
echo VERIFY_OK
