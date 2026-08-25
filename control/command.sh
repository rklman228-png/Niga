set -euo pipefail
cd /opt/minecraft/server
echo '=== properties'
grep -E '^(require-resource-pack|resource-pack|resource-pack-id|resource-pack-sha1|online-mode|white-list|enforce-whitelist|level-name)=' server.properties || true
echo '=== usercache'
cat usercache.json 2>/dev/null || true
echo '=== ops'
cat ops.json 2>/dev/null || true
echo '=== whitelist'
cat whitelist.json 2>/dev/null || true
echo '=== mods'
find mods -maxdepth 1 -type f -printf '%f\n' | sort
echo '=== service'
systemctl cat minecraft.service
echo '=== status'
systemctl is-active minecraft.service
