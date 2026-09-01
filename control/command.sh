#!/usr/bin/env bash
set -euo pipefail

echo '===== VPN status ====='
echo "mobile_reality=$(docker inspect -f '{{.State.Running}}' amnezia-xray-mobile 2>/dev/null || echo missing)"
echo "legacy_xray=$(docker inspect -f '{{.State.Running}}' amnezia-xray 2>/dev/null || echo missing)"
echo "awg0=$([ -d /sys/class/net/awg0 ] && echo up || echo missing)"
echo "awg1=$([ -d /sys/class/net/awg1 ] && echo up || echo missing)"
ss -ltnH | grep ':8443 ' >/dev/null && echo 'mobile_8443_tcp=listening' || echo 'mobile_8443_tcp=missing'
echo VPN_STATUS_OK
