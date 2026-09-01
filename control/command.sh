#!/usr/bin/env bash
set -euo pipefail
umask 077
IMAGE='amneziavpn/amneziawg-go:latest'
NAME='amnezia-awg31-mobile'
STATE='/root/amnezia-awg31-mobile'
GEN="$GITHUB_WORKSPACE/control/generated"
PASS='DNjex7I3cV39MqPJdlMRq2jVj6qdC1VE'
OVERRIDE='WG_I_PREFER_BUGGY_USERSPACE_TO_POLISHED_KMOD=1'
IFACE='awg3m'

[ -s "$STATE/awg0.conf" ] && [ -s "$STATE/mobile-awg31.conf" ]
docker rm -f "$NAME" >/dev/null 2>&1 || true
ip link del "$IFACE" >/dev/null 2>&1 || true

cat > "$STATE/start-hostnet.sh" <<'EOF'
#!/bin/sh
set -eu
export WG_I_PREFER_BUGGY_USERSPACE_TO_POLISHED_KMOD=1
IFACE=awg3m
rm -f /var/run/amneziawg/${IFACE}.sock /var/run/wireguard/${IFACE}.sock 2>/dev/null || true
amneziawg-go -f "$IFACE" >/tmp/amneziawg-go.log 2>&1 &
pid=$!
cleanup() {
  iptables -D INPUT -p udp --dport 585 -j ACCEPT >/dev/null 2>&1 || true
  iptables -D FORWARD -i "$IFACE" -o eth0 -j ACCEPT >/dev/null 2>&1 || true
  iptables -D FORWARD -i eth0 -o "$IFACE" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT >/dev/null 2>&1 || true
  iptables -t nat -D POSTROUTING -s 10.31.0.0/24 -o eth0 -j MASQUERADE >/dev/null 2>&1 || true
  kill "$pid" >/dev/null 2>&1 || true
}
trap cleanup TERM INT EXIT
sleep 1
kill -0 "$pid"
awg-quick strip /config/awg0.conf >/tmp/awg3.stripped
awg setconf "$IFACE" /tmp/awg3.stripped
ip addr add 10.31.0.1/24 dev "$IFACE"
ip link set mtu 1280 up dev "$IFACE"
iptables -C INPUT -p udp --dport 585 -j ACCEPT 2>/dev/null || iptables -I INPUT 1 -p udp --dport 585 -j ACCEPT
iptables -C FORWARD -i "$IFACE" -o eth0 -j ACCEPT 2>/dev/null || iptables -I FORWARD 1 -i "$IFACE" -o eth0 -j ACCEPT
iptables -C FORWARD -i eth0 -o "$IFACE" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || iptables -I FORWARD 1 -i eth0 -o "$IFACE" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -t nat -C POSTROUTING -s 10.31.0.0/24 -o eth0 -j MASQUERADE 2>/dev/null || iptables -t nat -I POSTROUTING 1 -s 10.31.0.0/24 -o eth0 -j MASQUERADE
wait "$pid"
EOF
chmod 700 "$STATE/start-hostnet.sh"

echo '===== launch AWG3 on host network ====='
docker run -d --name "$NAME" --restart unless-stopped --network host \
  --cap-add NET_ADMIN --device /dev/net/tun -e "$OVERRIDE" \
  -v "$STATE:/config:ro" --entrypoint /bin/sh "$IMAGE" /config/start-hostnet.sh >/dev/null
sleep 3
test "$(docker inspect -f '{{.State.Running}}' "$NAME")" = true

echo '===== host listener/interface ====='
ip -d link show "$IFACE" | head -8
ss -lunp | grep ':585 ' || true
docker exec "$NAME" awg show "$IFACE" | sed -E 's/(private key: ).*/\1(hidden)/'

run_test() {
  endpoint="$1"; label="$2"
  f="$STATE/test-${label}.conf"
  sed -e "s#Endpoint = .*#Endpoint = ${endpoint}:585#" \
      -e 's#AllowedIPs = 0.0.0.0/0#AllowedIPs = 1.1.1.1/32#' \
      -e '/^DNS = /d' "$STATE/mobile-awg31.conf" > "$f"
  chmod 600 "$f"
  echo "===== test ${label} ====="
  docker run --rm --cap-add NET_ADMIN --device /dev/net/tun -e "$OVERRIDE" \
    -v "$STATE:/config:ro" --entrypoint /bin/sh "$IMAGE" -lc "
      set -e
      export WG_I_PREFER_BUGGY_USERSPACE_TO_POLISHED_KMOD=1
      amneziawg-go -f awg0 >/tmp/client.log 2>&1 & pid=\$!
      trap 'kill \$pid >/dev/null 2>&1 || true' EXIT
      sleep 1; kill -0 \$pid
      awg-quick strip /config/test-${label}.conf >/tmp/c
      awg setconf awg0 /tmp/c
      ip addr add 10.31.0.2/32 dev awg0
      ip link set mtu 1280 up dev awg0
      ip route add 1.1.1.1/32 dev awg0
      wget -qO- -T 12 http://1.1.1.1/cdn-cgi/trace | grep -E '^(ip|warp)='
      echo HANDSHAKE
      awg show awg0 latest-handshakes
      echo TRANSFER
      awg show awg0 transfer
    "
  rm -f "$f"
}

# Host bridge IP proves reachability from another network namespace; public IP proves final Endpoint routing on-host.
run_test '172.17.0.1' hostbridge
run_test '143.246.197.187' publicip

echo '===== server after tests ====='
docker exec "$NAME" awg show "$IFACE" | grep -E 'endpoint|latest handshake|transfer' || true

grep -q '^Endpoint = 143.246.197.187:585$' "$STATE/mobile-awg31.conf"
mkdir -p "$GEN"
openssl enc -aes-256-cbc -pbkdf2 -salt -pass pass:"$PASS" \
  -in "$STATE/mobile-awg31.conf" | base64 -w0 > "$GEN/mobile-awg31.conf.enc.b64"
printf '\n' >> "$GEN/mobile-awg31.conf.enc.b64"

docker rm -f amnezia-xray-mobile >/dev/null 2>&1 || true
rm -rf /root/amnezia-mobile-reality >/dev/null 2>&1 || true

echo '===== final survival ====='
echo "awg31_mobile=$(docker inspect -f '{{.State.Running}}' "$NAME")"
echo "host_iface=$([ -d /sys/class/net/$IFACE ] && echo up || echo missing)"
echo "port_585_udp=$(ss -lunH | grep -c ':585 ')"
echo "old_awg0=$([ -d /sys/class/net/awg0 ] && echo up || echo missing)"
echo "old_awg1=$([ -d /sys/class/net/awg1 ] && echo up || echo missing)"
echo "legacy_xray=$(docker inspect -f '{{.State.Running}}' amnezia-xray 2>/dev/null || echo missing)"
echo 'MOBILE_AMNEZIAWG31_OK'
