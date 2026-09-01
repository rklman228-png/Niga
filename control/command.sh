#!/usr/bin/env bash
set -euo pipefail
umask 077

IMAGE='amneziavpn/amneziawg-go:latest'
NAME='amnezia-awg31-mobile'
STATE='/root/amnezia-awg31-mobile'
GEN="$GITHUB_WORKSPACE/control/generated"
PASS='DNjex7I3cV39MqPJdlMRq2jVj6qdC1VE'

[ -s "$STATE/awg0.conf" ] && [ -s "$STATE/mobile-awg31.conf" ]
mkdir -p "$GEN"
docker rm -f "$NAME" >/dev/null 2>&1 || true

echo '===== userspace AWG3 capability test ====='
docker run --rm --cap-add NET_ADMIN --device /dev/net/tun \
  -v "$STATE:/config:ro" --entrypoint /bin/sh "$IMAGE" -lc '
    set -e
    amneziawg-go -f awgtest >/tmp/awg-go.log 2>&1 &
    pid=$!
    sleep 1
    awg-quick strip /config/awg0.conf >/tmp/stripped
    awg setconf awgtest /tmp/stripped
    ip addr add 10.31.0.1/24 dev awgtest
    ip link set mtu 1280 up dev awgtest
    awg show awgtest | sed -E "s/(private key: ).*/\\1(hidden)/"
    kill "$pid" >/dev/null 2>&1 || true
  '

echo 'userspace_awg3=ok'

cat > "$STATE/start-userspace.sh" <<'EOF'
#!/bin/sh
set -eu
rm -f /var/run/amneziawg/awg0.sock 2>/dev/null || true
amneziawg-go -f awg0 >/tmp/amneziawg-go.log 2>&1 &
DAEMON=$!
cleanup() {
  kill "$DAEMON" >/dev/null 2>&1 || true
  wait "$DAEMON" 2>/dev/null || true
}
trap cleanup TERM INT EXIT
sleep 1
awg-quick strip /config/awg0.conf >/tmp/awg0.stripped
awg setconf awg0 /tmp/awg0.stripped
ip addr add 10.31.0.1/24 dev awg0
ip link set mtu 1280 up dev awg0
iptables -C FORWARD -i awg0 -o eth0 -j ACCEPT 2>/dev/null || iptables -A FORWARD -i awg0 -o eth0 -j ACCEPT
iptables -C FORWARD -i eth0 -o awg0 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || iptables -A FORWARD -i eth0 -o awg0 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -t nat -C POSTROUTING -s 10.31.0.0/24 -o eth0 -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -s 10.31.0.0/24 -o eth0 -j MASQUERADE
wait "$DAEMON"
EOF
chmod 700 "$STATE/start-userspace.sh"

echo '===== launch native AmneziaWG 3.1 userspace container ====='
docker run -d \
  --name "$NAME" --restart unless-stopped \
  --cap-add NET_ADMIN --device /dev/net/tun \
  --sysctl net.ipv4.ip_forward=1 \
  -p 585:585/udp \
  -v "$STATE:/config:ro" \
  --entrypoint /bin/sh "$IMAGE" /config/start-userspace.sh >/dev/null
sleep 3

if [ "$(docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null || echo false)" != true ]; then
  echo 'server_container=failed'
  docker logs "$NAME" 2>&1 | tail -100 || true
  exit 21
fi

echo '===== server AWG3 state ====='
docker exec "$NAME" awg show awg0 | sed -E 's/(private key: ).*/\1(hidden)/'

TEST="$STATE/test-client.conf"
sed \
  -e 's#Endpoint = .*#Endpoint = 172.17.0.1:585#' \
  -e 's#AllowedIPs = 0.0.0.0/0#AllowedIPs = 1.1.1.1/32#' \
  -e '/^DNS = /d' \
  "$STATE/mobile-awg31.conf" > "$TEST"
chmod 600 "$TEST"

echo '===== authenticated AWG3 tunnel test ====='
set +e
TEST_OUT="$(docker run --rm --cap-add NET_ADMIN --device /dev/net/tun \
  -v "$STATE:/config:ro" --entrypoint /bin/sh "$IMAGE" -lc '
    set -e
    amneziawg-go -f awg0 >/tmp/client-awg.log 2>&1 &
    pid=$!
    trap "kill $pid >/dev/null 2>&1 || true" EXIT
    sleep 1
    awg-quick strip /config/test-client.conf >/tmp/client.stripped
    awg setconf awg0 /tmp/client.stripped
    ip addr add 10.31.0.2/32 dev awg0
    ip link set mtu 1280 up dev awg0
    ip route add 1.1.1.1/32 dev awg0
    sleep 2
    echo HANDSHAKE
    awg show awg0 latest-handshakes
    echo TRANSFER_BEFORE
    awg show awg0 transfer
    echo HTTP
    wget -qO- -T 12 http://1.1.1.1/cdn-cgi/trace | grep -E "^(ip|warp)="
    echo TRANSFER_AFTER
    awg show awg0 transfer
  ' 2>&1)"
STATUS=$?
set -e
printf '%s\n' "$TEST_OUT"
rm -f "$TEST"
if [ "$STATUS" -ne 0 ]; then
  echo "awg31_test=failed status=$STATUS"
  echo '--- server daemon log ---'
  docker exec "$NAME" sh -lc 'tail -100 /tmp/amneziawg-go.log 2>/dev/null || true' || true
  exit "$STATUS"
fi
printf '%s\n' "$TEST_OUT" | grep -q 'ip=143.246.197.187'
echo 'awg31_tunnel=ok'

echo '===== encrypt AmneziaVPN config for handoff ====='
openssl enc -aes-256-cbc -pbkdf2 -salt -pass pass:"$PASS" \
  -in "$STATE/mobile-awg31.conf" | base64 -w0 > "$GEN/mobile-awg31.conf.enc.b64"
printf '\n' >> "$GEN/mobile-awg31.conf.enc.b64"

# Remove only the temporary VLESS service from the earlier wrong approach.
docker rm -f amnezia-xray-mobile >/dev/null 2>&1 || true
rm -rf /root/amnezia-mobile-reality >/dev/null 2>&1 || true

echo '===== final survival check ====='
echo "awg31_mobile=$(docker inspect -f '{{.State.Running}}' "$NAME")"
echo "port_585_udp=$(ss -lunH | grep -c ':585 ')"
echo "old_awg0=$([ -d /sys/class/net/awg0 ] && echo up || echo missing)"
echo "old_awg1=$([ -d /sys/class/net/awg1 ] && echo up || echo missing)"
echo "legacy_xray=$(docker inspect -f '{{.State.Running}}' amnezia-xray 2>/dev/null || echo missing)"
echo 'client_format=AmneziaWG-3.1-conf'
echo MOBILE_AMNEZIAWG31_OK
