#!/usr/bin/env bash
set -euo pipefail

IMAGE='ghcr.io/xtls/xray-core:26.7.28'
STATE='/root/vless-reality-whitelist-xhttp'
CONTAINER='xray-vless-whitelist-xhttp'
TEST='xray-vless-whitelist-xhttp-test'
SERVER_IP='143.246.197.187'
LOCAL_PORT='47007'
PUBLIC_PORT='443'
SNI='www.yandex.ru'
PATH_X='/api/v1/ping/'
HANDOFF='control/generated/wl-xhttp-creds.enc.b64'
BACKUP="/root/nginx-xhttp-backup-$(date -u +%Y%m%dT%H%M%SZ)"

mkdir -p "$STATE" control/generated
chmod 700 "$STATE"
rm -f "$HANDOFF"

echo '===== prepare separate XHTTP+REALITY whitelist profile ====='
docker pull "$IMAGE" >/dev/null

if [ ! -s "$STATE/server.json" ] || [ ! -s "$STATE/client.json" ] || [ ! -s "$STATE/meta.json" ]; then
  UUID="$(cat /proc/sys/kernel/random/uuid)"
  SID="$(openssl rand -hex 8)"
  KEYOUT="$(docker run --rm "$IMAGE" x25519 2>/dev/null)"
  PRIVATE_KEY="$(printf '%s\n' "$KEYOUT" | sed -nE 's/^(Private key|PrivateKey):[[:space:]]*//p' | head -n1)"
  PUBLIC_KEY="$(printf '%s\n' "$KEYOUT" | sed -nE 's/^(Password \(PublicKey\)|Public key|PublicKey|Password):[[:space:]]*//p' | head -n1)"
  test -n "$PRIVATE_KEY" && test -n "$PUBLIC_KEY"

  cat > "$STATE/server.json" <<EOF
{
  "log":{"loglevel":"info"},
  "dns":{"queryStrategy":"UseIPv4","servers":["1.1.1.1","1.0.0.1"]},
  "inbounds":[{
    "listen":"0.0.0.0",
    "port":$LOCAL_PORT,
    "protocol":"vless",
    "settings":{"clients":[{"id":"$UUID"}],"decryption":"none"},
    "streamSettings":{
      "network":"xhttp",
      "security":"reality",
      "xhttpSettings":{"path":"$PATH_X","mode":"auto"},
      "realitySettings":{"target":"$SNI:443","serverNames":["$SNI"],"privateKey":"$PRIVATE_KEY","shortIds":["$SID"]}
    }
  }],
  "outbounds":[{"protocol":"freedom","settings":{"domainStrategy":"UseIPv4"},"tag":"direct"},{"protocol":"blackhole","tag":"block"}]
}
EOF

  cat > "$STATE/client.json" <<EOF
{
  "log":{"loglevel":"warning"},
  "dns":{"queryStrategy":"UseIPv4","servers":["1.1.1.1","1.0.0.1"]},
  "inbounds":[
    {"listen":"127.0.0.1","port":10928,"protocol":"socks","settings":{"auth":"noauth","udp":true},"sniffing":{"enabled":true,"destOverride":["http","tls","quic"]},"tag":"socks"}
  ],
  "outbounds":[{
    "protocol":"vless",
    "settings":{"vnext":[{"address":"$SERVER_IP","port":$PUBLIC_PORT,"users":[{"id":"$UUID","encryption":"none","packetEncoding":"xudp"}]}]},
    "streamSettings":{
      "network":"xhttp",
      "security":"reality",
      "xhttpSettings":{"path":"$PATH_X","mode":"auto"},
      "realitySettings":{"serverName":"$SNI","fingerprint":"firefox","publicKey":"$PUBLIC_KEY","shortId":"$SID"}
    },
    "tag":"proxy"
  }],
  "routing":{"domainStrategy":"IPIfNonMatch","rules":[{"type":"field","network":"tcp,udp","outboundTag":"proxy"}]}
}
EOF

  cat > "$STATE/meta.json" <<EOF
{"uuid":"$UUID","publicKey":"$PUBLIC_KEY","shortId":"$SID","sni":"$SNI","path":"$PATH_X"}
EOF
  chmod 600 "$STATE/server.json" "$STATE/client.json" "$STATE/meta.json"
  unset UUID SID PRIVATE_KEY PUBLIC_KEY KEYOUT
  echo 'credentials=generated'
else
  echo 'credentials=reused'
fi

echo '===== validate XHTTP configs ====='
docker run --rm --user 0:0 -v "$STATE/server.json:/etc/xray/config.json:ro" "$IMAGE" run -test -config=/etc/xray/config.json >/dev/null
docker run --rm --user 0:0 -v "$STATE/client.json:/etc/xray/config.json:ro" "$IMAGE" run -test -config=/etc/xray/config.json >/dev/null
echo 'xhttp_configs=valid'

echo '===== start isolated XHTTP backend ====='
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
docker run -d --name "$CONTAINER" --restart unless-stopped --user 0:0 \
  -p "127.0.0.1:$LOCAL_PORT:$LOCAL_PORT/tcp" \
  -v "$STATE/server.json:/etc/xray/config.json:ro" \
  "$IMAGE" run -config=/etc/xray/config.json >/dev/null
sleep 2
test "$(docker inspect -f '{{.State.Running}}' "$CONTAINER")" = true
echo 'xhttp_backend=running'

