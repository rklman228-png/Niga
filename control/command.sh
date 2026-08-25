set -euo pipefail

echo '=== hotfix source ==='
sed -n '1,520p' /opt/brigada-hotfix-src/src/main/java/dev/brigada13/hotfix/RuntimeFixes.java | grep -n -E 'register\(|stabiliseEventMobs|tickMeaningfulParticles|boundary|ring\(|onComplete|emitFireworkBurst|ServerEntityEvents|Magma|Slime|eventEntities|glowing|Persistence|play\(' || true

echo '=== hotfix mixin ==='
sed -n '1,420p' /opt/brigada-hotfix-src/src/main/java/dev/brigada13/hotfix/mixin/ChallengeServiceMixin.java | grep -n -E 'renderZone|tickHold|tickSplit|tickExtraction|Redirect|Inject|complete' || true

echo '=== menu bytecode methods ==='
J=/opt/minecraft/server/mods/brigada-core-0.1.0.jar
javap -classpath "$J" -p dev.brigada13.core.menu.WorldMenuService | grep -E 'buttonWithItem|item|Item|glyph|icon|Icon|openDeaths' || true

echo '=== menu source candidates / resource pack ==='
grep -RIn --exclude='*.jar' --exclude='*.log' -E 'item_icons|itemGlyph|buttonWithItem|Здесь только вещи' /opt /root 2>/dev/null | head -n 160 || true

echo '=== server resource pack config ==='
grep -E '^(resource-pack|require-resource-pack|resource-pack-sha1|resource-pack-id)' /opt/minecraft/server/server.properties || true
find /opt/minecraft /opt -maxdepth 5 -type f \( -iname '*.zip' -o -iname '*pack*' \) -printf '%TY-%Tm-%Td %TH:%TM %s %p\n' 2>/dev/null | sort -r | head -n 80 || true
