#!/usr/bin/env bash
set -euo pipefail

echo '===== AWG apply inspection ====='
echo "host_awg=$(command -v awg || true)"
echo "host_wg=$(command -v wg || true)"
echo "container_awg=$(docker exec amnezia-awg31-mobile sh -lc 'command -v awg || true' 2>/dev/null || true)"
echo "container_wg=$(docker exec amnezia-awg31-mobile sh -lc 'command -v wg || true' 2>/dev/null || true)"
echo '--- start-hostnet.sh ---'
sed -n '1,220p' /root/amnezia-awg31-mobile/start-hostnet.sh 2>/dev/null | sed -E 's/(PrivateKey|PresharedKey|HeaderProtectionKey)[[:space:]]*=.*/\1 = <redacted>/I' || true
echo '--- awg0 peer count ---'
grep -c '^\[Peer\]' /root/amnezia-awg31-mobile/awg0.conf 2>/dev/null || true
echo AWG_APPLY_INSPECT_OK
