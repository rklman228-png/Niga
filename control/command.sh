set -euo pipefail

echo '=== hotfix files ==='
find /opt/brigada-hotfix-src/src/main -maxdepth 8 -type f -print | sort

echo '=== mixins json ==='
cat /opt/brigada-hotfix-src/src/main/resources/brigada_hotfix.mixins.json

echo '=== runtime key source ==='
grep -nE 'register\(|onComplete|stabiliseEventMobs|tickMeaningfulParticles|nearbySurfaceY|emitFireworkBurst|play\(|eventEntities|setGlowingTag|setPersistenceRequired' /opt/brigada-hotfix-src/src/main/java/dev/brigada13/hotfix/RuntimeFixes.java || true

echo '=== server resource pack properties ==='
grep -E '^(resource-pack|require-resource-pack|resource-pack-sha1|resource-pack-id)' /opt/minecraft/server/server.properties || true

echo '=== exact local pack candidates ==='
find /opt/minecraft/server /var/www /srv -maxdepth 4 -type f \( -iname 'world-ui*.zip' -o -iname '*resource*pack*.zip' -o -iname 'item_icons.json' \) -printf '%TY-%Tm-%Td %TH:%TM:%TS %s %p\n' 2>/dev/null | sort -r | head -n 40 || true

for z in $(find /opt/minecraft/server /var/www /srv -maxdepth 4 -type f -iname 'world-ui*.zip' 2>/dev/null | head -n 4); do
  echo "=== zip $z ==="
  unzip -l "$z" | grep -E 'font/(item_icons|icons)\.json|pack.mcmeta' || true
  unzip -p "$z" assets/brigada_core/font/item_icons.json 2>/dev/null | head -c 12000 || true
  echo
 done

echo FAST_INSPECT_OK
