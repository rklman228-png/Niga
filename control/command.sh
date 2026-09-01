#!/usr/bin/env bash
set -euo pipefail

IMAGE='ghcr.io/xtls/xray-core:26.3.27'
STATE='/root/vless-reality-47005'
SERVER_IP='143.246.197.187'
PORT='47005'
CONTAINER='xray-vless-47005'
TEST_CONTAINER='xray-vless-client2-test'
HANDOFF='control/generated/vless2.uuid.enc.b64'

mkdir -p control/generated
rm -f "$HANDOFF"

if [ ! -s "$STATE/server.json" ] || [ ! -s "$STATE/client.json" ]; then
  echo 'vless_state=missing'
  exit 40
fi

cp -a "$STATE/server.json" "$STATE/server.json.before-client2"
UUID2="$(cat /proc/sys/kernel/random/uuid)"
export UUID2

python3 - <<'PY'
import json, os
state='/root/vless-reality-47005'
uuid2=os.environ['UUID2']
with open(state+'/server.json','r',encoding='utf-8') as f:
    s=json.load(f)
clients=s['inbounds'][0]['settings']['clients']
if not any(c.get('id')==uuid2 for c in clients):
    clients.append({'id':uuid2,'flow':'xtls-rprx-vision'})
with open(state+'/server.json','w',encoding='utf-8') as f:
    json.dump(s,f,ensure_ascii=False,separators=(',',':'))

with open(state+'/client.json','r',encoding='utf-8') as f:
    c=json.load(f)
# isolate test ports so we do not collide with anything already listening
for ib in c.get('inbounds',[]):
    if ib.get('protocol')=='socks': ib['port']=10908
    elif ib.get('protocol')=='http': ib['port']=10909
c['outbounds'][0]['settings']['vnext'][0]['users'][0]['id']=uuid2
with open(state+'/client2-test.json','w',encoding='utf-8') as f:
    json.dump(c,f,ensure_ascii=False,separators=(',',':'))
PY
chmod 600 "$STATE/server.json" "$STATE/client2-test.json"

echo '===== validate updated VLESS server ====='
docker run --rm --user 0:0 -v "$STATE/server.json:/etc/xray/config.json:ro" "$IMAGE" run -test -config=/etc/xray/config.json >/dev/null
docker run --rm --user 0:0 -v "$STATE/client2-test.json:/etc/xray/config.json:ro" "$IMAGE" run -test -config=/etc/xray/config.json >/dev/null
echo 'configs=valid'

echo '===== restart VLESS with second client ====='
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
docker run -d \
  --name "$CONTAINER" \
  --restart unless-stopped \
  --user 0:0 \
  -p "$PORT:$PORT/tcp" \
  -v "$STATE/server.json:/etc/xray/config.json:ro" \
  "$IMAGE" run -config=/etc/xray/config.json >/dev/null
sleep 2
if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || echo false)" != true ]; then
  echo 'vless_container=failed'
  cp -a "$STATE/server.json.before-client2" "$STATE/server.json"
  exit 41
fi
echo 'vless_container=running'

echo '===== test second client through public endpoint ====='
docker rm -f "$TEST_CONTAINER" >/dev/null 2>&1 || true
docker run -d --name "$TEST_CONTAINER" --network host --user 0:0 \
  -v "$STATE/client2-test.json:/etc/xray/config.json:ro" \
  "$IMAGE" run -config=/etc/xray/config.json >/dev/null
cleanup() { docker rm -f "$TEST_CONTAINER" >/dev/null 2>&1 || true; rm -f "$STATE/client2-test.json"; }
trap cleanup EXIT
sleep 3
TEST_IP="$(curl -fsS --max-time 15 --socks5-hostname 127.0.0.1:10908 https://api.ipify.org || true)"
if [ "$TEST_IP" != "$SERVER_IP" ]; then
  echo "client2_test=failed result=${TEST_IP:-none}"
  exit 42
fi
echo 'client2_test=ok'
echo "exit_ip=$TEST_IP"

cat > "$STATE/client2-handoff.pub.pem" <<'PUBEOF'
-----BEGIN PUBLIC KEY-----
MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA43zzisuMnxtm6yxmjecE
4DDzkvh5BZppzf8AisTZCY7PNtIQHPbSUD6WUbpuc0VVMN+MRwEptt+MjWNA85x4
Wa7w1lUC5GKE1GMdmYtvzcoNB+dCPUss7ag5PZmDfUDJhV+eX3z/JgLyyORSAOdt
+8ggK6KIQfXXnuMdeLut6ZPHZvzzLNvrVCqUICzm8Zylu1AGmLSKlluT20zKmqYA
ySSz7z7hTbVji0uZ+d4aA2uQoSbfH1MmtnTI6X0OLTNYQGONi62eyix+XWgUryD1
apYku3PewV2VycxyTB4y/L6K4lILAMxitegTt5bb6MDfsUwy+1HKZVNrgNTIdY5+
5ktIOQP2WRXye+wfhdAAbzn75beNI9TYowJ2RuNCh40OWM/mkZCxmU1I8X36K30F
/F9uddElBA/gwH/Dia19NpBFIZMBYbBvi+SHdoaicNjkyIgWcVVchZa7x1TuYDAO
AtB4Rc6vTPijBlvYPyxoee5el250zze8gbrNeUHd9pAUWksIpBZx7tw3oME5Dxwg
PanAsdwaxowMuTJSYvR7W9zXxj1ZFrMRs6/N4Dt1DEdzo16tGhVGEqkMsSW6YpMU
mAJDf9uLzKmoTNhj6LEweV2jEy3nLr+kkF0oIwaDi1fMoOZPFPOH/KIVqixFf9nY
WJX0HB5Udyo7TF5ELyIXOvkCAwEAAQ==
-----END PUBLIC KEY-----
PUBEOF
printf '%s' "$UUID2" | openssl pkeyutl -encrypt -pubin -inkey "$STATE/client2-handoff.pub.pem" \
  -pkeyopt rsa_padding_mode:oaep \
  -pkeyopt rsa_oaep_md:sha256 \
  -pkeyopt rsa_mgf1_md:sha256 2>/dev/null | base64 -w0 > "$HANDOFF"
rm -f "$STATE/client2-handoff.pub.pem"
unset UUID2

echo 'uuid2_handoff=ready'
echo "vless_clients=$(python3 - <<'PY'
import json
with open('/root/vless-reality-47005/server.json') as f: d=json.load(f)
print(len(d['inbounds'][0]['settings']['clients']))
PY
)"
echo "vless_tcp47005=$(ss -ltnH | grep -c ':47005 ' || true)"
echo "awg31_mobile=$(docker inspect -f '{{.State.Running}}' amnezia-awg31-mobile 2>/dev/null || echo missing)"
echo "legacy_xray=$(docker inspect -f '{{.State.Running}}' amnezia-xray 2>/dev/null || echo missing)"
echo VLESS_CLIENT2_OK
