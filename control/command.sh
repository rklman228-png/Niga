#!/usr/bin/env bash
set -euo pipefail

echo '===== xray binary ====='
docker exec amnezia-xray sh -lc 'command -v xray || true'
echo '===== xray version ====='
docker exec amnezia-xray sh -lc 'xray version 2>/dev/null | head -20 || true'
echo '===== reality support ====='
docker exec amnezia-xray sh -lc 'xray help 2>&1 | head -80 || true'
# Do not print generated key material. Just verify the generator exists.
if docker exec amnezia-xray sh -lc 'xray x25519 >/tmp/reality-test 2>&1 && test -s /tmp/reality-test'; then
  echo 'x25519_generator=ok'
  docker exec amnezia-xray sh -lc 'rm -f /tmp/reality-test'
else
  echo 'x25519_generator=failed'
fi

echo XRAY_CAPABILITY_OK
