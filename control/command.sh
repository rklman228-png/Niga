set -euo pipefail
if command -v jq >/dev/null; then
  jq '{activeChallenge:.activeChallenge,activeExpedition:.activeExpedition}' /opt/minecraft/server/config/brigada-core/state.json
else
  sed -n '1,160p' /opt/minecraft/server/config/brigada-core/state.json
fi
