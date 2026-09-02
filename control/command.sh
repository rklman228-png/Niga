#!/usr/bin/env bash
set -euo pipefail

echo '===== VPN status ====='
echo "main_vless=$(docker inspect -f '{{.State.Running}}' xray-vless-47005 2>/dev/null || echo missing)"
echo "main_tcp47005=$(ss -ltnH | grep -c ':47005 ' || true)"
echo "awg31=$(docker inspect -f '{{.State.Running}}' amnezia-awg31-mobile 2>/dev/null || echo missing)"
echo "legacy_xray=$(docker inspect -f '{{.State.Running}}' amnezia-xray 2>/dev/null || echo missing)"
echo VPN_STATUS_OK
