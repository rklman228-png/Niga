#!/usr/bin/env bash
set -euo pipefail

echo '===== AWG31 inspect ====='
echo "container=$(docker inspect -f '{{.State.Running}}' amnezia-awg31-mobile 2>/dev/null || echo missing)"
echo '--- mounts ---'
docker inspect -f '{{range .Mounts}}{{println .Source "->" .Destination}}{{end}}' amnezia-awg31-mobile 2>/dev/null || true
echo '--- interface ---'
ip -brief addr show awg3m 2>/dev/null || true
wg show awg3m 2>/dev/null | sed -E '/private key:/d;/preshared key:/d' || true
echo '--- likely configs ---'
find /root /etc -maxdepth 4 -type f \( -iname '*awg*' -o -iname '*amnezia*wg*' \) -printf '%p\n' 2>/dev/null | head -n 30

echo AWG31_INSPECT_OK
