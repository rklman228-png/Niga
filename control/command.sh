#!/usr/bin/env bash
set -euo pipefail
IMAGE='amneziavpn/amneziawg-go:latest'

echo '===== userspace override strings ====='
docker run --rm --entrypoint /bin/sh "$IMAGE" -lc '
  strings /usr/bin/amneziawg-go 2>/dev/null | grep -Ei "PREFER|USERSPACE|KMOD|POLISHED|BUGGY|WG_I|AMNEZIAWG" | head -200 || true
'

echo '===== likely WireGuard override ====='
docker run --rm --cap-add NET_ADMIN --device /dev/net/tun \
  -e WG_I_PREFER_BUGGY_USERSPACE_TO_POLISHED_KMOD=1 \
  --entrypoint /bin/sh "$IMAGE" -lc '
    set -e
    rm -f /var/run/amneziawg/awgprobe.sock /var/run/wireguard/awgprobe.sock 2>/dev/null || true
    amneziawg-go -f awgprobe >/tmp/go.log 2>&1 &
    pid=$!
    sleep 1
    echo PROCESS
    kill -0 "$pid" && echo alive=yes || echo alive=no
    echo LOG
    cat /tmp/go.log || true
    echo LINKS
    ip -d link show awgprobe 2>/dev/null || true
    echo SOCKETS
    ls -la /var/run/amneziawg /var/run/wireguard 2>/dev/null || true
    kill "$pid" >/dev/null 2>&1 || true
  '
echo USERSPACE_OVERRIDE_PROBE_OK
