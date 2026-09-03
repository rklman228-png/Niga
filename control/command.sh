#!/usr/bin/env bash
set -euo pipefail

echo '===== VPN status ====='
echo "main_vless=$(docker inspect -f '{{.State.Running}}' xray-vless-47005 2>/dev/null || echo missing)"
echo "main_tcp47005=$(ss -ltnH | grep -c ':47005 ' || true)"
echo "awg31=$(docker inspect -f '{{.State.Running}}' amnezia-awg31-mobile 2>/dev/null || echo missing)"
echo "awg_udp585=$(ss -lunH | grep -c ':585 ' || true)"
echo "cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)"
echo VPN_STATUS_OK
