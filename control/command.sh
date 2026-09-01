#!/usr/bin/env bash
set -euo pipefail
umask 077

STATE=/root/amnezia-mobile-reality
URI="$(cat "$STATE/client.txt")"
UUID="$(printf '%s' "$URI" | sed -E 's#^vless://([^@]+)@.*#\1#')"
PUBLIC="$(printf '%s' "$URI" | sed -E 's/.*[?&]pbk=([^&]+).*/\1/')"
SHORT="$(printf '%s' "$URI" | sed -E 's/.*[?&]sid=([^&]+).*/\1/')"
TEST="$STATE/selftest-client.json"

cat > "$TEST" <<JSON
{
  "log": {"loglevel": "debug"},
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
            "address": "127.0.0.1",
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
          "serverName": "www.microsoft.com",
          "fingerprint": "chrome",
          "password": "$PUBLIC",
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
sleep 2

set +e
RESULT="$(curl -fsS --connect-timeout 8 --max-time 15 --socks5-hostname 127.0.0.1:10888 https://api.ipify.org 2>/tmp/mobile-curl.err)"
CURL_STATUS=$?
set -e

echo '===== authenticated Reality self-test ====='
if [ "$CURL_STATUS" -eq 0 ]; then
  echo 'tunnel_http=ok'
  echo "egress_ip=$RESULT"
else
  echo "tunnel_http=failed status=$CURL_STATUS"
  cat /tmp/mobile-curl.err || true
  echo '--- client log (secrets filtered) ---'
  docker logs xray-mobile-selftest 2>&1 | tail -100 | sed -E 's/[A-Za-z0-9_-]{35,}/<REDACTED>/g'
  echo '--- server log (secrets filtered) ---'
  docker logs amnezia-xray-mobile 2>&1 | tail -100 | sed -E 's/[A-Za-z0-9_-]{35,}/<REDACTED>/g'
fi

docker rm -f xray-mobile-selftest >/dev/null 2>&1 || true
rm -f "$TEST" /tmp/mobile-curl.err

echo '===== survival check ====='
echo "mobile=$(docker inspect -f '{{.State.Running}}' amnezia-xray-mobile)"
echo "old_xray=$(docker inspect -f '{{.State.Running}}' amnezia-xray)"
echo "awg0=$([ -d /sys/class/net/awg0 ] && echo up || echo missing)"
echo "awg1=$([ -d /sys/class/net/awg1 ] && echo up || echo missing)"

if [ "$CURL_STATUS" -ne 0 ]; then exit "$CURL_STATUS"; fi
test "$RESULT" = "143.246.197.187"
echo MOBILE_REALITY_AUTH_TEST_OK
