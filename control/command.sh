#!/usr/bin/env bash
set -euo pipefail
umask 077

STATE=/root/amnezia-mobile-reality
URI="$(cat "$STATE/client.txt")"
UUID="$(printf '%s' "$URI" | sed -E 's#^vless://([^@]+)@.*#\1#')"
PUBLIC="$(printf '%s' "$URI" | sed -E 's/.*[?&]pbk=([^&]+).*/\1/')"
SHORT="$(printf '%s' "$URI" | sed -E 's/.*[?&]sid=([^&]+).*/\1/')"
SNI="www.microsoft.com"
TEST=/root/amnezia-mobile-reality/selftest-client.json

cat > "$TEST" <<JSON
{
  "log": {"loglevel": "warning"},
  "inbounds": [
    {
      "listen": "127.0.0.1",
      "port": 10888,
      "protocol": "socks",
      "settings": {"udp": false}
    }
  ],
  "outbounds": [
    {
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "143.246.197.187",
            "port": 8443,
            "users": [
              {
                "id": "$UUID",
                "encryption": "none",
                "flow": "xtls-rprx-vision"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "serverName": "$SNI",
          "fingerprint": "chrome",
          "publicKey": "$PUBLIC",
          "shortId": "$SHORT"
        }
      }
    }
  ]
}
JSON
chmod 600 "$TEST"

docker rm -f xray-mobile-selftest >/dev/null 2>&1 || true
docker run -d --name xray-mobile-selftest --network host \
  -v "$TEST:/tmp/client.json:ro" \
  --entrypoint /usr/bin/xray \
  amnezia-xray run -config /tmp/client.json >/dev/null
trap 'docker rm -f xray-mobile-selftest >/dev/null 2>&1 || true; rm -f "$TEST"' EXIT
sleep 2

echo '===== authenticated Reality self-test ====='
RESULT="$(curl -fsS --connect-timeout 8 --max-time 15 --socks5-hostname 127.0.0.1:10888 https://api.ipify.org)"
echo "tunnel_http=ok"
echo "egress_ip=$RESULT"
test "$RESULT" = "143.246.197.187"

echo '===== survival check ====='
echo "mobile=$(docker inspect -f '{{.State.Running}}' amnezia-xray-mobile)"
echo "old_xray=$(docker inspect -f '{{.State.Running}}' amnezia-xray)"
echo "awg0=$([ -d /sys/class/net/awg0 ] && echo up || echo missing)"
echo "awg1=$([ -d /sys/class/net/awg1 ] && echo up || echo missing)"
echo MOBILE_REALITY_AUTH_TEST_OK
