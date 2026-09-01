#!/usr/bin/env bash
set -euo pipefail

echo '===== whitelist IPv4/IPv6 diagnostics ====='
echo '--- host addresses ---'
ip -br addr | sed -E 's#([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]+#[ipv4]#g; s#[0-9a-fA-F:]{3,}/[0-9]+#[ipv6]#g'
echo '--- IPv6 routes ---'
ip -6 route show || true

echo '--- connectivity ---'
printf 'ipv4_cloudflare='; curl -4 -sS -o /dev/null --max-time 8 -w '%{http_code}\n' https://www.cloudflare.com/ || echo fail
printf 'ipv6_cloudflare='; curl -6 -sS -o /dev/null --max-time 8 -w '%{http_code}\n' https://www.cloudflare.com/ || echo fail
printf 'ipv4_google='; curl -4 -sS -o /dev/null --max-time 8 -w '%{http_code}\n' https://www.google.com/ || echo fail
printf 'ipv6_google='; curl -6 -sS -o /dev/null --max-time 8 -w '%{http_code}\n' https://www.google.com/ || echo fail

echo '--- recent whitelist xray log classes ---'
docker logs --since 15m --tail 200 xray-vless-whitelist 2>&1 \
 | sed -E 's/([0-9]{1,3}\.){3}[0-9]{1,3}/[ip]/g; s/[A-Fa-f0-9]{8}-[A-Fa-f0-9-]{27,}/[uuid]/g' \
 | tail -n 120 || true

echo '--- services ---'
echo "wl_vless=$(docker inspect -f '{{.State.Running}}' xray-vless-whitelist 2>/dev/null || echo missing)"
echo "main_vless=$(docker inspect -f '{{.State.Running}}' xray-vless-47005 2>/dev/null || echo missing)"
echo "awg31=$(docker inspect -f '{{.State.Running}}' amnezia-awg31-mobile 2>/dev/null || echo missing)"
echo WL_IP_DIAG_OK
