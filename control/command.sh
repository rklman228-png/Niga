#!/usr/bin/env bash
set -euo pipefail
umask 077

NAME="amnezia-xray-mobile"
PORT="8443"
SNI="www.microsoft.com"
TARGET="${SNI}:443"
STATE="/root/amnezia-mobile-reality"
BACKUP_ROOT="/root/amnezia-vpn-backups"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP="${BACKUP_ROOT}/${STAMP}"
GEN="$GITHUB_WORKSPACE/control/generated"

mkdir -p "$STATE" "$BACKUP" "$GEN"

echo "===== backup existing VPN state ====="
cp -a /etc/amnezia/amneziawg "$BACKUP/" 2>/dev/null || true
cp -a /etc/wireguard "$BACKUP/" 2>/dev/null || true
docker cp amnezia-xray:/opt/amnezia/xray "$BACKUP/xray-existing" >/dev/null 2>&1 || true
chmod -R go-rwx "$BACKUP" 2>/dev/null || true
echo "backup=$BACKUP"

echo "===== verify prerequisites ====="
command -v openssl >/dev/null
command -v docker >/dev/null
if ss -ltnH | awk '{print $4}' | grep -Eq '(^|:)8443$'; then
  echo "port 8443/tcp is already occupied"
  ss -ltnp | grep ':8443 ' || true
  exit 20
fi
docker image inspect amnezia-xray >/dev/null
docker exec amnezia-xray sh -lc 'command -v xray >/dev/null'

echo "===== generate isolated mobile credentials ====="
UUID="$(docker exec amnezia-xray sh -lc 'xray uuid' | tr -d '\r\n')"
KEYS="$(docker exec amnezia-xray sh -lc 'xray x25519')"
PRIVATE="$(printf '%s\n' "$KEYS" | grep -Ei '^Private' | head -1 | sed -E 's/^[^:]+:[[:space:]]*//')"
PUBLIC="$(printf '%s\n' "$KEYS" | grep -Ei '^(Public|Password)' | head -1 | sed -E 's/^[^:]+:[[:space:]]*//')"
SHORT="$(openssl rand -hex 8)"
test -n "$UUID" && test -n "$PRIVATE" && test -n "$PUBLIC" && test -n "$SHORT"

cat > "$STATE/server.json" <<JSON
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": 8443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "$TARGET",
          "xver": 0,
          "serverNames": ["$SNI"],
          "privateKey": "$PRIVATE",
          "shortIds": ["$SHORT"]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    }
  ]
}
JSON
chmod 600 "$STATE/server.json"

URI="vless://${UUID}@143.246.197.187:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=chrome&pbk=${PUBLIC}&sid=${SHORT}&type=tcp#Mobile-RU-Reality"
printf '%s\n' "$URI" > "$STATE/client.txt"
chmod 600 "$STATE/client.txt"

echo "===== validate config in disposable container ====="
docker run --rm \
  --entrypoint /usr/bin/xray \
  -v "$STATE/server.json:/tmp/server.json:ro" \
  amnezia-xray run -test -config /tmp/server.json

echo "===== launch isolated mobile Reality service ====="
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d \
  --name "$NAME" \
  --restart unless-stopped \
  --cap-drop ALL \
  --security-opt no-new-privileges \
  --tmpfs /tmp:rw,noexec,nosuid,size=16m \
  -p "${PORT}:${PORT}/tcp" \
  -v "$STATE/server.json:/etc/xray-mobile/server.json:ro" \
  --entrypoint /usr/bin/xray \
  amnezia-xray run -config /etc/xray-mobile/server.json >/dev/null

sleep 2
RUNNING="$(docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null || echo false)"
if [ "$RUNNING" != "true" ]; then
  echo "mobile container failed to start"
  docker logs "$NAME" 2>&1 | tail -80 || true
  exit 21
fi

echo "===== local transport test ====="
ss -ltnp | grep ":${PORT} " || true
curl -fsSI --connect-timeout 8 --max-time 12 \
  --resolve "${SNI}:${PORT}:127.0.0.1" \
  "https://${SNI}:${PORT}/" | head -8 || true

echo "===== encrypt client URI for chat handoff ====="
cat > /tmp/chatgpt-vless-pub.pem <<'PUBKEY'
-----BEGIN PUBLIC KEY-----
MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA3j6kbfEGH3Cvm1U+WChH
jZWd4leFXIRePvnTi6opWGqjMvwyX97rOs7NFMEXZ7HqAQspI01PR7ktKwRI48tv
TgE2Q1ro4GkKKUivOIaiBXrAQe8h+Yr2vx8dq2eT49UrJicdatLFpQU3n9GRNRrR
Mrq8pnrLbKcigkp8gj2D5/YVLMDcp0HUasNvTDx573WxsYwZ3P8K4w8MPaTIp6l9
zHS0GnNkxfcb3Gnippc6VrtyFOMeXkzHmYhfEJ5uCtg8PG6GGFQSlp+PZDnIslMU
f6KP7cdAFRv+I22MplJXQrpYORSQnQunco9aTL0tnGCr8ut1FP/IXzj7AGjrGXWv
X1deiMbuWlpbY4ivJEpYduJN9QMSQsdHTxLBI2zbwkLrUBd/zkNabZvTLckHhkz/
JRL/xSaEbSKwxtA4J7qHfgpDhORwbncFbdLE4kWUv2al716x31wRqxXA1h0kz1a1
SFF1sueqKklh2eY2NAFd8X4zuC79bjP5pd43Q869nD4zbidSC4L7RJeHfzb5DR5C
Jvn6tihPfMIYuipiWltett+m9MpijSejg7z0czi2U2/jvowGHaSjA/B+BfGr52mB
tWmEf/yYnhK+1UJLq7+tkqjr9Ny3b4C7Mim+oZhqPYfoL77xz5cP9llC6d57QTbO
OcflXAQuSP8s2PzASvhcTaECAwEAAQ==
-----END PUBLIC KEY-----
PUBKEY
printf '%s' "$URI" | openssl pkeyutl -encrypt -pubin \
  -inkey /tmp/chatgpt-vless-pub.pem \
  -pkeyopt rsa_padding_mode:oaep \
  -pkeyopt rsa_oaep_md:sha256 \
  | base64 -w0 > "$GEN/mobile-vless.enc.b64"
printf '\n' >> "$GEN/mobile-vless.enc.b64"
rm -f /tmp/chatgpt-vless-pub.pem

echo "mobile_protocol=VLESS+REALITY+Vision"
echo "mobile_port=${PORT}/tcp"
echo "mobile_sni=${SNI}"
echo "container_running=$RUNNING"
echo "old_amnezia_xray=$(docker inspect -f '{{.State.Running}}' amnezia-xray 2>/dev/null || echo unknown)"
echo "awg0_present=$([ -d /sys/class/net/awg0 ] && echo yes || echo no)"
echo "awg1_present=$([ -d /sys/class/net/awg1 ] && echo yes || echo no)"
echo "client_uri_encrypted=yes"
echo MOBILE_REALITY_DEPLOY_OK
