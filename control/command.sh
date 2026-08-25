set -euo pipefail
SERVER=/opt/minecraft/server
BUILD=/opt/brigada-core-src/build/libs/brigada-core-0.1.0.jar
EXPECTED=30e94c349a3119442196bc68e368afba0218f847cbe95bc1eb1fde9d9797eed9
test "$(sha256sum "$BUILD" | awk '{print $1}')" = "$EXPECTED"
systemctl stop minecraft.service
cp "$SERVER/mods/brigada-core-0.1.0.jar" "$SERVER/mods/brigada-core-0.1.0.jar.before-ui-fixes"
install -o minecraft -g minecraft -m 0644 "$BUILD" "$SERVER/mods/brigada-core-0.1.0.jar"
sed -i 's/^require-resource-pack=.*/require-resource-pack=true/' "$SERVER/server.properties"
sed -i 's/^resource-pack-id=.*/resource-pack-id=fc9e76d5-cfc6-4d60-b30c-6a43dc6ffa65/' "$SERVER/server.properties"
if grep -q '^resource-pack-prompt=' "$SERVER/server.properties"; then
  sed -i 's|^resource-pack-prompt=.*|resource-pack-prompt={"text":"Ресурсы интерфейса обязательны для игры на сервере.","color":"gold"}|' "$SERVER/server.properties"
else
  printf '%s\n' 'resource-pack-prompt={"text":"Ресурсы интерфейса обязательны для игры на сервере.","color":"gold"}' >> "$SERVER/server.properties"
fi
printf '%s\n' '[{"uuid":"d5c369db-55e6-30e8-aac1-b9f9bdb92beb","name":"Otezi","level":4,"bypassesPlayerLimit":false}]' > "$SERVER/ops.json"
chown minecraft:minecraft "$SERVER/server.properties" "$SERVER/ops.json"
STATE="$SERVER/config/brigada-core/state.json"
cp "$STATE" "$STATE.before-challenge-fix"
jq '.activeChallenge = null' "$STATE" > "$STATE.tmp"
mv "$STATE.tmp" "$STATE"
chown minecraft:minecraft "$STATE"
systemctl start minecraft.service
sleep 14
echo '=== service'
systemctl is-active minecraft.service
echo '=== deployed'
sha256sum "$SERVER/mods/brigada-core-0.1.0.jar"
grep -E '^(require-resource-pack|resource-pack-id|resource-pack-sha1|resource-pack-prompt)=' "$SERVER/server.properties"
cat "$SERVER/ops.json"
echo '=== log'
journalctl -u minecraft.service -n 100 --no-pager
