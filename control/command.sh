#!/usr/bin/env bash
set -euo pipefail

echo '===== live whitelist trace ====='
echo "now=$(date -u +%FT%TZ)"
echo "wl_vless=$(docker inspect -f '{{.State.Running}}' xray-vless-whitelist 2>/dev/null || echo missing)"
echo "public443_estab=$(ss -tnH state established '( sport = :443 or dport = :443 )' 2>/dev/null | wc -l)"
echo "wl47006_estab=$(ss -tnH state established '( sport = :47006 or dport = :47006 )' 2>/dev/null | wc -l)"
echo '--- recent wl xray accepts ---'
docker logs --since 8m --tail 200 xray-vless-whitelist 2>&1 \
 | sed -E 's/([0-9]{1,3}\.){3}[0-9]{1,3}/[ip]/g; s/[A-Fa-f0-9]{8}-[A-Fa-f0-9-]{27,}/[uuid]/g' \
 | tail -n 120 || true

echo '--- nginx stream sockets ---'
ss -ltnp | grep -E ':(443|4443|47006) ' || true

echo '--- service preservation ---'
echo "main_vless=$(docker inspect -f '{{.State.Running}}' xray-vless-47005 2>/dev/null || echo missing)"
echo "awg31=$(docker inspect -f '{{.State.Running}}' amnezia-awg31-mobile 2>/dev/null || echo missing)"
echo TRACE_OK
