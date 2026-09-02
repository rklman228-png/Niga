#!/usr/bin/env bash
set -euo pipefail

CFG='/root/vless-reality-47005/server.json'

echo '===== latency/routing diagnostics ====='
echo "main_vless=$(docker inspect -f '{{.State.Running}}' xray-vless-47005 2>/dev/null || echo missing)"
echo "awg31=$(docker inspect -f '{{.State.Running}}' amnezia-awg31-mobile 2>/dev/null || echo missing)"

echo '--- VLESS outbound summary ---'
python3 - "$CFG" <<'PY'
import json,sys
p=sys.argv[1]
d=json.load(open(p))
for i,o in enumerate(d.get('outbounds',[])):
    print(f'outbound[{i}] protocol={o.get("protocol")} tag={o.get("tag")}')
for i,r in enumerate(d.get('routing',{}).get('rules',[])):
    print(f'rule[{i}] outbound={r.get("outboundTag")} network={r.get("network")} protocol={r.get("protocol")}')
PY

echo '--- host routing ---'
ip route show default
ip rule show | sed -n '1,12p'

echo '--- congestion/qdisc ---'
printf 'tcp_congestion_control='; sysctl -n net.ipv4.tcp_congestion_control
printf 'available_cc='; sysctl -n net.ipv4.tcp_available_congestion_control
printf 'default_qdisc='; sysctl -n net.core.default_qdisc
tc qdisc show dev eth0 | head -n 4

echo '--- active VLESS TCP RTT samples ---'
# Print RTT only, never peer addresses.
ss -tin state established '( sport = :47005 )' 2>/dev/null \
 | grep -oE 'rtt:[0-9.]+/[0-9.]+' \
 | sort -u \
 | head -n 20 || true

echo '--- VPS outbound baseline ---'
for host in 1.1.1.1 8.8.8.8; do
  printf '%s ' "$host"
  ping -n -c 5 -W 2 "$host" 2>/dev/null | tail -n 1 || true
done
for url in https://www.gstatic.com/generate_204 https://telegram.org/; do
  curl -4 -o /dev/null -sS --max-time 10 -w "$url connect=%{time_connect}s tls=%{time_appconnect}s total=%{time_total}s\n" "$url" || true
done

echo ROUTING_DIAG_OK
