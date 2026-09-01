#!/usr/bin/env bash
set -euo pipefail

echo '===== latency diagnostics ====='
echo '--- load ---'
uptime
printf 'cpu_count='; nproc
printf 'mem_available_mb='; awk '/MemAvailable:/ {printf "%.0f\n", $2/1024}' /proc/meminfo

echo '--- vless status ---'
echo "vless=$(docker inspect -f '{{.State.Running}}' xray-vless-47005 2>/dev/null || echo missing)"
echo "tcp47005=$(ss -ltnH | grep -c ':47005 ' || true)"

echo '--- network RTT from VPS ---'
for host in 1.1.1.1 8.8.8.8; do
  echo "host=$host"
  ping -n -c 8 -W 2 "$host" 2>/dev/null | tail -n 2 || true
done

echo '--- HTTPS timing from VPS ---'
for url in https://www.gstatic.com/generate_204 https://www.cloudflare.com/cdn-cgi/trace; do
  curl -o /dev/null -sS --max-time 10 -w "$url connect=%{time_connect}s tls=%{time_appconnect}s total=%{time_total}s\n" "$url" || true
done

echo '--- socket counters ---'
ss -s

echo LATENCY_DIAG_OK
