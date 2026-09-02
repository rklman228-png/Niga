#!/usr/bin/env bash
set -euo pipefail

echo '===== AWG31 sanitized config ====='
for f in /root/amnezia-awg31-mobile/awg0.conf /root/amnezia-awg31-mobile/mobile-awg31.conf; do
  echo "--- $f ---"
  if [ -s "$f" ]; then
    python3 - "$f" <<'PY'
import sys
p=sys.argv[1]
secret=('privatekey','presharedkey','publickey','headerprotectionkey')
for raw in open(p, errors='replace'):
    s=raw.rstrip('\n')
    st=s.strip()
    if not st or st.startswith('#'):
        continue
    if '=' in s:
        k,v=s.split('=',1)
        kl=k.strip().lower()
        if kl in secret:
            print(f'{k.strip()} = <redacted>')
        else:
            print(s)
    else:
        print(s)
PY
  else
    echo missing
  fi
done

echo '--- container command/image ---'
docker inspect -f 'image={{.Config.Image}} cmd={{json .Config.Cmd}} entry={{json .Config.Entrypoint}}' amnezia-awg31-mobile 2>/dev/null || true

echo AWG31_SANITIZED_OK
