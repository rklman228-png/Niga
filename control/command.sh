#!/usr/bin/env bash
set -euo pipefail

CFG=/root/amnezia-awg31-mobile/awg0.conf
CONTAINER=amnezia-awg31-mobile
EXPECT_CLIENT_PUB_HASH='98c586e0ca7c4e527d61e1ed8cde38b945e966a7159ca97e753033f77a0062b5'
EXPECT_PSK_HASH='a91e8d455e2feee76981b8af3f0a3b7722685ec48b1e02f09f64b17ef0857a8f'
EXPECT_SERVER_PUB_HASH='6e3d7cc6d97a7262e26818201631f71700f248ca564d3eba8a753535e5882e31'
EXPECT_HPK_HASH='053394f67cde02f985d50f537e6969f9df57e687fa9ac66ae7b92b344f0211cd'

echo '===== AWG31 client diagnostics ====='
echo "container=$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || echo missing)"
echo "udp585=$(ss -lunH | grep -c ':585 ' || true)"

python3 - "$CFG" "$EXPECT_CLIENT_PUB_HASH" "$EXPECT_PSK_HASH" "$EXPECT_HPK_HASH" <<'PY'
import sys,hashlib
p,ec,ep,eh=sys.argv[1:]
text=open(p,errors='replace').read().splitlines()
sec=''; peers=[]; cur=None; hpk=None
for line in text:
    s=line.strip()
    if s.startswith('[') and s.endswith(']'):
        sec=s[1:-1]
        if sec=='Peer':
            cur={}; peers.append(cur)
        continue
    if '=' not in line: continue
    k,v=(x.strip() for x in line.split('=',1))
    if sec=='Interface' and k.lower()=='headerprotectionkey': hpk=v
    if sec=='Peer' and cur is not None: cur[k.lower()]=v
peer=next((x for x in peers if x.get('allowedips')=='10.31.0.3/32'),None)
print('peer_10_31_0_3=' + ('present' if peer else 'missing'))
if peer:
    ph=hashlib.sha256(peer.get('publickey','').encode()).hexdigest()
    sh=hashlib.sha256(peer.get('presharedkey','').encode()).hexdigest()
    print('client_public_match=' + ('yes' if ph==ec else 'NO'))
    print('psk_match=' + ('yes' if sh==ep else 'NO'))
hh=hashlib.sha256((hpk or '').encode()).hexdigest()
print('header_key_match=' + ('yes' if hh==eh else 'NO'))
print('config_peer_count='+str(len(peers)))
PY

SERVER_PUB="$(docker exec "$CONTAINER" awg show awg3m public-key 2>/dev/null || true)"
SERVER_PUB_HASH="$(printf '%s' "$SERVER_PUB" | sha256sum | awk '{print $1}')"
echo "server_public_match=$([ "$SERVER_PUB_HASH" = "$EXPECT_SERVER_PUB_HASH" ] && echo yes || echo NO)"

# Report state of the 10.31.0.3 peer without printing keys or endpoint.
docker exec "$CONTAINER" awg show awg3m dump 2>/dev/null | python3 - "$EXPECT_CLIENT_PUB_HASH" <<'PY'
import sys,time,hashlib
expect=sys.argv[1]
rows=sys.stdin.read().splitlines()[1:]
found=False
for row in rows:
    c=row.split('\t')
    if not c: continue
    if hashlib.sha256(c[0].encode()).hexdigest()!=expect: continue
    found=True
    hs=int(c[4] or 0) if len(c)>4 else 0
    rx=int(c[5] or 0) if len(c)>5 else 0
    tx=int(c[6] or 0) if len(c)>6 else 0
    print('live_peer=present')
    print('latest_handshake=' + ('never' if hs==0 else f'{max(0,int(time.time())-hs)}s_ago'))
    print(f'rx_bytes={rx}')
    print(f'tx_bytes={tx}')
if not found: print('live_peer=missing')
PY

echo AWG31_CLIENT_DIAG_OK
