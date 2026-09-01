#!/usr/bin/env bash
set -euo pipefail

IMAGE='ghcr.io/xtls/xray-core:26.3.27'
STATE='/root/vless-reality-whitelist'
CONTAINER='xray-vless-whitelist'
TEST_CONTAINER='xray-vless-whitelist-test'
SERVER_IP='143.246.197.187'
LOCAL_PORT='47006'
PUBLIC_PORT='443'
SNI='yandex.ru'
HANDOFF='control/generated/wl-vless-creds.enc.b64'
BACKUP="/root/nginx-whitelist-backup-$(date -u +%Y%m%dT%H%M%SZ)"

mkdir -p "$STATE" control/generated
chmod 700 "$STATE"
rm -f "$HANDOFF"

rollback_nginx() {
  if [ -d "$BACKUP" ]; then
    cp -a "$BACKUP/nginx.conf" /etc/nginx/nginx.conf 2>/dev/null || true
    cp -a "$BACKUP/amneziawg-miniapp" /etc/nginx/sites-available/amneziawg-miniapp 2>/dev/null || true
    cp -a "$BACKUP/enihub" /etc/nginx/sites-available/enihub 2>/dev/null || true
    nginx -t >/dev/null 2>&1 && systemctl reload nginx || true
  fi
}

cleanup_test() {
  docker rm -f "$TEST_CONTAINER" >/dev/null 2>&1 || true
}
trap cleanup_test EXIT

echo '===== prepare Xray whitelist profile ====='
docker pull "$IMAGE" >/dev/null

if [ ! -s "$STATE/server.json" ] || [ ! -s "$STATE/client.json" ] || [ ! -s "$STATE/meta.json" ]; then
  UUID="$(cat /proc/sys/kernel/random/uuid)"
  SID="$(openssl rand -hex 8)"
  KEYOUT="$(docker run --rm "$IMAGE" x25519 2>/dev/null)"
  PRIVATE_KEY="$(printf '%s\n' "$KEYOUT" | sed -nE 's/^(Private key|PrivateKey):[[:space:]]*//p' | head -n1)"
  PUBLIC_KEY="$(printf '%s\n' "$KEYOUT" | sed -nE 's/^(Password \(PublicKey\)|Public key|PublicKey|Password):[[:space:]]*//p' | head -n1)"
  if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
    echo 'x25519_parse=failed'
    exit 50
  fi

  cat > "$STATE/server.json" <<EOF
{
  "log":{"loglevel":"warning"},
  "inbounds":[{
    "listen":"0.0.0.0",
    "port":$LOCAL_PORT,
    "protocol":"vless",
    "settings":{"clients":[{"id":"$UUID","flow":"xtls-rprx-vision"}],"decryption":"none"},
    "streamSettings":{"network":"tcp","security":"reality","realitySettings":{"target":"$SNI:443","serverNames":["$SNI"],"privateKey":"$PRIVATE_KEY","shortIds":["$SID"],"minClientVer":"24.1.1"}}
  }],
  "outbounds":[{"protocol":"freedom","tag":"direct"},{"protocol":"blackhole","tag":"block"}]
}
EOF

  cat > "$STATE/client.json" <<EOF
{
  "log":{"loglevel":"warning"},
  "inbounds":[{"listen":"127.0.0.1","port":10918,"protocol":"socks","settings":{"auth":"noauth","udp":true},"tag":"socks"}],
  "outbounds":[{
    "protocol":"vless",
    "settings":{"vnext":[{"address":"$SERVER_IP","port":$PUBLIC_PORT,"users":[{"id":"$UUID","encryption":"none","flow":"xtls-rprx-vision"}]}]},
    "streamSettings":{"network":"tcp","security":"reality","realitySettings":{"serverName":"$SNI","fingerprint":"ios","publicKey":"$PUBLIC_KEY","shortId":"$SID"}},
    "tag":"proxy"
  }]
}
EOF

  cat > "$STATE/meta.json" <<EOF
{"uuid":"$UUID","publicKey":"$PUBLIC_KEY","shortId":"$SID","sni":"$SNI"}
EOF
  chmod 600 "$STATE/server.json" "$STATE/client.json" "$STATE/meta.json"
  unset UUID SID PRIVATE_KEY PUBLIC_KEY KEYOUT
  echo 'credentials=generated'
