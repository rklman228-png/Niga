#!/usr/bin/env bash
set -euo pipefail

FILE=/etc/sysctl.d/99-vpn-performance.conf
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
if [ -f "$FILE" ]; then cp -a "$FILE" "/root/99-vpn-performance.conf.$STAMP.bak"; fi

echo '===== apply VPN network tuning ====='
echo "before_cc=$(sysctl -n net.ipv4.tcp_congestion_control)"
echo "before_rmem_max=$(sysctl -n net.core.rmem_max)"
echo "before_wmem_max=$(sysctl -n net.core.wmem_max)"

cat > "$FILE" <<'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_fastopen = 3
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.ipv4.udp_rmem_min = 131072
net.ipv4.udp_wmem_min = 131072
net.ipv4.tcp_rmem = 4096 131072 67108864
net.ipv4.tcp_wmem = 4096 16384 67108864
net.core.netdev_max_backlog = 16384
EOF

sysctl -p "$FILE"

echo '--- restart active VPN transports ---'
docker restart xray-vless-47005 >/dev/null
docker restart amnezia-awg31-mobile >/dev/null
sleep 3

echo '--- verify ---'
echo "after_cc=$(sysctl -n net.ipv4.tcp_congestion_control)"
echo "qdisc=$(sysctl -n net.core.default_qdisc)"
echo "rmem_max=$(sysctl -n net.core.rmem_max)"
echo "wmem_max=$(sysctl -n net.core.wmem_max)"
echo "tcp_mtu_probing=$(sysctl -n net.ipv4.tcp_mtu_probing)"
echo "tcp_fastopen=$(sysctl -n net.ipv4.tcp_fastopen)"
echo "main_vless=$(docker inspect -f '{{.State.Running}}' xray-vless-47005 2>/dev/null || echo missing)"
echo "awg31=$(docker inspect -f '{{.State.Running}}' amnezia-awg31-mobile 2>/dev/null || echo missing)"
echo "tcp47005=$(ss -ltnH | grep -c ':47005 ' || true)"
echo "udp585=$(ss -lunH | grep -c ':585 ' || true)"

for host in 1.1.1.1 8.8.8.8; do
  printf '%s ' "$host"
  ping -n -c 8 -W 2 "$host" 2>/dev/null | awk '/packet loss/{loss=$6} /min\/avg\/max/{rtt=$4} END{print "loss="loss" rtt="rtt}' || true
done
curl -4 -L -o /dev/null -sS --max-time 20 -w 'cloudflare_10MB code=%{http_code} speed_Bps=%{speed_download} total=%{time_total}s\n' 'https://speed.cloudflare.com/__down?bytes=10000000' || true

echo VPN_TUNING_OK
