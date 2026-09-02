#!/usr/bin/env bash
set -euo pipefail

IMAGE='ghcr.io/xtls/xray-core:26.3.27'
SERVER='/root/vless-reality-47005/server.json'
CONTAINER='xray-vless-47005'
TEST='xray-vless-extra-client-test'
HANDOFF='control/generated/main-vless-extra.enc.b64'
SERVER_IP='143.246.197.187'
PORT=47005
PUBLIC_KEY='xRR0sT5hpLbK7w6cR-r0bkRRfzSn5WMCPcT0mYKK1Ug'
SNI='akamai.com'
BACKUP="${SERVER}.bak-$(date -u +%Y%m%dT%H%M%SZ)"

mkdir -p control/generated
rm -f "$HANDOFF"
cp -a "$SERVER" "$BACKUP"
NEW_UUID="$(cat /proc/sys/kernel/random/uuid)"
export NEW_UUID

echo '===== add client ====='
python3 - "$SERVER" <<'PY'
import json, os, sys
p=sys.argv[1]
u=os.environ['NEW_UUID']
with open(p) as f: d=json.load(f)
for ib in d.get('inbounds',[]):
    if ib.get('protocol')=='vless':
        clients=ib.setdefault('settings',{}).setdefault('clients',[])
        clients.append({'id':u,'flow':'xtls-rprx-vision'})
        print('clients_after='+str(len(clients)))
        break
else:
    raise SystemExit('no_vless_inbound')
with open(p,'w') as f: json.dump(d,f,separators=(',',':'))
PY
chmod 600 "$SERVER"

echo '===== validate/restart ====='
if ! docker run --rm --user 0:0 -v "$SERVER:/etc/xray/config.json:ro" "$IMAGE" run -test -config=/etc/xray/config.json >/dev/null; then
  cp -a "$BACKUP" "$SERVER"
  exit 61
fi
docker restart "$CONTAINER" >/dev/null
sleep 2
[ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || echo false)" = true ]

echo '===== prove new client ====='
TMP='/root/vless-reality-47005/extra-client-test.json'
cat > "$TMP" <<EOF
{"log":{"loglevel":"warning"},"inbounds":[{"listen":"127.0.0.1","port":10921,"protocol":"socks","settings":{"auth":"noauth","udp":true}}],"outbounds":[{"protocol":"vless","settings":{"vnext":[{"address":"$SERVER_IP","port":$PORT,"users":[{"id":"$NEW_UUID","encryption":"none","flow":"xtls-rprx-vision"}]}]},"streamSettings":{"network":"tcp","security":"reality","realitySettings":{"serverName":"$SNI","fingerprint":"firefox","publicKey":"$PUBLIC_KEY"}}}]}
EOF
docker rm -f "$TEST" >/dev/null 2>&1 || true
docker run -d --name "$TEST" --network host --user 0:0 -v "$TMP:/etc/xray/config.json:ro" "$IMAGE" run -config=/etc/xray/config.json >/dev/null
cleanup(){ docker rm -f "$TEST" >/dev/null 2>&1 || true; rm -f "$TMP"; }
trap cleanup EXIT
sleep 2
TEST_IP="$(curl -fsS --max-time 20 --socks5-hostname 127.0.0.1:10921 https://api.ipify.org || true)"
if [ "$TEST_IP" != "$SERVER_IP" ]; then
  cp -a "$BACKUP" "$SERVER"
  docker restart "$CONTAINER" >/dev/null 2>&1 || true
  echo new_client_test=failed
  exit 62
fi
echo new_client_test=ok
echo exit_ip_ok=yes

echo '===== secure handoff ====='
META='/root/vless-reality-47005/extra-client-meta.json'
printf '{"uuid":"%s"}' "$NEW_UUID" > "$META"
PUB='/root/vless-reality-47005/handoff-extra.pub.pem'
cat > "$PUB" <<'PUBEOF'
-----BEGIN PUBLIC KEY-----
MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAwbu0oB22eUzsnXqKYuev
8uGQdbWr2KdQbhxKHNtgguevuPYf3O0xOgonzaID95qE4nbxLLMWUWfQm9udQ5LY
SXpv3gVU6i9Qdwid41TFnipcBcPfqPkuRFE4F6wDFq9URCPHDoN0uItRVGgD/KMU
FdgqckxewIPuEHGl7H8xjnRNo9Nq7uDvTUH2zVRzL6YS+MFWhm9yTRJZ+0g0Mb13
3hKEVzoBWEL6AzVqNStAUnoNp8r4LlMio/tt58eDXNqO3Sc93+EL1zj+7hFGTExC
Lu270RonP/C+ersey2BBQJEz2XA1Os5LBpBJGmR2FM8FPjRx+sm2o/GCnxZ9vrTo
fjjQVGW+Yw4jyI+9ZD1A/36cDQUSbFYklrOfIRZLfXZ0pX69BaMIUPd3J1RnkMgz
OEKdxQmwmEtQHYSDnrm96yT6Q+CtxHDq8s0kYvKUolTTV/5RhuEVipfRpms1J3mp
c/8GLhVYvYTupufQrP/OyIo4wFYQ/rfqmze8DpPVEKvpM0ltopvbXaFvoqqWqD5P
tlxHAt1Xc/H27N1PIA7LYjqOdWU29l3663bfkYVO9qVXhzoy/0zAl1YCAwDWm7/y
MPkFm+ZNd234IJ6OcAIhG2i60WR4N4ypcavq0YMCVjlKLZjPf2P1BqlwrouZv18K
vQlJZ4RUA/itJ+l2zxfVD80CAwEAAQ==
-----END PUBLIC KEY-----
PUBEOF
openssl pkeyutl -encrypt -pubin -inkey "$PUB" -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256 -pkeyopt rsa_mgf1_md:sha256 -in "$META" 2>/dev/null | base64 -w0 > "$HANDOFF"
rm -f "$PUB" "$META"
unset NEW_UUID

echo secure_handoff=ready
echo "main_vless=$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || echo missing)"
echo "awg31=$(docker inspect -f '{{.State.Running}}' amnezia-awg31-mobile 2>/dev/null || echo missing)"
echo EXTRA_MAIN_VLESS_READY