else
  echo 'credentials=reused'
fi

echo '===== validate Xray configs ====='
docker run --rm --user 0:0 -v "$STATE/server.json:/etc/xray/config.json:ro" "$IMAGE" run -test -config=/etc/xray/config.json >/dev/null
docker run --rm --user 0:0 -v "$STATE/client.json:/etc/xray/config.json:ro" "$IMAGE" run -test -config=/etc/xray/config.json >/dev/null
echo 'xray_configs=valid'

echo '===== ensure nginx stream module ====='
if ! nginx -T 2>&1 | grep -q '^stream {'; then
  if [ ! -e /usr/lib/nginx/modules/ngx_stream_module.so ]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq libnginx-mod-stream >/dev/null
  fi
  if ! grep -Rqs 'ngx_stream_module.so' /etc/nginx/modules-enabled 2>/dev/null; then
    printf 'load_module modules/ngx_stream_module.so;\n' > /etc/nginx/modules-enabled/50-mod-stream.conf
  fi
fi
nginx -t >/dev/null
echo 'nginx_stream=ready'

echo '===== start isolated whitelist Xray ====='
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
docker run -d \
  --name "$CONTAINER" \
  --restart unless-stopped \
  --user 0:0 \
  -p "127.0.0.1:$LOCAL_PORT:$LOCAL_PORT/tcp" \
  -v "$STATE/server.json:/etc/xray/config.json:ro" \
  "$IMAGE" run -config=/etc/xray/config.json >/dev/null
sleep 2
if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || echo false)" != true ]; then
  echo 'wl_xray=failed'
  exit 51
fi
echo 'wl_xray=running'

echo '===== install nginx SNI mux on 443 ====='
if ! grep -q '# WL_STREAM_BEGIN' /etc/nginx/nginx.conf; then
  mkdir -p "$BACKUP"
  cp -a /etc/nginx/nginx.conf "$BACKUP/nginx.conf"
  cp -a /etc/nginx/sites-available/amneziawg-miniapp "$BACKUP/amneziawg-miniapp"
  cp -a /etc/nginx/sites-available/enihub "$BACKUP/enihub"

  python3 - <<'PY'
from pathlib import Path
for p in [Path('/etc/nginx/sites-available/amneziawg-miniapp'), Path('/etc/nginx/sites-available/enihub')]:
    s=p.read_text()
    s=s.replace('listen [::]:443 ssl ipv6only=on;', 'listen [::1]:4443 ssl ipv6only=on;')
    s=s.replace('listen 443 ssl;', 'listen 127.0.0.1:4443 ssl;')
    p.write_text(s)
PY

  cat >> /etc/nginx/nginx.conf <<'EOF'

# WL_STREAM_BEGIN
stream {
    map $ssl_preread_server_name $wl_backend {
        yandex.ru 127.0.0.1:47006;
        default   127.0.0.1:4443;
    }

    server {
        listen 0.0.0.0:443;
        listen [::]:443;
        ssl_preread on;
        proxy_connect_timeout 5s;
        proxy_timeout 3600s;
        proxy_pass $wl_backend;
    }
}
# WL_STREAM_END
EOF

  if ! nginx -t; then
    echo 'nginx_mux_config=invalid'
    rollback_nginx
    exit 52
  fi
  systemctl reload nginx
  sleep 1
  echo "nginx_backup=$BACKUP"
else
  echo 'nginx_mux=already_installed'
fi

echo '===== verify existing HTTPS survived ====='
for domain in bot.pronexsbp.ru enihub.ru; do
  CODE="$(curl -sS -o /dev/null --max-time 12 --resolve "$domain:443:127.0.0.1" -w '%{http_code}' "https://$domain/" || true)"
  echo "$domain=http_$CODE"
  if [ "$CODE" = 000 ] || [ -z "$CODE" ]; then
    echo 'existing_https=failed'
    rollback_nginx
    exit 53
  fi
done
echo 'existing_https=ok'

