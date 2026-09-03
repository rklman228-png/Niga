#!/usr/bin/env bash
set -euo pipefail

echo '===== VPN slowdown diagnostics ====='
date -u '+utc=%Y-%m-%dT%H:%M:%SZ'
echo '--- services ---'
for c in xray-vless-47005 amnezia-awg31-mobile amnezia-xray; do
  echo "$c=$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null || echo missing)"
done

echo '--- host load ---'
uptime
free -m
printf 'root_disk='; df -h / | awk 'NR==2{print $5" used, "$4" free"}'

echo '--- docker resources ---'
docker stats --no-stream --format '{{.Name}} cpu={{.CPUPerc}} mem={{.MemUsage}} net={{.NetIO}}' xray-vless-47005 amnezia-awg31-mobile amnezia-xray 2>/dev/null || true

echo '--- network interface ---'
ip -s link show dev eth0 | sed -n '1,6p'

echo '--- qdisc/congestion ---'
printf 'cc='; sysctl -n net.ipv4.tcp_congestion_control
printf 'available_cc='; sysctl -n net.ipv4.tcp_available_congestion_control
printf 'default_qdisc='; sysctl -n net.core.default_qdisc
tc -s qdisc show dev eth0 | sed -n '1,8p'

echo '--- socket/conntrack pressure ---'
ss -s
if [ -r /proc/sys/net/netfilter/nf_conntrack_count ]; then
  printf 'conntrack='; cat /proc/sys/net/netfilter/nf_conntrack_count
  printf 'conntrack_max='; cat /proc/sys/net/netfilter/nf_conntrack_max
fi

echo '--- TCP retrans counters ---'
netstat -s 2>/dev/null | grep -Ei 'segments retransmitted|retransmit|failed connection|listen.*overflow|packet receive errors' | head -n 20 || true

echo '--- active VLESS RTT (addresses hidden) ---'
ss -tin state established '( sport = :47005 )' 2>/dev/null | grep -oE 'rtt:[0-9.]+/[0-9.]+' | sort -u | head -n 30 || true

echo '--- AWG status sanitized ---'
wg show awg3m 2>/dev/null | sed -E '/private key:/d;/public key:/d;/preshared key:/d;/peer:/d' | head -n 30 || true

echo '--- recent service error counts (20m) ---'
for c in xray-vless-47005 amnezia-awg31-mobile; do
  log="$(docker logs --since 20m "$c" 2>&1 || true)"
  printf '%s errors=' "$c"
  printf '%s' "$log" | grep -Eci 'error|failed|timeout|reset|unreachable|refused|rejected' || true
  printf '%s warnings=' "$c"
  printf '%s' "$log" | grep -Eci 'warn' || true
done

echo '--- outbound latency/loss ---'
for host in 1.1.1.1 8.8.8.8 9.9.9.9; do
  printf '%s ' "$host"
  ping -n -c 12 -W 2 "$host" 2>/dev/null | awk '/packet loss/{loss=$6} /min\/avg\/max/{rtt=$4} END{print "loss="loss" rtt="rtt}' || true
done

echo '--- HTTPS timing ---'
for url in https://www.gstatic.com/generate_204 https://telegram.org/ https://github.com/ https://ya.ru/; do
  curl -4 -L -o /dev/null -sS --max-time 15 -w "$url code=%{http_code} connect=%{time_connect}s tls=%{time_appconnect}s start=%{time_starttransfer}s total=%{time_total}s\n" "$url" || true
done

echo '--- outbound throughput sample ---'
curl -4 -L -o /dev/null -sS --max-time 35 -w 'cloudflare_20MB code=%{http_code} speed_Bps=%{speed_download} total=%{time_total}s\n' 'https://speed.cloudflare.com/__down?bytes=20000000' || true

echo VPN_SLOW_DIAG_OK
