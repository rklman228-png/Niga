#!/usr/bin/env bash
set -euo pipefail

echo '===== whitelist profile preflight ====='
echo '--- nginx build ---'
nginx -V 2>&1 | sed 's/ --/\n--/g' | grep -E 'nginx version|with-stream|dynamic-module' || true

echo '--- listeners 443 ---'
ss -ltnpH | grep ':443 ' || true

echo '--- nginx 443 declarations ---'
grep -RInE 'listen[[:space:]].*443' /etc/nginx 2>/dev/null | head -n 40 || true

echo '--- candidate local ports ---'
for p in 47006 47007 8443 2053; do
  if ss -ltnH | grep -qE "[:.]${p}[[:space:]]"; then echo "$p=busy"; else echo "$p=free"; fi
done

echo '--- decoy TLS 1.3 tests ---'
for host in vk.com yandex.ru www.yandex.ru; do
  printf '%s=' "$host"
  if timeout 8 openssl s_client -connect "$host:443" -servername "$host" -tls1_3 </dev/null 2>/dev/null | grep -q 'Protocol  *: TLSv1.3'; then echo tls13_ok; else echo tls13_unknown; fi
done

echo '--- preservation ---'
echo "vless_main=$(docker inspect -f '{{.State.Running}}' xray-vless-47005 2>/dev/null || echo missing)"
echo "awg31=$(docker inspect -f '{{.State.Running}}' amnezia-awg31-mobile 2>/dev/null || echo missing)"
echo WL_PREFLIGHT_OK
