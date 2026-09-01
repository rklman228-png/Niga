#!/usr/bin/env bash
set -euo pipefail
umask 077
STATE=/root/amnezia-mobile-reality
URI="$(cat "$STATE/client.txt")"
UUID="$(printf '%s' "$URI" | sed -E 's#^vless://([^@]+)@.*#\1#')"
PUBLIC="$(printf '%s' "$URI" | sed -E 's/.*[?&]pbk=([^&]+).*/\1/')"
SHORT="$(printf '%s' "$URI" | sed -E 's/.*[?&]sid=([^&]+).*/\1/')"

SERVER_UUID="$(python3 -c 'import json; d=json.load(open("/root/amnezia-mobile-reality/server.json")); print(d["inbounds"][0]["settings"]["clients"][0]["id"])')"
SERVER_SHORT="$(python3 -c 'import json; d=json.load(open("/root/amnezia-mobile-reality/server.json")); print(d["inbounds"][0]["streamSettings"]["realitySettings"]["shortIds"][0])')"
PRIVATE="$(python3 -c 'import json; d=json.load(open("/root/amnezia-mobile-reality/server.json")); print(d["inbounds"][0]["streamSettings"]["realitySettings"]["privateKey"])')"
DERIVED_RAW="$(docker exec amnezia-xray sh -lc "xray x25519 -i '$PRIVATE'")"
DERIVED_PUBLIC="$(printf '%s\n' "$DERIVED_RAW" | grep -Ei '^(Public|Password)' | head -1 | sed -E 's/^[^:]+:[[:space:]]*//')"

echo '===== credential consistency ====='
[ "$UUID" = "$SERVER_UUID" ] && echo uuid_match=yes || echo uuid_match=no
[ "$SHORT" = "$SERVER_SHORT" ] && echo shortid_match=yes || echo shortid_match=no
[ "$PUBLIC" = "$DERIVED_PUBLIC" ] && echo x25519_match=yes || echo x25519_match=no

echo '===== target TLS ====='
timeout 8 openssl s_client -connect www.microsoft.com:443 -servername www.microsoft.com -tls1_3 -alpn h2 </dev/null 2>&1 | grep -E 'Protocol|Cipher|ALPN|Verify return code' | head -20 || true

# Debug only the isolated mobile service.
python3 - <<'PY'
import json
p='/root/amnezia-mobile-reality/server.json'
d=json.load(open(p))
d['log']['loglevel']='debug'
open(p,'w').write(json.dumps(d, indent=2))
PY
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
        "address": "127.0.0.1",
        "port": 8443,
        "id": "$UUID",
        "flow": "xtls-rprx-vision",
        "encryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "fingerprint": "chrome",
          "serverName": "www.microsoft.com",
          "publicKey": "$PUBLIC",
          "shortId": "$SHORT",
          "spiderX": "/"
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

echo '===== authenticated Reality self-test ====='
if [ "$STATUS" -eq 0 ]; then
  echo tunnel_http=ok
  echo "egress_ip=$RESULT"
else
  echo "tunnel_http=failed status=$STATUS"
  cat /tmp/mobile-curl.err || true
fi
echo '--- client log ---'
docker logs xray-mobile-selftest 2>&1 | tail -120 | sed -E 's/[A-Za-z0-9_-]{35,}/<REDACTED>/g' || true
echo '--- server log ---'
docker logs amnezia-xray-mobile 2>&1 | tail -120 | sed -E 's/[A-Za-z0-9_-]{35,}/<REDACTED>/g' || true

docker rm -f xray-mobile-selftest >/dev/null 2>&1 || true
rm -f "$TEST" /tmp/mobile-curl.err

echo '===== survival ====='
echo "mobile=$(docker inspect -f '{{.State.Running}}' amnezia-xray-mobile)"
echo "old_xray=$(docker inspect -f '{{.State.Running}}' amnezia-xray)"
if [ "$STATUS" -ne 0 ]; then exit "$STATUS"; fi
test "$RESULT" = "143.246.197.187"
echo MOBILE_REALITY_AUTH_TEST_OK
