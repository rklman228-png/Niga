#!/usr/bin/env bash
set -euo pipefail

echo '===== xray safe diagnostics ====='
echo "legacy_xray=$(docker inspect -f '{{.State.Running}}' amnezia-xray 2>/dev/null || echo missing)"
echo '--- container image/mounts/ports ---'
docker inspect amnezia-xray --format 'image={{.Config.Image}} network={{.HostConfig.NetworkMode}}' 2>/dev/null || true
docker inspect amnezia-xray --format '{{range .Mounts}}mount={{.Source}} -> {{.Destination}}{{"\n"}}{{end}}' 2>/dev/null || true
docker inspect amnezia-xray --format '{{range $p,$v := .NetworkSettings.Ports}}port={{$p}}{{"\n"}}{{end}}' 2>/dev/null || true

echo '--- listening tcp ports ---'
ss -ltnH | awk '{print $4}' | sed 's/.*://' | sort -n | uniq | tail -n 80

echo '--- candidate ports ---'
for p in 47005 8443 2053 2083 2096 2443 5443; do
  if ss -ltnH | grep -qE "[:.]${p}[[:space:]]"; then echo "$p=busy"; else echo "$p=free"; fi
done

echo '--- docker ps amnezia ---'
docker ps --format '{{.Names}} {{.Image}} {{.Ports}}' | grep -E '^amnezia-' || true

echo XRAY_SAFE_DIAG_OK