echo '===== end-to-end whitelist profile test through public 443 ====='
cleanup_test
docker run -d --name "$TEST_CONTAINER" --network host --user 0:0 \
  -v "$STATE/client.json:/etc/xray/config.json:ro" \
  "$IMAGE" run -config=/etc/xray/config.json >/dev/null
sleep 3
TEST_IP="$(curl -fsS --max-time 20 --socks5-hostname 127.0.0.1:10918 https://api.ipify.org || true)"
if [ "$TEST_IP" != "$SERVER_IP" ]; then
  echo "wl_tunnel_test=failed result=${TEST_IP:-none}"
  docker logs --tail 30 "$TEST_CONTAINER" 2>&1 | sed -E 's/[A-Za-z0-9_+\/-]{28,}={0,2}/[redacted]/g' || true
  rollback_nginx
  exit 54
fi
echo 'wl_tunnel_test=ok'
echo "exit_ip=$TEST_IP"
cleanup_test

echo '===== encrypted client credential handoff ====='
cat > "$STATE/handoff.pub.pem" <<'PUBEOF'
-----BEGIN PUBLIC KEY-----
MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAwMufdcQmCiceHYTHJvGv
XtE4/c+iDYglIyI4Un+RDkbLB9HpazFUyTRAk2rvuR+F5HKADB47msWmLkFgX88m
4Ich9iYpKdGzxBeVlUmV9UerV/16yCo37jZ/pYv4Pt6GKP+UkRAUzbh6o9u4MPF2
7HJpURzSQHTR94Y+rI/Q+7LQNSwLmusFSgFs7JQBpEtZs7EzF5wBMnJ/5EJxHM5e
cuRFi7vayIx7NqCLF9oqhSacT1EY+jBRBHyy2RVwW+S2clExYdp9uGFGh2vYFWkE
HrJ6JlpUCmR/jqSXxb3hTskFNfRfIBgHA7/5Ix7erEYhEFiDgGSAu5OZlahQVUZa
Vyfz07dZX/YNed3Pdycz+3xo2Tc3R430Q+qPl5tKzTXD5m55AmlpfkceIuK5mxZx
ud8q6trhxHBTXaCK/WljfKoVdoQtGoNHhTzizVhv4OWH5u5NaV3HZskVVg6sAhUC
y9k18YS2wDOCDOHGfLeh4E4pf6hKdj9rJ7sC2RQx1Zhb3hmJ8tnlzu3icKOX9QLz
6lLVUeLBrLHMaFGKOhiQHXyCX8bsjF6OPHRbpD8zUAmFNqQr17vH/jOf2qqHu+nV
7CoziD3kRu5O4vC5s9blLD+1DXH0ikbX7eH8XUJWgXZW7/nuAzgRnjNBSb6wG/MV
J5qpSk/JOS/wWzX0PctZvQMCAwEAAQ==
-----END PUBLIC KEY-----
PUBEOF
openssl pkeyutl -encrypt -pubin -inkey "$STATE/handoff.pub.pem" \
  -pkeyopt rsa_padding_mode:oaep \
  -pkeyopt rsa_oaep_md:sha256 \
  -pkeyopt rsa_mgf1_md:sha256 \
  -in "$STATE/meta.json" 2>/dev/null | base64 -w0 > "$HANDOFF"
rm -f "$STATE/handoff.pub.pem"
echo 'secure_handoff=ready'

echo '===== preservation checks ====='
echo "wl_vless=$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || echo missing)"
echo "public_tcp443=$(ss -ltnH | grep -c ':443 ' || true)"
echo "inner_tcp4443=$(ss -ltnH | grep -c ':4443 ' || true)"
echo "main_vless=$(docker inspect -f '{{.State.Running}}' xray-vless-47005 2>/dev/null || echo missing)"
echo "awg31=$(docker inspect -f '{{.State.Running}}' amnezia-awg31-mobile 2>/dev/null || echo missing)"
echo "legacy_xray=$(docker inspect -f '{{.State.Running}}' amnezia-xray 2>/dev/null || echo missing)"
echo WL_VLESS_DEPLOY_OK
