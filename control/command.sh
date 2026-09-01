#!/usr/bin/env bash
set -euo pipefail
umask 077

IMAGE='amneziavpn/amneziawg-go:latest'
NAME='amnezia-awg31-mobile'
STATE='/root/amnezia-awg31-mobile'
GEN="$GITHUB_WORKSPACE/control/generated"
PORT='585'
SUBNET='10.31.0.0/24'
SERVER_IP='10.31.0.1'
CLIENT_IP='10.31.0.2'
PUBLIC_IP='143.246.197.187'
PASS='DNjex7I3cV39MqPJdlMRq2jVj6qdC1VE'
I1='<r 2><b 0x8580000100010000000004796162730679616e6465780272750000010001c00c000100010000026d000457fa27d1>'

mkdir -p "$STATE" "$GEN"
chmod 700 "$STATE"

echo '===== safety/preflight ====='
if ss -lunH | grep -Eq '(^|:)585[[:space:]]'; then
  echo 'port585=busy'
  ss -lunp | grep ':585 ' || true
  exit 20
fi
echo 'port585=free'
echo "old_awg0=$([ -d /sys/class/net/awg0 ] && echo up || echo missing)"
echo "old_awg1=$([ -d /sys/class/net/awg1 ] && echo up || echo missing)"
echo "legacy_xray=$(docker inspect -f '{{.State.Running}}' amnezia-xray 2>/dev/null || echo missing)"

docker pull "$IMAGE" >/dev/null

echo '===== generate isolated AWG 3.1 credentials ====='
SERVER_PRIV="$(docker run --rm --entrypoint awg "$IMAGE" genkey)"
SERVER_PUB="$(printf '%s\n' "$SERVER_PRIV" | docker run --rm -i --entrypoint awg "$IMAGE" pubkey)"
CLIENT_PRIV="$(docker run --rm --entrypoint awg "$IMAGE" genkey)"
CLIENT_PUB="$(printf '%s\n' "$CLIENT_PRIV" | docker run --rm -i --entrypoint awg "$IMAGE" pubkey)"
PSK="$(docker run --rm --entrypoint awg "$IMAGE" genpsk)"
HPK="$(docker run --rm --entrypoint awg "$IMAGE" genkey)"

# Random non-overlapping header ranges, matching the current Amnezia client approach.
read -r H1 H2 H3 H4 < <(python3 - <<'PY'
import secrets
vals=sorted(secrets.SystemRandom().sample(range(100000, 2_000_000_000), 8))
print(*(f'{vals[i]}-{vals[i+1]}' for i in range(0,8,2)))
PY
)

# S1-S4 are all >=12 because AWG 3 header protection requires that.
S1=83
S2=117
S3=41
S4=17

cat > "$STATE/server.conf" <<EOF
[Interface]
PrivateKey = $SERVER_PRIV
Address = $SERVER_IP/24
ListenPort = $PORT
MTU = 1280
Jc = 6
Jmin = 10
Jmax = 50
S1 = $S1
S2 = $S2
S3 = $S3
S4 = $S4
H1 = $H1
H2 = $H2
H3 = $H3
H4 = $H4
HeaderProtectionKey = $HPK
ContentPaddingAddition = 10-100
RekeyAfterTime = 100-120
RekeyTimeout = 3-7
RejectAfterTime = 150-180
KeepaliveTimeout = 5-15
MaxHandshakeAttempts = 15-20
RandomTrailers = on
DisableCookies = on

[Peer]
PublicKey = $CLIENT_PUB
PresharedKey = $PSK
AllowedIPs = $CLIENT_IP/32
EOF

cat > "$STATE/mobile-awg31.conf" <<EOF
[Interface]
PrivateKey = $CLIENT_PRIV
Address = $CLIENT_IP/32
DNS = 1.1.1.1, 1.0.0.1
MTU = 1280
Jc = 6
Jmin = 10
Jmax = 50
S1 = $S1
S2 = $S2
S3 = $S3
S4 = $S4
H1 = $H1
H2 = $H2
H3 = $H3
H4 = $H4
I1 = $I1
HeaderProtectionKey = $HPK
ContentPaddingAddition = 10-100
RekeyAfterTime = 100-120
RekeyTimeout = 3-7
RejectAfterTime = 150-180
KeepaliveTimeout = 5-15
MaxHandshakeAttempts = 15-20
RandomTrailers = on
DisableCookies = on

[Peer]
PublicKey = $SERVER_PUB
PresharedKey = $PSK
AllowedIPs = 0.0.0.0/0
Endpoint = $PUBLIC_IP:$PORT
PersistentKeepalive = 25-35
EOF

chmod 600 "$STATE/server.conf" "$STATE/mobile-awg31.conf"

