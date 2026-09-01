#!/usr/bin/env bash
set -euo pipefail
STATE='/root/vless-reality-47005'
mkdir -p control/generated
rm -f control/generated/vless-client.creds.enc.b64

if [ ! -s "$STATE/client.json" ]; then
  echo 'client_state=missing'
  exit 40
fi

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

python3 - <<'PY' > "$STATE/client-creds.json"
import json
p='/root/vless-reality-47005/client.json'
with open(p,'r',encoding='utf-8') as f:
    d=json.load(f)
o=d['outbounds'][0]
print(json.dumps({
    'id': o['settings']['vnext'][0]['users'][0]['id'],
    'publicKey': o['streamSettings']['realitySettings']['publicKey']
}, separators=(',',':')))
PY
chmod 600 "$STATE/client-creds.json"

openssl pkeyutl -encrypt -pubin -inkey "$STATE/handoff.pub.pem" \
  -pkeyopt rsa_padding_mode:oaep \
  -pkeyopt rsa_oaep_md:sha256 \
  -pkeyopt rsa_mgf1_md:sha256 \
  -in "$STATE/client-creds.json" 2>/dev/null | base64 -w0 > control/generated/vless-client.creds.enc.b64
rm -f "$STATE/handoff.pub.pem" "$STATE/client-creds.json"

echo 'rsa_credentials_handoff=ready'
echo "vless_container=$(docker inspect -f '{{.State.Running}}' xray-vless-47005 2>/dev/null || echo missing)"
echo "tcp47005=$(ss -ltnH | grep -c ':47005 ' || true)"
echo "awg31_mobile=$(docker inspect -f '{{.State.Running}}' amnezia-awg31-mobile 2>/dev/null || echo missing)"
echo "legacy_xray=$(docker inspect -f '{{.State.Running}}' amnezia-xray 2>/dev/null || echo missing)"
echo VLESS_CREDS_HANDOFF_OK
