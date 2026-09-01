#!/usr/bin/env bash
set -euo pipefail

echo '===== VPN status ====='
echo "wl_vless=$(docker inspect -f '{{.State.Running}}' xray-vless-whitelist 2>/dev/null || echo missing)"
echo "tcp443=$(ss -ltnH | grep -c ':443 ' || true)"
echo "tcp4443=$(ss -ltnH | grep -c ':4443 ' || true)"
echo "main_vless=$(docker inspect -f '{{.State.Running}}' xray-vless-47005 2>/dev/null || echo missing)"
echo "awg31=$(docker inspect -f '{{.State.Running}}' amnezia-awg31-mobile 2>/dev/null || echo missing)"
echo "legacy_xray=$(docker inspect -f '{{.State.Running}}' amnezia-xray 2>/dev/null || echo missing)"
for domain in bot.pronexsbp.ru enihub.ru; do
  code="$(curl -sS -o /dev/null --max-time 8 --resolve "$domain:443:127.0.0.1" -w '%{http_code}' "https://$domain/" || true)"
  echo "$domain=http_$code"
done
echo VPN_STATUS_OK
