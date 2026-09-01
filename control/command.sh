#!/usr/bin/env bash
set -euo pipefail

IMAGE='ghcr.io/xtls/xray-core:26.3.27'
STATE='/root/vless-reality-whitelist'
CONTAINER='xray-vless-whitelist'
TEST_CONTAINER='xray-vless-whitelist-test'
SERVER_IP='143.246.197.187'
HANDOFF='control/generated/wl-vless-creds.enc.b64'
BACKUP="/root/nginx-whitelist-backup-$(date -u +%Y%m%dT%H%M%SZ)"

mkdir -p control/generated
rm -f "$HANDOFF"

if [ ! -s "$STATE/server.json" ] || [ ! -s "$STATE/client.json" ] || [ ! -s "$STATE/meta.json" ]; then
  echo 'wl_state=missing'
  exit 60
fi

rollback() {
  if [ -d "$BACKUP" ]; then
    cp -a "$BACKUP/nginx.conf" /etc/nginx/nginx.conf 2>/dev/null || true
    cp -a "$BACKUP/amneziawg-miniapp" /etc/nginx/sites-available/amneziawg-miniapp 2>/dev/null || true
    cp -a "$BACKUP/enihub" /etc/nginx/sites-available/enihub 2>/dev/null || true
    nginx -t >/dev/null 2>&1 && systemctl reload nginx || true
  fi
}
cleanup_test() { docker rm -f "$TEST_CONTAINER" >/dev/null 2>&1 || true; }
trap cleanup_test EXIT

echo '===== verify existing services before retry ====='
echo "main_vless=$(docker inspect -f '{{.State.Running}}' xray-vless-47005 2>/dev/null || echo missing)"
echo "awg31=$(docker inspect -f '{{.State.Running}}' amnezia-awg31-mobile 2>/dev/null || echo missing)"
echo "legacy_xray=$(docker inspect -f '{{.State.Running}}' amnezia-xray 2>/dev/null || echo missing)"
nginx -t >/dev/null

echo '===== ensure whitelist Xray local backend ====='
if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || echo false)" != true ]; then
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  docker run -d --name "$CONTAINER" --restart unless-stopped --user 0:0 \
    -p 127.0.0.1:47006:47006/tcp \
    -v "$STATE/server.json:/etc/xray/config.json:ro" \
    "$IMAGE" run -config=/etc/xray/config.json >/dev/null
  sleep 2
fi
[ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || echo false)" = true ]
echo 'wl_xray=running'

echo '===== install 443 SNI mux with IPv4 inner HTTPS ====='
if ! grep -q '# WL_STREAM_BEGIN' /etc/nginx/nginx.conf; then
  mkdir -p "$BACKUP"
  cp -a /etc/nginx/nginx.conf "$BACKUP/nginx.conf"
  cp -a /etc/nginx/sites-available/amneziawg-miniapp "$BACKUP/amneziawg-miniapp"
  cp -a /etc/nginx/sites-available/enihub "$BACKUP/enihub"

  python3 - <<'PY'
from pathlib import Path
for p in [Path('/etc/nginx/sites-available/amneziawg-miniapp'), Path('/etc/nginx/sites-available/enihub')]:
    s=p.read_text()
    s=s.replace('listen [::]:443 ssl ipv6only=on;', '# IPv6 public 443 handled by stream mux')
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
    echo 'nginx_mux=invalid'
    rollback
    exit 61
  fi
  systemctl reload nginx
  sleep 1
  echo "nginx_backup=$BACKUP"
else
  echo 'nginx_mux=already_present'
fi

echo '===== verify ordinary HTTPS ====='
for domain in bot.pronexsbp.ru enihub.ru; do
  CODE="$(curl -sS -o /dev/null --max-time 12 --resolve "$domain:443:127.0.0.1" -w '%{http_code}' "https://$domain/" || true)"
  echo "$domain=http_$CODE"
  if [ -z "$CODE" ] || [ "$CODE" = 000 ]; then
    rollback
    echo 'ordinary_https=failed'
    exit 62
  fi
done
echo 'ordinary_https=ok'

echo '===== test whitelist VLESS through public TCP 443 ====='
cleanup_test
docker run -d --name "$TEST_CONTAINER" --network host --user 0:0 \
  -v "$STATE/client.json:/etc/xray/config.json:ro" \
  "$IMAGE" run -config=/etc/xray/config.json >/dev/null
sleep 3
TEST_IP="$(curl -fsS --max-time 20 --socks5-hostname 127.0.0.1:10918 https://api.ipify.org || true)"
if [ "$TEST_IP" != "$SERVER_IP" ]; then
  echo "wl_tunnel=failed result=${TEST_IP:-none}"
  docker logs --tail 30 "$TEST_CONTAINER" 2>&1 | sed -E 's/[A-Za-z0-9_+\/-]{28,}={0,2}/[redacted]/g' || true
  rollback
  exit 63
fi
echo 'wl_tunnel=ok'
echo "exit_ip=$TEST_IP"
cleanup_test

echo '===== encrypted client handoff ====='
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
  -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256 -pkeyopt rsa_mgf1_md:sha256 \
  -in "$STATE/meta.json" 2>/dev/null | base64 -w0 > "$HANDOFF"
rm -f "$STATE/handoff.pub.pem"
echo 'secure_handoff=ready'

echo '===== final status ====='
echo "wl_vless=$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || echo missing)"
echo "tcp443=$(ss -ltnH | grep -c ':443 ' || true)"
echo "tcp4443=$(ss -ltnH | grep -c ':4443 ' || true)"
echo "main_vless=$(docker inspect -f '{{.State.Running}}' xray-vless-47005 2>/dev/null || echo missing)"
echo "awg31=$(docker inspect -f '{{.State.Running}}' amnezia-awg31-mobile 2>/dev/null || echo missing)"
echo "legacy_xray=$(docker inspect -f '{{.State.Running}}' amnezia-xray 2>/dev/null || echo missing)"
echo WL_VLESS_READY
