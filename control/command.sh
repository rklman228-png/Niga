#!/usr/bin/env bash
set -euo pipefail

IMAGE='ghcr.io/xtls/xray-core:26.3.27'
STATE='/root/vless-reality-47005'
SERVER_IP='143.246.197.187'
PORT='47005'
SNI='akamai.com'
CONTAINER='xray-vless-47005'
TEST_CONTAINER='xray-vless-client-test'

mkdir -p "$STATE" control/generated
chmod 700 "$STATE"
rm -f control/generated/vless-client.json.enc.b64 control/generated/vless-client.key.enc.b64

echo '===== pull current pinned Xray ====='
docker pull "$IMAGE" >/dev/null
printf 'image=%s\n' "$IMAGE"

echo '===== generate server/client credentials locally on VPS ====='
UUID="$(cat /proc/sys/kernel/random/uuid)"
KEYOUT="$(docker run --rm "$IMAGE" x25519 2>/dev/null)"
PRIVATE_KEY="$(printf '%s\n' "$KEYOUT" | sed -nE 's/^(Private key|PrivateKey):[[:space:]]*//p' | head -n1)"
PUBLIC_KEY="$(printf '%s\n' "$KEYOUT" | sed -nE 's/^(Password \(PublicKey\)|Public key|PublicKey|Password):[[:space:]]*//p' | head -n1)"
if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
  echo 'x25519_parse=failed'
  exit 20
fi
printf 'uuid_generated=yes\nx25519_generated=yes\n'

cat > "$STATE/server.json" <<EOF
{
  "log": {"loglevel": "warning"},
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": $PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          {"id": "$UUID", "flow": "xtls-rprx-vision"}
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "dest": "$SNI:443",
          "serverNames": ["$SNI"],
          "privateKey": "$PRIVATE_KEY",
          "shortIds": [""]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "routeOnly": true
      }
    }
  ],
  "outbounds": [
    {"protocol": "freedom", "tag": "direct"},
    {"protocol": "blackhole", "tag": "block"}
  ]
}
EOF
chmod 600 "$STATE/server.json"

cat > "$STATE/client.json" <<EOF
{
  "burstObservatory": {
    "pingConfig": {
      "connectivity": "",
      "destination": "http://www.gstatic.com/generate_204",
      "interval": "1m",
      "sampling": 1,
      "timeout": "3s"
    },
    "subjectSelector": ["proxy"]
  },
  "dns": {
    "queryStrategy": "UseIP",
    "servers": ["1.1.1.1", "1.0.0.1"]
  },
  "inbounds": [
    {
      "listen": "127.0.0.1",
      "port": 10808,
      "protocol": "socks",
      "settings": {"auth": "noauth", "udp": true},
      "sniffing": {
        "destOverride": ["http", "tls", "quic"],
        "enabled": true,
        "routeOnly": false
      },
      "tag": "socks"
    },
    {
      "listen": "127.0.0.1",
      "port": 10809,
      "protocol": "http",
      "settings": {"allowTransparent": false},
      "sniffing": {
        "destOverride": ["http", "tls", "quic"],
        "enabled": true,
        "routeOnly": false
      },
      "tag": "http"
    }
  ],
  "outbounds": [
    {
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "$SERVER_IP",
            "port": $PORT,
            "users": [
              {
                "encryption": "none",
                "flow": "xtls-rprx-vision",
                "id": "$UUID"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "realitySettings": {
          "fingerprint": "firefox",
          "publicKey": "$PUBLIC_KEY",
          "serverName": "$SNI"
        },
        "security": "reality",
        "tcpSettings": {}
      },
      "tag": "proxy"
    },
    {"protocol": "freedom", "tag": "direct"},
    {"protocol": "blackhole", "tag": "block"}
  ],
  "remarks": "⚡️VLESS REALITY 143.246.197.187",
  "routing": {
    "balancers": [
      {
        "fallbackTag": "direct",
        "selector": ["proxy"],
        "strategy": {
          "settings": {
            "baselines": ["1s"],
            "expected": 2,
            "maxRTT": "1s",
            "tolerance": 0.01
          },
          "type": "leastLoad"
        },
        "tag": "Super_Balancer"
      }
    ],
    "domainMatcher": "hybrid",
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {"outboundTag": "block", "protocol": ["bittorrent"], "type": "field"},
      {"domain": ["max.ru", "geosite:category-ru"], "outboundTag": "direct", "type": "field"},
      {"ip": ["geoip:ru"], "outboundTag": "direct", "type": "field"},
      {"balancerTag": "Super_Balancer", "network": "tcp,udp", "type": "field"}
    ]
  }
}
EOF
chmod 600 "$STATE/client.json"

