#!/usr/bin/env bash
set -euo pipefail

IMAGE='ghcr.io/xtls/xray-core:26.3.27'
STATE='/root/vless-reality-whitelist'
CONTAINER='xray-vless-whitelist'
TEST='xray-wl-ipv4-client'
SERVER_IP='143.246.197.187'

echo '===== force whitelist profile to IPv4 ====='
cp -a "$STATE/server.json" "$STATE/server.json.before-ipv4" 
cp -a "$STATE/client.json" "$STATE/client.json.before-ipv4"

python3 - <<'PY'
import json
from pathlib import Path
state=Path('/root/vless-reality-whitelist')

sp=state/'server.json'
s=json.loads(sp.read_text())
for ob in s.get('outbounds',[]):
    if ob.get('tag')=='direct' or ob.get('protocol')=='freedom':
        ob.setdefault('settings',{})['domainStrategy']='UseIPv4'
sp.write_text(json.dumps(s,ensure_ascii=False,separators=(',',':')))

cp=state/'client-ipv4.json'
c=json.loads((state/'client.json').read_text())
c['dns']={'queryStrategy':'UseIPv4','servers':['1.1.1.1','1.0.0.1']}
# Explicit IPv4 preference for local DNS/routing.
c['routing']={
    'domainStrategy':'IPIfNonMatch',
    'rules':[{'type':'field','network':'tcp,udp','outboundTag':'proxy'}]
}
for ob in c.get('outbounds',[]):
    if ob.get('tag')=='proxy' and ob.get('protocol')=='vless':
        user=ob['settings']['vnext'][0]['users'][0]
        user['packetEncoding']='xudp'
        rs=ob.setdefault('streamSettings',{}).setdefault('realitySettings',{})
        rs['fingerprint']='firefox'
cp.write_text(json.dumps(c,ensure_ascii=False,separators=(',',':')))
PY
chmod 600 "$STATE/server.json" "$STATE/client-ipv4.json"

echo '--- validate ---'
docker run --rm --user 0:0 -v "$STATE/server.json:/etc/xray/config.json:ro" "$IMAGE" run -test -config=/etc/xray/config.json >/dev/null
docker run --rm --user 0:0 -v "$STATE/client-ipv4.json:/etc/xray/config.json:ro" "$IMAGE" run -test -config=/etc/xray/config.json >/dev/null
echo configs=valid

echo '--- restart whitelist server only ---'
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
docker run -d --name "$CONTAINER" --restart unless-stopped --user 0:0 \
  -p '127.0.0.1:47006:47006/tcp' \
  -v "$STATE/server.json:/etc/xray/config.json:ro" \
  "$IMAGE" run -config=/etc/xray/config.json >/dev/null
sleep 2
[ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER")" = true ]
echo wl_server=running

echo '--- test IPv4 client through public 443 ---'
docker rm -f "$TEST" >/dev/null 2>&1 || true
docker run -d --name "$TEST" --network host --user 0:0 \
  -v "$STATE/client-ipv4.json:/etc/xray/config.json:ro" \
  "$IMAGE" run -config=/etc/xray/config.json >/dev/null
cleanup(){ docker rm -f "$TEST" >/dev/null 2>&1 || true; }
trap cleanup EXIT
sleep 2
for url in https://api.ipify.org https://telegram.org/ https://github.com/ https://www.gstatic.com/generate_204; do
  printf '%s ' "$url"
  curl -sS -o /dev/null --max-time 15 --socks5-hostname 127.0.0.1:10918 \
    -w 'code=%{http_code} total=%{time_total}\n' "$url" || echo failed
done
EXIT_IP="$(curl -fsS --max-time 15 --socks5-hostname 127.0.0.1:10918 https://api.ipify.org || true)"
[ "$EXIT_IP" = "$SERVER_IP" ]
echo exit_ip_ok=yes

echo '--- preservation ---'
echo "main_vless=$(docker inspect -f '{{.State.Running}}' xray-vless-47005 2>/dev/null || echo missing)"
echo "awg31=$(docker inspect -f '{{.State.Running}}' amnezia-awg31-mobile 2>/dev/null || echo missing)"
for domain in bot.pronexsbp.ru enihub.ru; do
  code="$(curl -sS -o /dev/null --max-time 8 --resolve "$domain:443:127.0.0.1" -w '%{http_code}' "https://$domain/" || true)"
  echo "$domain=http_$code"
done
echo WL_IPV4_PROFILE_READY
