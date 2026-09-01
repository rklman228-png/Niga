#!/usr/bin/env bash
set -euo pipefail

echo '===== preflight ====='
ss -lunH | grep -E '(^|:)585 ' && { echo 'port585=busy'; exit 20; } || echo 'port585=free'
echo "old_awg0=$([ -d /sys/class/net/awg0 ] && echo up || echo missing)"
echo "old_awg1=$([ -d /sys/class/net/awg1 ] && echo up || echo missing)"

echo '===== pull official AWG image ====='
docker pull amneziavpn/amneziawg-go:latest >/dev/null

echo '===== image/tool capability ====='
docker image inspect amneziavpn/amneziawg-go:latest --format 'image={{.RepoDigests}}'
docker run --rm --entrypoint /bin/sh amneziavpn/amneziawg-go:latest -lc '
  set -e
  command -v amneziawg-go || true
  command -v awg || true
  command -v awg-quick || true
  (amneziawg-go --version || amneziawg-go -v || true) 2>&1 | head -20
  (awg --version || true) 2>&1 | head -20
'
echo AWG31_PREFLIGHT_OK
