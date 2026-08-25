set -euo pipefail
JAR=/opt/brigada-hotfix-src/build/libs/brigada-hotfix-0.1.0.jar
MOD=/opt/minecraft/server/mods/brigada-hotfix-1.0.0.jar

echo '=== deploy v2 ==='
test -s "$JAR"
sha256sum "$JAR"
install -m 0644 "$JAR" "$MOD"
sha256sum "$MOD"

systemctl restart minecraft
for i in $(seq 1 100); do
  if ! systemctl is-active --quiet minecraft; then
    echo SERVICE_DIED
    break
  fi
  if ss -ltn | grep -q ':25565 '; then
    break
  fi
  sleep 1
done

echo '=== verify service ==='
systemctl is-active minecraft
ss -ltnp | grep ':25565 '

echo '=== startup ==='
journalctl -u minecraft --since '-3 min' --no-pager | grep -Ei 'brigada_hotfix|brigada_core|Done \(|Starting Minecraft server|Mixin|ERROR|Exception|failed' | tail -n 220 || true

echo '=== hard checks ==='
test "$(systemctl is-active minecraft)" = active
ss -ltn | grep -q ':25565 '
! journalctl -u minecraft --since '-3 min' --no-pager | grep -Eqi 'InjectionError|InvalidMixin|MixinApplyError|Could not execute entrypoint|ModResolutionException|Exception in server tick loop|Failed to start the minecraft server'
echo DEPLOY_V2_OK
