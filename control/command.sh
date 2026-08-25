set -euo pipefail
JAR=/opt/brigada-hotfix-src/build/libs/brigada-hotfix-0.1.0.jar
MOD=/opt/minecraft/server/mods/brigada-hotfix-1.0.0.jar

test -s "$JAR"
install -m 0644 "$JAR" "$MOD"
echo '=== installed hotfix ==='
sha256sum "$MOD"

systemctl restart minecraft
for i in $(seq 1 30); do
  if systemctl is-active --quiet minecraft && ss -ltn | grep -q ':25565 '; then break; fi
  sleep 1
done

echo '=== service ==='
systemctl is-active minecraft
ss -ltnp | grep ':25565 ' || true

echo '=== startup log ==='
journalctl -u minecraft --since '-2 min' --no-pager | tail -n 180

echo '=== verify ==='
test "$(systemctl is-active minecraft)" = active
ss -ltn | grep -q ':25565 '
! journalctl -u minecraft --since '-2 min' --no-pager | grep -Eqi 'InjectionError|InvalidMixin|Could not execute entrypoint|ModResolutionException|Exception in server tick loop'
echo DEPLOY_OK
