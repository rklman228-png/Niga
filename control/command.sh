set -euo pipefail
echo INDEXES
find /root/.gradle /opt/minecraft -type f \( -path '*/assets/indexes/*.json' -o -name '26.json' -o -name '26.3-snapshot-9.json' \) 2>/dev/null | head -30
echo TEXTURES
find /root/.gradle /opt/minecraft -type f \( -iname 'compass*.png' -o -iname 'recovery_compass*.png' -o -iname 'bundle*.png' -o -iname 'netherite_sword*.png' \) 2>/dev/null | head -60
