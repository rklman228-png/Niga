set -euo pipefail
grep -n -A45 -B2 '"activeChallenge"\|"activeExpedition"' /opt/minecraft/server/config/brigada-core/state.json || true
