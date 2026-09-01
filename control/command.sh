#!/usr/bin/env bash
set -euo pipefail

redact() {
  sed -E \
    -e 's/^([[:space:]]*(PrivateKey|PresharedKey|Password|Token)[[:space:]]*=[[:space:]]*).*/\1<REDACTED>/I' \
    -e 's/("(privateKey|presharedKey|password|token|id|uuid)"[[:space:]]*:[[:space:]]*")[^"]*/\1<REDACTED>/Ig'
}

echo '===== xray docker inspect ====='
docker inspect amnezia-xray --format '{{json .Config}}' 2>/dev/null | redact || true
docker inspect amnezia-xray --format '{{json .Mounts}}' 2>/dev/null | redact || true
docker inspect amnezia-xray --format '{{json .HostConfig.PortBindings}}' 2>/dev/null | redact || true

echo '===== xray filesystem ====='
docker exec amnezia-xray sh -lc 'find /opt /etc /usr/local/etc -maxdepth 5 -type f 2>/dev/null | sort | grep -Ei "xray|config|json" | head -200' || true

echo '===== xray candidate configs ====='
for f in $(docker exec amnezia-xray sh -lc 'find /opt /etc /usr/local/etc -maxdepth 5 -type f \( -name "*.json" -o -name "*.conf" \) 2>/dev/null | sort' 2>/dev/null); do
  echo "--- $f ---"
  docker exec amnezia-xray sh -lc "cat '$f'" 2>/dev/null | redact || true
  echo
done

echo '===== host nginx ====='
nginx -T 2>&1 | sed -E 's/(ssl_certificate_key[[:space:]]+)[^;]+/\1<REDACTED>/Ig' | head -500 || true

echo '===== xray version/process ====='
docker exec amnezia-xray sh -lc 'ps aux; (xray version || /usr/bin/xray version || /usr/local/bin/xray version) 2>/dev/null' || true

echo XRAY_INSPECT_OK
