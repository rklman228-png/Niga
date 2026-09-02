#!/usr/bin/env bash
set -euo pipefail

echo '===== main VLESS inspect ====='
echo "running=$(docker inspect -f '{{.State.Running}}' xray-vless-47005 2>/dev/null || echo missing)"
echo '--- mounts ---'
docker inspect -f '{{range .Mounts}}{{println .Source "->" .Destination}}{{end}}' xray-vless-47005 2>/dev/null || true
echo '--- image/cmd ---'
docker inspect -f 'image={{.Config.Image}} cmd={{json .Config.Cmd}}' xray-vless-47005 2>/dev/null || true
echo '--- config summary ---'
for f in /root/vless-reality-mobile/server.json /root/vless-reality-mobile/config.json /root/vless-reality/config.json /root/vless-reality/server.json; do
  if [ -s "$f" ]; then
    echo "found=$f"
    python3 - "$f" <<'PY'
import json,sys
p=sys.argv[1]
d=json.load(open(p))
for i,ib in enumerate(d.get('inbounds',[])):
    if ib.get('protocol')=='vless':
        c=ib.get('settings',{}).get('clients',[])
        ss=ib.get('streamSettings',{})
        r=ss.get('realitySettings',{})
        print(f'inbound={i} port={ib.get("port")} clients={len(c)} network={ss.get("network")} security={ss.get("security")} serverNames={r.get("serverNames",[])}')
PY
  fi
done
echo MAIN_VLESS_INSPECT_OK