echo '===== add dedicated SNI route without touching old whitelist ====='
if ! grep -q "^[[:space:]]*$SNI[[:space:]]\+127\.0\.0\.1:$LOCAL_PORT;" /etc/nginx/nginx.conf; then
  mkdir -p "$BACKUP"
  cp -a /etc/nginx/nginx.conf "$BACKUP/nginx.conf"
  python3 - <<'PY'
from pathlib import Path
p=Path('/etc/nginx/nginx.conf')
s=p.read_text()
needle='        default   127.0.0.1:4443;'
line='        www.yandex.ru 127.0.0.1:47007;\n'
if line.strip() not in s:
    if needle not in s:
        raise SystemExit('stream map default not found')
    s=s.replace(needle, line+needle, 1)
p.write_text(s)
PY
  if ! nginx -t; then
    cp -a "$BACKUP/nginx.conf" /etc/nginx/nginx.conf
    nginx -t >/dev/null && systemctl reload nginx || true
    echo 'nginx_route=rollback'
    exit 61
  fi
  systemctl reload nginx
  echo "nginx_backup=$BACKUP"
else
  echo 'nginx_route=already_present'
fi

echo '===== verify existing services ====='
for domain in bot.pronexsbp.ru enihub.ru; do
  code="$(curl -sS -o /dev/null --max-time 10 --resolve "$domain:443:127.0.0.1" -w '%{http_code}' "https://$domain/" || true)"
  echo "$domain=http_$code"
  test "$code" != 000
  test -n "$code"
done

echo '===== end-to-end XHTTP through public 443 ====='
docker rm -f "$TEST" >/dev/null 2>&1 || true
docker run -d --name "$TEST" --network host --user 0:0 \
  -v "$STATE/client.json:/etc/xray/config.json:ro" \
  "$IMAGE" run -config=/etc/xray/config.json >/dev/null
cleanup(){ docker rm -f "$TEST" >/dev/null 2>&1 || true; }
trap cleanup EXIT
sleep 3
for url in https://api.ipify.org https://telegram.org/ https://github.com/ https://www.gstatic.com/generate_204; do
  printf '%s ' "$url"
  curl -sS -o /dev/null --max-time 20 --socks5-hostname 127.0.0.1:10928 \
    -w 'code=%{http_code} total=%{time_total}\n' "$url"
done
OUT_IP="$(curl -fsS --max-time 20 --socks5-hostname 127.0.0.1:10928 https://api.ipify.org)"
test "$OUT_IP" = "$SERVER_IP"
echo 'xhttp_tunnel=ok'
echo "exit_ip=$OUT_IP"
cleanup

echo '===== secure client handoff ====='
cat > "$STATE/handoff.pub.pem" <<'PUBEOF'
-----BEGIN PUBLIC KEY-----
MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAuDBfgwxuEeNyna2KPWGY
hYA+aR7pjLgpMVoMC68v9LRIOBmUA64jKWPkKl21WKclhqBIbNYTBc9Q0oY6gzC7
RvzpW/R7+YdRAalovj11neOrD0UczeCg+s5YpR4yskyB2vTOX0vI/nnGaAlJ/KRb
h1gBMgMtKNbmHfPOgASacFMgdQHnm+w9R+W1xIjU55P+F1mZuGh4CPPpMPN3f/Xi
IgHIxPR/z7+GPGgpJveL8DcrxkYlNG4epu7VXvmVJeyViauTiG9Qm7tJo2Fy8twb
9+qdei9us6IAyPGop2Zw0rxGPpbi0iqjjuV8JW5tCrVmPGmwpaD1/5IOEh/USx5Y
bgVXTyeGO0iSFlzTIZG47cR8R5pXDepoOq0Q9MZTYSfP6jOe2Thv8dUXTdXNgDm9
SUOqGPFGu9VNGVpHy1RBLsSGNrsOyJL4O2g6e1D+TJnpTkQEFG46RmUoh5/3O+a2
J7DWvbum0qGQiuvxjgO5gLhzwJ+/zKvnB3lL4EuNb3sNvtgAk+8/JFe5VBBt9eIk
R1KsMBf+AsfD3l0X6SVN/G1g4hIQR8fSOmPJKTZ0GJr0L3BbWtp9uS5L49GEfpLu
d3LmqKVIbaoyRUkpHhVqq1ccIsw8YhPgmGo+LNIqwIGfHY1WEEsYngUtIVVAWUB5
Of5oeGfc0zo4dNpcv0+ot+cCAwEAAQ==
-----END PUBLIC KEY-----
PUBEOF
openssl pkeyutl -encrypt -pubin -inkey "$STATE/handoff.pub.pem" \
  -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256 -pkeyopt rsa_mgf1_md:sha256 \
  -in "$STATE/meta.json" 2>/dev/null | base64 -w0 > "$HANDOFF"
rm -f "$STATE/handoff.pub.pem"
echo 'secure_handoff=ready'

echo '===== preservation ====='
echo "xhttp_vless=$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || echo missing)"
echo "old_wl_vless=$(docker inspect -f '{{.State.Running}}' xray-vless-whitelist 2>/dev/null || echo missing)"
echo "main_vless=$(docker inspect -f '{{.State.Running}}' xray-vless-47005 2>/dev/null || echo missing)"
echo "awg31=$(docker inspect -f '{{.State.Running}}' amnezia-awg31-mobile 2>/dev/null || echo missing)"
echo XHTTP_WL_READY
