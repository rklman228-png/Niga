#!/usr/bin/env bash
set -euo pipefail

echo '===== VPN status ====='
echo "vless_reality=$(docker inspect -f '{{.State.Running}}' xray-vless-47005 2>/dev/null || echo missing)"
echo "vless_tcp47005=$(ss -ltnH | grep -c ':47005 ' || true)"
echo "mobile_awg31=$(docker inspect -f '{{.State.Running}}' amnezia-awg31-mobile 2>/dev/null || echo missing)"
echo "mobile_iface=$([ -d /sys/class/net/awg3m ] && echo up || echo missing)"
echo "legacy_awg0=$([ -d /sys/class/net/awg0 ] && echo up || echo missing)"
echo "legacy_awg1=$([ -d /sys/class/net/awg1 ] && echo up || echo missing)"
echo "legacy_xray=$(docker inspect -f '{{.State.Running}}' amnezia-xray 2>/dev/null || echo missing)"
echo VPN_STATUS_OK
