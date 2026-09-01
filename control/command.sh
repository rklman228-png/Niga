#!/usr/bin/env bash
set -euo pipefail
umask 077
IMAGE='amneziavpn/amneziawg-go:latest'
NAME='amnezia-awg31-mobile'
STATE='/root/amnezia-awg31-mobile'
GEN="$GITHUB_WORKSPACE/control/generated"
PASS='DNjex7I3cV39MqPJdlMRq2jVj6qdC1VE'
OVERRIDE='WG_I_PREFER_BUGGY_USERSPACE_TO_POLISHED_KMOD=1'

# Match current AmneziaWG 3.1 generator defaults for transport signature fields.
for f in "$STATE/awg0.conf" "$STATE/mobile-awg31.conf"; do
  sed -i -E \
    -e 's/^S4 = .*/S4 = 12/' \
    -e 's/^H1 = .*/H1 = 1/' \
    -e 's/^H2 = .*/H2 = 2/' \
    -e 's/^H3 = .*/H3 = 3/' \
    -e 's/^H4 = .*/H4 = 4/' "$f"
done
chmod 600 "$STATE/awg0.conf" "$STATE/mobile-awg31.conf"

docker rm -f "$NAME" >/dev/null 2>&1 || true
cat > "$STATE/start-userspace.sh" <<'EOF'
#!/bin/sh
set -eu
export WG_I_PREFER_BUGGY_USERSPACE_TO_POLISHED_KMOD=1
rm -f /var/run/amneziawg/awg0.sock /var/run/wireguard/awg0.sock 2>/dev/null || true
amneziawg-go -f awg0 >/tmp/amneziawg-go.log 2>&1 &
pid=$!
trap 'kill "$pid" >/dev/null 2>&1 || true' TERM INT EXIT
sleep 1
kill -0 "$pid"
awg-quick strip /config/awg0.conf >/tmp/awg0.stripped
awg setconf awg0 /tmp/awg0.stripped
ip addr add 10.31.0.1/24 dev awg0
ip link set mtu 1280 up dev awg0
iptables -C FORWARD -i awg0 -o eth0 -j ACCEPT 2>/dev/null || iptables -A FORWARD -i awg0 -o eth0 -j ACCEPT
iptables -C FORWARD -i eth0 -o awg0 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || iptables -A FORWARD -i eth0 -o awg0 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -t nat -C POSTROUTING -s 10.31.0.0/24 -o eth0 -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -s 10.31.0.0/24 -o eth0 -j MASQUERADE
wait "$pid"
EOF
chmod 700 "$STATE/start-userspace.sh"

echo '===== launch official-style AWG 3.1 ====='
docker run -d --name "$NAME" --restart unless-stopped \
  --cap-add NET_ADMIN --device /dev/net/tun --sysctl net.ipv4.ip_forward=1 \
  -e "$OVERRIDE" -p 585:585/udp -v "$STATE:/config:ro" \
  --entrypoint /bin/sh "$IMAGE" /config/start-userspace.sh >/dev/null
sleep 3
test "$(docker inspect -f '{{.State.Running}}' "$NAME")" = true

echo '===== server parameters ====='
docker exec "$NAME" awg show awg0 | sed -E 's/(private key: ).*/\1(hidden)/'

SERVER_CIP="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$NAME")"
echo "server_container_ip=$SERVER_CIP"

run_test() {
  endpoint="$1"; label="$2"
  testconf="$STATE/test-${label}.conf"
  sed -e "s#Endpoint = .*#Endpoint = ${endpoint}:585#" \
      -e 's#AllowedIPs = 0.0.0.0/0#AllowedIPs = 1.1.1.1/32#' \
      -e '/^DNS = /d' "$STATE/mobile-awg31.conf" > "$testconf"
  chmod 600 "$testconf"
  echo "===== test ${label} ====="
  set +e
  out="$(docker run --rm --cap-add NET_ADMIN --device /dev/net/tun \
    -e "$OVERRIDE" -v "$STATE:/config:ro" --entrypoint /bin/sh "$IMAGE" -lc "
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
    " 2>&1)"
  st=$?
  set -e
  printf '%s\n' "$out"
  rm -f "$testconf"
  return "$st"
}

# First prove protocol/config directly to the server container, then prove host UDP publishing.
run_test "$SERVER_CIP" direct
run_test '172.17.0.1' published

echo '===== server after tests ====='
docker exec "$NAME" awg show awg0 | grep -E 'latest handshake|transfer|endpoint' || true

# Final mobile profile remains pointed at the public VPS endpoint.
grep -q '^Endpoint = 143.246.197.187:585$' "$STATE/mobile-awg31.conf"

openssl enc -aes-256-cbc -pbkdf2 -salt -pass pass:"$PASS" \
  -in "$STATE/mobile-awg31.conf" | base64 -w0 > "$GEN/mobile-awg31.conf.enc.b64"
printf '\n' >> "$GEN/mobile-awg31.conf.enc.b64"

docker rm -f amnezia-xray-mobile >/dev/null 2>&1 || true
rm -rf /root/amnezia-mobile-reality >/dev/null 2>&1 || true

echo '===== survival ====='
echo "awg31_mobile=$(docker inspect -f '{{.State.Running}}' "$NAME")"
echo "port_585_udp=$(ss -lunH | grep -c ':585 ')"
echo "old_awg0=$([ -d /sys/class/net/awg0 ] && echo up || echo missing)"
echo "old_awg1=$([ -d /sys/class/net/awg1 ] && echo up || echo missing)"
echo "legacy_xray=$(docker inspect -f '{{.State.Running}}' amnezia-xray 2>/dev/null || echo missing)"
echo 'MOBILE_AMNEZIAWG31_OK'
