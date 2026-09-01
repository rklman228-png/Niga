#!/usr/bin/env bash
set -euo pipefail
IMAGE='ghcr.io/xtls/xray-core:26.3.27'
STATE='/root/vless-reality-47005'

redact() {
  sed -E 's/[A-Za-z0-9_+\/-]{28,}={0,2}/[redacted]/g'
}

for f in server.json client.json; do
  echo "===== validate $f ====="
  set +e
  OUT="$(docker run --rm -v "$STATE/$f:/etc/xray/config.json:ro" "$IMAGE" run -test -config=/etc/xray/config.json 2>&1)"
  CODE=$?
  set -e
  printf '%s\n' "$OUT" | redact
  echo "code=$CODE"
done

echo XRAY_VALIDATION_DIAG_OK
