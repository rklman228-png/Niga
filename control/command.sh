#!/usr/bin/env bash
set -euo pipefail
umask 077
STATE=/root/amnezia-mobile-reality
URI="$(cat "$STATE/client.txt")"
UUID="$(printf '%s' "$URI" | sed -E 's#^vless://([^@]+)@.*#\1#')"
PASSWORD="$(printf '%s' "$URI" | sed -E 's/.*[?&]pbk=([^&]+).*/\1/')"
SHORT="$(printf '%s' "$URI" | sed -E 's/.*[?&]sid=([^&]+).*/\1/')"

# Migrate only the isolated mobile service to current REALITY field names.
python3 - <<'PY'
import json
p='/root/amnezia-mobile-reality/server.json'
d=json.load(open(p))
inb=d['inbounds'][0]
inb['streamSettings']['network']='raw'
r=inb['streamSettings']['realitySettings']
if 'dest' in r:
    r['target']=r.pop('dest')
d['log']['loglevel']='debug'
open(p,'w').write(json.dumps(d, indent=2))
PY

# Validate before touching the running mobile container.
docker run --rm --entrypoint /usr/bin/xray \
  -v "$STATE/server.json:/tmp/server.json:ro" \
  amnezia-xray run -test -config /tmp/server.json

docker restart amnezia-xray-mobile >/dev/null
sleep 2

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
                "flow": "xtls-rprx-vision",
                "encryption": "none"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "raw",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "fingerprint": "chrome",
          "serverName": "www.microsoft.com",
          "password": "$PASSWORD",
          "shortId": "$SHORT",
          "spiderX": ""
        }
      },
      "tag": "proxy"
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
STATUS=$?
set -e

echo '===== current REALITY end-to-end test ====='
if [ "$STATUS" -eq 0 ]; then
  echo tunnel_http=ok
  echo "egress_ip=$RESULT"
else
  echo "tunnel_http=failed status=$STATUS"
  cat /tmp/mobile-curl.err || true
  echo '--- client log ---'
  docker logs xray-mobile-selftest 2>&1 | tail -120 | sed -E 's/[A-Za-z0-9_-]{35,}/<REDACTED>/g' || true
  echo '--- server log ---'
  docker logs amnezia-xray-mobile 2>&1 | tail -120 | sed -E 's/[A-Za-z0-9_-]{35,}/<REDACTED>/g' || true
fi

docker rm -f xray-mobile-selftest >/dev/null 2>&1 || true
rm -f "$TEST" /tmp/mobile-curl.err

echo '===== survival ====='
echo "mobile=$(docker inspect -f '{{.State.Running}}' amnezia-xray-mobile)"
echo "old_xray=$(docker inspect -f '{{.State.Running}}' amnezia-xray)"
echo "awg0=$([ -d /sys/class/net/awg0 ] && echo up || echo missing)"
echo "awg1=$([ -d /sys/class/net/awg1 ] && echo up || echo missing)"

if [ "$STATUS" -ne 0 ]; then exit "$STATUS"; fi
test "$RESULT" = "143.246.197.187"
echo MOBILE_REALITY_AUTH_TEST_OK
