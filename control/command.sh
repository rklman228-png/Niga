#!/usr/bin/env bash
set -euo pipefail

IMAGE='ghcr.io/xtls/xray-core:26.3.27'
SERVER='/root/vless-reality-47005/server.json'
CONTAINER='xray-vless-47005'
TEST='xray-vless-new-client-test'
HANDOFF='control/generated/main-vless-new.enc.b64'
BACKUP="/root/vless-reality-47005/server.json.bak-$(date -u +%Y%m%dT%H%M%SZ)"
PUBLIC_KEY='xRR0sT5hpLbK7w6cR-r0bkRRfzSn5WMCPcT0mYKK1Ug'
SNI='akamai.com'
SERVER_IP='143.246.197.187'
PORT=47005

mkdir -p control/generated
rm -f "$HANDOFF"
cp -a "$SERVER" "$BACKUP"
NEW_UUID="$(cat /proc/sys/kernel/random/uuid)"
export NEW_UUID

echo '===== add new client to main VLESS ====='
python3 - "$SERVER" <<'PY'
import json, os, sys
p=sys.argv[1]
u=os.environ['NEW_UUID']
with open(p) as f: d=json.load(f)
for ib in d.get('inbounds',[]):
    if ib.get('protocol')=='vless':
        clients=ib.setdefault('settings',{}).setdefault('clients',[])
        if not any(c.get('id')==u for c in clients):
            clients.append({'id':u,'flow':'xtls-rprx-vision'})
        print('clients_after='+str(len(clients)))
        break
else:
    raise SystemExit('no_vless_inbound')
with open(p,'w') as f: json.dump(d,f,separators=(',',':'))
PY
chmod 600 "$SERVER"

echo '===== validate and restart ====='
if ! docker run --rm --user 0:0 -v "$SERVER:/etc/xray/config.json:ro" "$IMAGE" run -test -config=/etc/xray/config.json >/dev/null; then
  cp -a "$BACKUP" "$SERVER"
  echo config_validation=failed
  exit 61
fi
docker restart "$CONTAINER" >/dev/null
sleep 2
if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || echo false)" != true ]; then
  cp -a "$BACKUP" "$SERVER"
  docker restart "$CONTAINER" >/dev/null 2>&1 || true
  echo main_vless_restart=failed
  exit 62
fi
echo main_vless=running

echo '===== prove new credential ====='
TMP='/root/vless-reality-47005/new-client-test.json'
cat > "$TMP" <<EOF
{"log":{"loglevel":"warning"},"inbounds":[{"listen":"127.0.0.1","port":10919,"protocol":"socks","settings":{"auth":"noauth","udp":true}}],"outbounds":[{"protocol":"vless","settings":{"vnext":[{"address":"$SERVER_IP","port":$PORT,"users":[{"id":"$NEW_UUID","encryption":"none","flow":"xtls-rprx-vision"}]}]},"streamSettings":{"network":"tcp","security":"reality","realitySettings":{"serverName":"$SNI","fingerprint":"firefox","publicKey":"$PUBLIC_KEY"}}}]}
EOF
chmod 600 "$TMP"
docker rm -f "$TEST" >/dev/null 2>&1 || true
docker run -d --name "$TEST" --network host --user 0:0 -v "$TMP:/etc/xray/config.json:ro" "$IMAGE" run -config=/etc/xray/config.json >/dev/null
cleanup(){ docker rm -f "$TEST" >/dev/null 2>&1 || true; rm -f "$TMP"; }
trap cleanup EXIT
sleep 2
TEST_IP="$(curl -fsS --max-time 20 --socks5-hostname 127.0.0.1:10919 https://api.ipify.org || true)"
if [ "$TEST_IP" != "$SERVER_IP" ]; then
  cp -a "$BACKUP" "$SERVER"
  docker restart "$CONTAINER" >/dev/null 2>&1 || true
  echo new_client_test=failed
  exit 63
fi
echo new_client_test=ok
echo exit_ip_ok=yes

echo '===== secure handoff ====='
META='/root/vless-reality-47005/new-client-meta.json'
printf '{"uuid":"%s"}' "$NEW_UUID" > "$META"
chmod 600 "$META"
PUB='/root/vless-reality-47005/handoff.pub.pem'
cat > "$PUB" <<'PUBEOF'
-----BEGIN PUBLIC KEY-----
MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAlK5ky74BDxO6piLtDSlj
6bJDo5dZjbhabLYfYLJs+Pf277wU6JkVKvPZJIdC5XRA4m57DIg+nNQ0Ksy6IuqC
1ZtCzL86nL5KGj1mjHgBLv9kc5bDcTthfyEhOlRjRZ3w5dpTlMjltapDzP/qmWza
ObeLrdPZViA2hefmjQ8KZZASJrq5BOrz/FYcrp58EGFgmowMa5q1YRFCw9KOOKTb
GIqt9UZeatOaSuS2GYWMfItPNxL34bTnsWwSKdkMV3uzWk3INSQw/aA6OduqhYyP
0sbf+XMv3hQSE4ReJu8tl18G8BamVzkGYEtLhdNIgK/kl1fAIdc1DSfXnf0tOFcZ
2lcHKAnkwFHaDAEIi3d5wHTzpZNkGql+By2RFAVK2/R47Smfq7Y2QY4ynY2b60RU
0Ngw9c+ujHAWGQoTkCfZiCLtk1kFQzT/ior9AbVdwBsIOBEk3bhp8HX0o8XPs8Lp
3ywx7pTvucwH147+iBldKEWqHo1CFlRiKoa9L121lEqAYfVl0cUoiFFJeuC/XnhR
+R6JK2TcdpCWgwEtmmFRl87MZwBALfNGpuR+ybkHFparVQfUwuwm5+SaUbjhodkc
P/LzjhH5CJbiF1tU1Ba4NoncsO3V4SeRfOv09J53rHoWTk5kmARKhaQu16Wn2R/g
iKOPsC5oFKWKBP8Bm4Mzr2cCAwEAAQ==
-----END PUBLIC KEY-----
PUBEOF
openssl pkeyutl -encrypt -pubin -inkey "$PUB" -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256 -pkeyopt rsa_mgf1_md:sha256 -in "$META" 2>/dev/null | base64 -w0 > "$HANDOFF"
rm -f "$PUB" "$META"
unset NEW_UUID

echo secure_handoff=ready
echo "main_vless=$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || echo missing)"
echo "awg31=$(docker inspect -f '{{.State.Running}}' amnezia-awg31-mobile 2>/dev/null || echo missing)"
echo NEW_MAIN_VLESS_READY
