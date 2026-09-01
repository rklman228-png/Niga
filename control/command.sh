#!/usr/bin/env bash
set -euo pipefail
IMAGE='ghcr.io/xtls/xray-core:26.3.27'
STATE='/root/vless-reality-47005'

echo '===== Xray image CLI diagnostics ====='
docker image inspect "$IMAGE" --format 'entrypoint={{json .Config.Entrypoint}} cmd={{json .Config.Cmd}}'
echo '--- version ---'
docker run --rm "$IMAGE" version || true
echo '--- help head ---'
docker run --rm "$IMAGE" help 2>&1 | head -n 40 || true

echo '--- state files present ---'
for f in server.json client.json; do
  if [ -s "$STATE/$f" ]; then echo "$f=present"; else echo "$f=missing"; fi
done

echo XRAY_CLI_DIAG_OK