echo '===== validate configs ====='
docker run --rm -v "$STATE/server.json:/etc/xray/config.json:ro" "$IMAGE" run -test -config /etc/xray/config.json >/dev/null
docker run --rm -v "$STATE/client.json:/etc/xray/config.json:ro" "$IMAGE" run -test -config /etc/xray/config.json >/dev/null
printf 'server_config=valid\nclient_config=valid\n'

echo '===== deploy isolated VLESS REALITY ====='
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
docker run -d \
  --name "$CONTAINER" \
  --restart unless-stopped \
  -p "$PORT:$PORT/tcp" \
  -v "$STATE/server.json:/etc/xray/config.json:ro" \
  "$IMAGE" run -config /etc/xray/config.json >/dev/null
sleep 2
RUNNING="$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || echo false)"
if [ "$RUNNING" != true ]; then
  echo 'server_container=failed'
  docker logs --tail 30 "$CONTAINER" 2>&1 | sed -E 's/[A-Za-z0-9_-]{30,}/[redacted]/g' || true
  exit 21
fi
printf 'server_container=running\n'

if ! ss -ltnH | grep -qE "[:.]${PORT}[[:space:]]"; then
  echo 'tcp47005=not_listening'
  exit 22
fi
printf 'tcp47005=listening\n'

echo '===== end-to-end test with exact client JSON ====='
docker rm -f "$TEST_CONTAINER" >/dev/null 2>&1 || true
docker run -d --name "$TEST_CONTAINER" --network host \
  -v "$STATE/client.json:/etc/xray/config.json:ro" \
  "$IMAGE" run -config /etc/xray/config.json >/dev/null
cleanup_test() { docker rm -f "$TEST_CONTAINER" >/dev/null 2>&1 || true; }
trap cleanup_test EXIT
sleep 3
TEST_IP="$(curl -fsS --max-time 15 --socks5-hostname 127.0.0.1:10808 https://api.ipify.org || true)"
if [ "$TEST_IP" != "$SERVER_IP" ]; then
  echo "tunnel_test=failed result=${TEST_IP:-none}"
  docker logs --tail 30 "$TEST_CONTAINER" 2>&1 | sed -E 's/[A-Za-z0-9_-]{30,}/[redacted]/g' || true
  exit 23
fi
printf 'tunnel_test=ok\nexit_ip=%s\n' "$TEST_IP"
cleanup_test
trap - EXIT

echo '===== encrypted one-time client handoff ====='
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
chmod 600 control/generated/vless-client.json.enc.b64 control/generated/vless-client.key.enc.b64
rm -f "$STATE/handoff.pub.pem"
unset PASS UUID PRIVATE_KEY PUBLIC_KEY KEYOUT
printf 'secure_handoff=ready\n'

echo '===== preservation checks ====='
echo "legacy_awg0=$([ -d /sys/class/net/awg0 ] && echo up || echo missing)"
echo "legacy_awg1=$([ -d /sys/class/net/awg1 ] && echo up || echo missing)"
echo "awg31_mobile=$(docker inspect -f '{{.State.Running}}' amnezia-awg31-mobile 2>/dev/null || echo missing)"
echo "legacy_xray=$(docker inspect -f '{{.State.Running}}' amnezia-xray 2>/dev/null || echo missing)"
echo VLESS_REALITY_DEPLOY_OK
