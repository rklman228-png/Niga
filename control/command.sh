#!/usr/bin/env bash
set -euo pipefail
umask 077
STATE=/root/amnezia-mobile-reality
GEN="$GITHUB_WORKSPACE/control/generated"
SNI='www.cloudflare.com'
mkdir -p "$GEN"

OLD_URI="$(cat "$STATE/client.txt")"
UUID="$(printf '%s' "$OLD_URI" | sed -E 's#^vless://([^@]+)@.*#\1#')"
PASSWORD="$(printf '%s' "$OLD_URI" | sed -E 's/.*[?&]pbk=([^&]+).*/\1/')"
SHORT="$(printf '%s' "$OLD_URI" | sed -E 's/.*[?&]sid=([^&]+).*/\1/')"
URI="vless://${UUID}@143.246.197.187:8443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=chrome&pbk=${PASSWORD}&sid=${SHORT}&type=tcp#Mobile-RU-Reality"

# Change only the isolated mobile REALITY camouflage target.
python3 - <<'PY'
import json
p='/root/amnezia-mobile-reality/server.json'
d=json.load(open(p))
inb=d['inbounds'][0]
inb['streamSettings']['network']='raw'
r=inb['streamSettings']['realitySettings']
r.pop('dest', None)
r['target']='www.cloudflare.com:443'
r['serverNames']=['www.cloudflare.com']
d['log']['loglevel']='debug'
open(p,'w').write(json.dumps(d, indent=2))
PY
printf '%s\n' "$URI" > "$STATE/client.txt"
chmod 600 "$STATE/client.txt" "$STATE/server.json"

echo '===== target capability ====='
timeout 8 openssl s_client -connect "${SNI}:443" -servername "$SNI" -tls1_3 -alpn h2 </dev/null 2>&1 | grep -E 'Protocol|Cipher|ALPN|Verify return code' | head -20

echo '===== server config validation ====='
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
    {"listen":"127.0.0.1","port":10888,"protocol":"socks","settings":{"udp":false}}
  ],
  "outbounds": [
    {
      "protocol":"vless",
      "settings":{"vnext":[{"address":"127.0.0.1","port":8443,"users":[{"id":"$UUID","flow":"xtls-rprx-vision","encryption":"none"}]}]},
      "streamSettings":{"network":"raw","security":"reality","realitySettings":{"show":false,"fingerprint":"chrome","serverName":"$SNI","password":"$PASSWORD","shortId":"$SHORT","spiderX":""}},
      "tag":"proxy"
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

echo '===== authenticated REALITY test ====='
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

if [ "$STATUS" -ne 0 ]; then
  echo "mobile=$(docker inspect -f '{{.State.Running}}' amnezia-xray-mobile)"
  echo "old_xray=$(docker inspect -f '{{.State.Running}}' amnezia-xray)"
  exit "$STATUS"
fi
test "$RESULT" = '143.246.197.187'

# Restore non-debug logging after a successful proof.
python3 - <<'PY'
import json
p='/root/amnezia-mobile-reality/server.json'
d=json.load(open(p)); d['log']['loglevel']='warning'
open(p,'w').write(json.dumps(d, indent=2))
PY
docker restart amnezia-xray-mobile >/dev/null
sleep 1

# Encrypt the final client URI before returning it through the public repo.
cat > /tmp/chatgpt-vless-pub.pem <<'PUBKEY'
-----BEGIN PUBLIC KEY-----
MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA/WGlVWSgLBuSSm5DjLyE
Rg9q7n2YhYcyvs8kAaAEgwxjX9dHF46KYlz8G7iOW/4dUOCsfZ+rKj9JjFahuxhI
1ROBzXB1nQrZL24wZ2CHQ6Mh0l5Zr9BzH3wEuegHuxk4nM5lQ+xosKPjlzH131Mw
mZStqLds046gN/H/Pz2IJzm1JSQvQcuqpWu3SM+vgjH6JyTchIxUPP2dlI1sN0oa
TLuzmK5rDaUJ/z1mHeTqtLPHHkg67PbwzNMH3dj+LsshmLRUCZmLv2mu68YydOAK
qHvPmIegFc5qB9Eq7f4zu/20sJxEunKTiNh91lvb1WX15/iI94OLAojlWkWvPeG8
ZaY0CI7zs07IAHi9q1n89s5a1GiwdKqjI7UXHT7LlE81UuSzofAjjhPhurJdy4Aa
OSX2LPnjwZA9UQ0QB/fCHkN3WEVlrUOFTR73JYaiZUbG/j9srS/QrC2/MmmAElfe
Qv2OsV1C4UXuNHGRgCbBdw2AUGqw+7DqDjAoJKGi5ZL30oo43tISu/Rn+NrhfVok
MOw3bNGE0BrKC+qAxjigaKJw5RS04tFhTNnpI7jtdWGFaBhmCzjN/+DwquSNC3gp
yswjIeZG3oI+0+dmKxLqwN7n4TSsWzWbb5/Y31FzR2KBPvqZkBdje13mtGqNQMXA
I5dVQMDGMVv2UczZvIovg0kCAwEAAQ==
-----END PUBLIC KEY-----
PUBKEY
printf '%s' "$URI" | openssl pkeyutl -encrypt -pubin -inkey /tmp/chatgpt-vless-pub.pem \
  -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256 | base64 -w0 > "$GEN/mobile-vless.enc.b64"
printf '\n' >> "$GEN/mobile-vless.enc.b64"
rm -f /tmp/chatgpt-vless-pub.pem

echo '===== final survival check ====='
echo "mobile=$(docker inspect -f '{{.State.Running}}' amnezia-xray-mobile)"
echo "old_xray=$(docker inspect -f '{{.State.Running}}' amnezia-xray)"
echo "awg0=$([ -d /sys/class/net/awg0 ] && echo up || echo missing)"
echo "awg1=$([ -d /sys/class/net/awg1 ] && echo up || echo missing)"
echo "mobile_port=$(ss -ltnH | grep -c ':8443 ')"
echo 'final_sni=www.cloudflare.com'
echo 'client_uri_encrypted=yes'
echo MOBILE_REALITY_FINAL_OK
