#!/usr/bin/env bash
set -euo pipefail

redact() {
  sed -E \
    -e 's/("(privateKey|password|token)"[[:space:]]*:[[:space:]]*")[^"]*/\1<REDACTED>/Ig' \
    -e 's/("(id|uuid)"[[:space:]]*:[[:space:]]*")[^"]*/\1<REDACTED>/Ig'
}

echo '===== container ====='
docker inspect amnezia-xray --format 'Image={{.Config.Image}} Entrypoint={{json .Config.Entrypoint}} Cmd={{json .Config.Cmd}}' || true
docker inspect amnezia-xray --format 'Mounts={{json .Mounts}}' || true
docker inspect amnezia-xray --format 'Ports={{json .HostConfig.PortBindings}}' || true

echo '===== xray dir ====='
docker exec amnezia-xray sh -lc 'ls -la /opt/amnezia/xray 2>/dev/null || true'

echo '===== server.json sanitized ====='
docker exec amnezia-xray sh -lc 'cat /opt/amnezia/xray/server.json 2>/dev/null || true' | redact

echo '===== version ====='
docker exec amnezia-xray sh -lc '/opt/amnezia/xray/xray version 2>/dev/null | head -20 || true'

echo '===== processes ====='
docker exec amnezia-xray sh -lc 'ps -ef | head -80' || true

echo XRAY_INSPECT_OK
