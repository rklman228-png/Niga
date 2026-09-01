#!/usr/bin/env bash
set -euo pipefail

IMAGE='ghcr.io/xtls/xray-core:26.3.27'
STATE='/root/vless-reality-47005'
SERVER_IP='143.246.197.187'
PORT='47005'
CONTAINER='xray-vless-47005'
TEST_CONTAINER='xray-vless-client-test'

mkdir -p control/generated
rm -f control/generated/vless-client.json.enc.b64 control/generated/vless-client.key.enc.b64

if [ ! -s "$STATE/server.json" ] || [ ! -s "$STATE/client.json" ]; then
  echo 'state_config=missing'
  exit 30
fi

echo '===== normalize current REALITY server fields ====='
python3 - <<'PY'
import json
p='/root/vless-reality-47005/server.json'
with open(p,'r',encoding='utf-8') as f:
    d=json.load(f)
r=d['inbounds'][0]['streamSettings']['realitySettings']
if 'dest' in r and 'target' not in r:
    r['target']=r.pop('dest')
r['minClientVer']='24.1.1'
with open(p,'w',encoding='utf-8') as f:
    json.dump(d,f,ensure_ascii=False,separators=(',',':'))
PY
chmod 600 "$STATE/server.json" "$STATE/client.json"
echo 'server_fields=normalized'

echo '===== validate configs as container root ====='
for f in server.json client.json; do
  set +e
  OUT="$(docker run --rm --user 0:0 -v "$STATE/$f:/etc/xray/config.json:ro" "$IMAGE" run -test -config=/etc/xray/config.json 2>&1)"
  CODE=$?
  set -e
  if [ "$CODE" -ne 0 ]; then
    echo "$f=invalid"
    printf '%s\n' "$OUT" | sed -E 's/[A-Za-z0-9_+\/-]{28,}={0,2}/[redacted]/g'
    exit "$CODE"
  fi
  echo "$f=valid"
done

echo '===== deploy isolated VLESS REALITY ====='
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
docker run -d \
  --name "$CONTAINER" \
  --restart unless-stopped \
  --user 0:0 \
  -p "$PORT:$PORT/tcp" \
  -v "$STATE/server.json:/etc/xray/config.json:ro" \
  "$IMAGE" run -config=/etc/xray/config.json >/dev/null
sleep 2
RUNNING="$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || echo false)"
if [ "$RUNNING" != true ]; then
  echo 'server_container=failed'
  docker logs --tail 30 "$CONTAINER" 2>&1 | sed -E 's/[A-Za-z0-9_+\/-]{28,}={0,2}/[redacted]/g' || true
  exit 31
fi
echo 'server_container=running'

if ss -ltnH | grep -qE "[:.]${PORT}[[:space:]]"; then
  echo 'tcp47005=listening'
else
  echo 'tcp47005=not_listening'
  exit 32
fi

echo '===== end-to-end test exact client config ====='
docker rm -f "$TEST_CONTAINER" >/dev/null 2>&1 || true
docker run -d \
  --name "$TEST_CONTAINER" \
  --network host \
  --user 0:0 \
  -v "$STATE/client.json:/etc/xray/config.json:ro" \
  "$IMAGE" run -config=/etc/xray/config.json >/dev/null
cleanup_test() { docker rm -f "$TEST_CONTAINER" >/dev/null 2>&1 || true; }
trap cleanup_test EXIT
sleep 3
TEST_IP="$(curl -fsS --max-time 15 --socks5-hostname 127.0.0.1:10808 https://api.ipify.org || true)"
if [ "$TEST_IP" != "$SERVER_IP" ]; then
  echo "tunnel_test=failed result=${TEST_IP:-none}"
  docker logs --tail 40 "$TEST_CONTAINER" 2>&1 | sed -E 's/[A-Za-z0-9_+\/-]{28,}={0,2}/[redacted]/g' || true
  exit 33
fi
echo 'tunnel_test=ok'
echo "exit_ip=$TEST_IP"
cleanup_test
trap - EXIT

echo '===== encrypted one-time handoff ====='
cat > "$STATE/handoff.pub.pem" <<'PUBEOF'
-----BEGIN PUBLIC KEY-----
MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA1a2xknp9WnDE9wjtiSZ0
KjL7z8xTwxIF3oKbCeErT512UWBK+slTz22D6TgTibnFjx07BpbLU2SQybLegubM
1y/r0ChUb+0zR9rdFrN693XPjNjI/BUfxJzViLuGa7WwoRCt5+y92vgrRmCOz3ph
vYBWG4xt737txQjEJYw8Ft25vJaL6XtNJlQRkbmjZg4eM+Fxv5uCqGMlS30DJAah
bWciId5I8Z6S5OGkq53cGrRid8OFSy7KGZfCX160e9bc6m6RkDC8faEheFEcYv+W
HwXhmPqFPnQZiNI5IhdXFB4WakCW4eYsSufat91wJlzxzRGSQG41j2B/8DxMA5xx
I/tFylBnrVVF4kIo5HUAiXcJlnM9e8epWA4h7YNbpyXfAGykQwSh3sYQM5ryKwgW
QDqCAhOVj7dNmbCwhbz5KerMD1MoZfouewZeL2T3Npb5g2FstdkWO9bvsT1NyTEG
6qr011HNt5VFcPaFEeyJ9hF310ql1GI3sPV7m9RE57lelwqqzssLbO6wc1YTcyUl
kM501eyHOOSJJkbMuqogYSRNJ4M1UvjvEYipOKueW/cshUlo3qtowjkHg4lyUe6L
XnFe+hxlWPxbW49w2ydNvOiDq/JY06ITVkLvVDDxMjQNiGnMyqBTKV4sqOawSY/M
zmi2SPuxar/qCKywDTdboS8CAwEAAQ==
-----END PUBLIC KEY-----
PUBEOF
PASS="$(openssl rand -base64 48 | tr -d '\n')"
openssl enc -aes-256-cbc -salt -pbkdf2 -iter 200000 \
  -pass pass:"$PASS" -in "$STATE/client.json" 2>/dev/null | base64 -w0 > control/generated/vless-client.json.enc.b64
printf '%s' "$PASS" | openssl pkeyutl -encrypt -pubin -inkey "$STATE/handoff.pub.pem" \
  -pkeyopt rsa_padding_mode:oaep \
  -pkeyopt rsa_oaep_md:sha256 \
  -pkeyopt rsa_mgf1_md:sha256 2>/dev/null | base64 -w0 > control/generated/vless-client.key.enc.b64
rm -f "$STATE/handoff.pub.pem"
unset PASS

echo 'secure_handoff=ready'
echo '===== preservation checks ====='
echo "legacy_awg0=$([ -d /sys/class/net/awg0 ] && echo up || echo missing)"
echo "legacy_awg1=$([ -d /sys/class/net/awg1 ] && echo up || echo missing)"
echo "awg31_mobile=$(docker inspect -f '{{.State.Running}}' amnezia-awg31-mobile 2>/dev/null || echo missing)"
echo "legacy_xray=$(docker inspect -f '{{.State.Running}}' amnezia-xray 2>/dev/null || echo missing)"
echo VLESS_REALITY_DEPLOY_OK