cat > "$STATE/start-server.sh" <<'EOF'
#!/bin/sh
set -eu
awg-quick down /config/server.conf >/dev/null 2>&1 || true
awg-quick up /config/server.conf
iptables -C FORWARD -i awg0 -o eth0 -j ACCEPT 2>/dev/null || iptables -A FORWARD -i awg0 -o eth0 -j ACCEPT
iptables -C FORWARD -i eth0 -o awg0 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || iptables -A FORWARD -i eth0 -o awg0 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -t nat -C POSTROUTING -s 10.31.0.0/24 -o eth0 -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -s 10.31.0.0/24 -o eth0 -j MASQUERADE
trap 'awg-quick down /config/server.conf >/dev/null 2>&1 || true; exit 0' TERM INT
while :; do sleep 3600 & wait $!; done
EOF
chmod 700 "$STATE/start-server.sh"

echo '===== validate config parser ====='
docker run --rm --cap-add NET_ADMIN --device /dev/net/tun \
  -v "$STATE:/config:ro" --entrypoint /bin/sh "$IMAGE" -lc \
  'awg-quick strip /config/server.conf >/tmp/stripped && grep -q HeaderProtectionKey /tmp/stripped && echo server_config=ok'

echo '===== launch separate native AmneziaWG 3.1 container ====='
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d \
  --name "$NAME" \
  --restart unless-stopped \
  --cap-add NET_ADMIN \
  --device /dev/net/tun \
  --sysctl net.ipv4.ip_forward=1 \
  -p "$PORT:$PORT/udp" \
  -v "$STATE:/config:ro" \
  --entrypoint /bin/sh \
  "$IMAGE" /config/start-server.sh >/dev/null
sleep 3

RUNNING="$(docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null || echo false)"
if [ "$RUNNING" != true ]; then
  echo 'awg31_container=failed'
  docker logs "$NAME" 2>&1 | tail -100 || true
  exit 21
fi

echo '===== server state ====='
docker exec "$NAME" awg show awg0 | sed -E 's/(private key: ).*/\1(hidden)/'

# Test through the actual Docker-published UDP port without exposing client secrets.
TEST="$STATE/test-client.conf"
sed \
  -e 's#Endpoint = .*#Endpoint = 172.17.0.1:585#' \
  -e 's#AllowedIPs = 0.0.0.0/0#AllowedIPs = 1.1.1.1/32#' \
  -e '/^DNS = /d' \
  "$STATE/mobile-awg31.conf" > "$TEST"
chmod 600 "$TEST"

echo '===== authenticated AWG 3.1 end-to-end test ====='
set +e
TEST_OUT="$(docker run --rm \
  --cap-add NET_ADMIN --device /dev/net/tun \
  -v "$STATE:/config:ro" --entrypoint /bin/sh "$IMAGE" -lc '
    set -e
    awg-quick up /config/test-client.conf >/dev/null
    sleep 2
    echo HANDSHAKE
    awg show awg0 latest-handshakes
    echo TRANSFER
    awg show awg0 transfer
    echo HTTP
    wget -qO- -T 12 http://1.1.1.1/cdn-cgi/trace | grep -E "^(ip|warp)="
    awg-quick down /config/test-client.conf >/dev/null
  ' 2>&1)"
TEST_STATUS=$?
set -e
printf '%s\n' "$TEST_OUT"
rm -f "$TEST"
if [ "$TEST_STATUS" -ne 0 ]; then
  echo "awg31_test=failed status=$TEST_STATUS"
  docker logs "$NAME" 2>&1 | tail -100 || true
  exit "$TEST_STATUS"
fi
printf '%s\n' "$TEST_OUT" | grep -q 'ip=143.246.197.187'
echo 'awg31_tunnel=ok'

echo '===== encrypt Amnezia config for handoff ====='
openssl enc -aes-256-cbc -pbkdf2 -salt \
  -pass pass:"$PASS" \
  -in "$STATE/mobile-awg31.conf" \
  | base64 -w0 > "$GEN/mobile-awg31.conf.enc.b64"
printf '\n' >> "$GEN/mobile-awg31.conf.enc.b64"

# Remove the temporary VLESS service created during the earlier wrong turn; leave the original Amnezia XRay untouched.
docker rm -f amnezia-xray-mobile >/dev/null 2>&1 || true
rm -rf /root/amnezia-mobile-reality >/dev/null 2>&1 || true

echo '===== final survival check ====='
echo "awg31_mobile=$(docker inspect -f '{{.State.Running}}' "$NAME")"
echo "port_585_udp=$(ss -lunH | grep -c ':585 ')"
echo "old_awg0=$([ -d /sys/class/net/awg0 ] && echo up || echo missing)"
echo "old_awg1=$([ -d /sys/class/net/awg1 ] && echo up || echo missing)"
echo "legacy_xray=$(docker inspect -f '{{.State.Running}}' amnezia-xray 2>/dev/null || echo missing)"
echo 'client_format=AmneziaWG-3.1-conf'
echo 'MOBILE_AMNEZIAWG31_OK'
