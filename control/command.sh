set -euo pipefail
echo '=== state files'
find /opt/minecraft/server -maxdepth 4 -type f \( -iname '*brigada*json' -o -path '*/brigada_core/*' \) -print
echo '=== state content'
for f in /opt/minecraft/server/config/brigada-core/*.json /opt/minecraft/server/world/brigada-core*.json /opt/minecraft/server/world/brigada_core*.json; do
  [ -f "$f" ] || continue
  echo "--- $f"
  cat "$f"
done
