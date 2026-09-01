#!/usr/bin/env bash
set -euo pipefail

IMAGE='ghcr.io/xtls/xray-core:26.3.27'
STATE='/root/vless-reality-whitelist'
TEST='xray-wl-diag-client'

echo '===== whitelist runtime diagnostics ====='
echo "wl_vless=$(docker inspect -f '{{.State.Running}}' xray-vless-whitelist 2>/dev/null || echo missing)"
echo "main_vless=$(docker inspect -f '{{.State.Running}}' xray-vless-47005 2>/dev/null || echo missing)"
echo "tcp443=$(ss -ltnH | grep -c ':443 ' || true)"
echo "tcp47006=$(ss -ltnH | grep -c ':47006 ' || true)"

echo '--- current established counts ---'
echo "estab_public443=$(ss -tnH state established '( sport = :443 or dport = :443 )' 2>/dev/null | wc -l)"
echo "estab_wl_backend=$(ss -tnH state established '( sport = :47006 or dport = :47006 )' 2>/dev/null | wc -l)"

echo '--- whitelist xray recent logs ---'
docker logs --since 10m --tail 80 xray-vless-whitelist 2>&1 \
 | sed -E 's/([0-9]{1,3}\.){3}[0-9]{1,3}/[ip]/g; s/[A-Fa-f0-9]{8}-[A-Fa-f0-9-]{27,}/[uuid]/g' || true

echo '--- local client end-to-end tests ---'
docker rm -f "$TEST" >/dev/null 2>&1 || true
docker run -d --name "$TEST" --network host --user 0:0 \
  -v "$STATE/client.json:/etc/xray/config.json:ro" \
  "$IMAGE" run -config=/etc/xray/config.json >/dev/null
cleanup(){ docker rm -f "$TEST" >/dev/null 2>&1 || true; }
trap cleanup EXIT
sleep 2
for url in \
  https://api.ipify.org \
  https://www.gstatic.com/generate_204 \
  https://www.cloudflare.com/cdn-cgi/trace \
  https://telegram.org/; do
  printf '%s ' "$url"
  curl -sS -o /dev/null --max-time 15 --socks5-hostname 127.0.0.1:10918 \
    -w 'code=%{http_code} connect=%{time_connect} total=%{time_total}\n' "$url" || echo failed
done

echo '--- DNS over proxy via hostname resolution ---'
for host in google.com telegram.org github.com; do
  printf '%s ' "$host"
  curl -sS -o /dev/null --max-time 15 --socks5-hostname 127.0.0.1:10918 \
    -w 'code=%{http_code} remote=%{remote_ip} total=%{time_total}\n' "https://$host/" \
    | sed -E 's/remote=[^ ]+/remote=[proxied]/' || echo failed
done

echo '--- preservation ---'
for domain in bot.pronexsbp.ru enihub.ru; do
  code="$(curl -sS -o /dev/null --max-time 8 --resolve "$domain:443:127.0.0.1" -w '%{http_code}' "https://$domain/" || true)"
  echo "$domain=http_$code"
done
echo WL_RUNTIME_DIAG_OK
