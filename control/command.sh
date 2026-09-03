#!/usr/bin/env bash
set -euo pipefail

ROOT=/root/amnezia-awg31-mobile
SERVER_CFG="$ROOT/awg0.conf"
TEMPLATE="$ROOT/mobile-awg31.conf"
CONTAINER=amnezia-awg31-mobile
OUTDIR=control/generated
mkdir -p "$OUTDIR"
rm -f "$OUTDIR/awg31-full.key.enc.b64" "$OUTDIR/awg31-full.payload.enc.b64"

IP="$(python3 - "$SERVER_CFG" <<'PY'
import re,sys
text=open(sys.argv[1],errors='replace').read()
used=set()
for m in re.finditer(r'^AllowedIPs\s*=\s*10\.31\.0\.(\d+)/32\s*$',text,re.M):
    used.add(int(m.group(1)))
for n in range(3,255):
    if n not in used:
        print(f'10.31.0.{n}')
        break
else:
    raise SystemExit('no free client address')
PY
)"
SUFFIX="${IP##*.}"
CLIENT_TMP="$ROOT/.client-new-$SUFFIX.conf"
PRIV="$ROOT/.client-new-$SUFFIX.key"
PUB="$ROOT/.client-new-$SUFFIX.pub"
PSK="$ROOT/.client-new-$SUFFIX.psk"
PASSFILE="$ROOT/.client-new-$SUFFIX.pass"
PUBPEM="$ROOT/.handoff-public.pem"
BACKUP="$ROOT/awg0.conf.bak-$(date -u +%Y%m%dT%H%M%SZ)"
CIPHER="$ROOT/.client-new-$SUFFIX.enc"
KEYCIPHER="$ROOT/.client-new-$SUFFIX.key.enc"

cleanup(){
  rm -f "$CLIENT_TMP" "$PRIV" "$PUB" "$PSK" "$PASSFILE" "$PUBPEM" "$CIPHER" "$KEYCIPHER"
}
trap cleanup EXIT
umask 077

echo '===== create new AWG31 client ====='
echo "client_address=$IP/32"
awg genkey > "$PRIV"
awg pubkey < "$PRIV" > "$PUB"
awg genpsk > "$PSK"
CLIENT_PRIV="$(cat "$PRIV")"
CLIENT_PUB="$(cat "$PUB")"
CLIENT_PSK="$(cat "$PSK")"
export IP CLIENT_PRIV CLIENT_PUB CLIENT_PSK

cp -a "$SERVER_CFG" "$BACKUP"
cat >> "$SERVER_CFG" <<EOF

[Peer]
PublicKey = $CLIENT_PUB
PresharedKey = $CLIENT_PSK
AllowedIPs = $IP/32
EOF
chmod 600 "$SERVER_CFG"

python3 - "$TEMPLATE" "$CLIENT_TMP" <<'PY'
import os,sys
src,dst=sys.argv[1:]
priv=os.environ['CLIENT_PRIV']; psk=os.environ['CLIENT_PSK']; ip=os.environ['IP']
section=''
out=[]
for raw in open(src,errors='replace'):
    line=raw.rstrip('\n')
    s=line.strip()
    if s.startswith('[') and s.endswith(']'):
        section=s[1:-1]
        out.append(line); continue
    if '=' in line:
        k,v=line.split('=',1); key=k.strip().lower()
        if section=='Interface' and key=='privatekey':
            line=f'PrivateKey = {priv}'
        elif section=='Interface' and key=='address':
            line=f'Address = {ip}/32'
        elif section=='Peer' and key=='presharedkey':
            line=f'PresharedKey = {psk}'
    out.append(line)
open(dst,'w').write('\n'.join(out).rstrip()+'\n')
PY
chmod 600 "$CLIENT_TMP"

echo '===== validate configs ====='
if ! docker exec "$CONTAINER" awg-quick strip /config/awg0.conf >/dev/null 2>&1; then
  cp -a "$BACKUP" "$SERVER_CFG"
  echo server_config_validation=failed
  exit 71
fi
if ! docker exec "$CONTAINER" awg-quick strip "/config/.client-new-$SUFFIX.conf" >/dev/null 2>&1; then
  cp -a "$BACKUP" "$SERVER_CFG"
  echo client_config_validation=failed
  exit 72
fi
echo configs=valid

echo '===== restart AWG31 ====='
docker restart "$CONTAINER" >/dev/null
sleep 3
if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || echo false)" != true ]; then
  cp -a "$BACKUP" "$SERVER_CFG"
  docker restart "$CONTAINER" >/dev/null 2>&1 || true
  echo restart=failed
  exit 73
fi
LIVE_PEERS="$(awg show awg3m peers 2>/dev/null | wc -l | tr -d ' ')"
CFG_PEERS="$(grep -c '^\[Peer\]' "$SERVER_CFG")"
echo "config_peers=$CFG_PEERS"
echo "live_peers=$LIVE_PEERS"
echo "udp585=$(ss -lunH | grep -c ':585 ' || true)"

cat > "$PUBPEM" <<'PUBEOF'
-----BEGIN PUBLIC KEY-----
MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAyiaxkyxRQTu4TIvkbEz5
wyuoigx55Mciq596micxyLMOSB/Viq+ioraqmxFHYDpbS4DgcmmjBh3hT+CtPbhu
yjsztC3zLvlz8BQcpp3Hmmk6gbNdIisZOmAIqhr5jeLvhSNohrE3M5SL/0S6X+Z2
G9VzKtzOqEvob7qn8SbWJoBZ0uuTBmaJc12bGfuYFGY+Ecx4zPLB4JKMZfDkrjtZ
r5i1EzfvSRjuIrFWqdsZrYRx69J7AGYd19x5gSEIJ7my7kT5C1R5qOrl7P6GSkSm
PfOdhZ4csViqfnMMLaDsSzgD5JUBQXqZjGvdisZGcS6V9qoLkAbA+FMfV1XK50qj
8MZAPQj/AlBORZLRAk+Y88s8W0n3LqsYymMOJQmrNSrhZWKnsonhaD02jLdALnsu
+FOfEX39sSSoMFrv2BOyI9bZLRn8YuwV1LdyK66Jp1sV/8evJ910Haibwm5iYdHJ
mM5jYqEiyE8+tEIw2d7JNiWKzYE+U6YO3iqOq0NPR/p38oYr36p94ASaNzGBNJbc
wJ8Dx2KKu/zpANB6kZXumtOBTfSHzSq6tvnnLcV5KuR/2PdmBppBbR+WaEqy4bk+
HQmHlhOJ+pxYdPs5WHeZywboF+IsaOsXrymL3+KGHqUjNbv4UxRXW45J9kN0ye9m
W+eLL1dZ6LRWp18aRH4eq4kCAwEAAQ==
-----END PUBLIC KEY-----
PUBEOF
openssl rand -hex 32 > "$PASSFILE"
openssl enc -aes-256-cbc -salt -pbkdf2 -iter 200000 -pass file:"$PASSFILE" -in "$CLIENT_TMP" -out "$CIPHER"
openssl pkeyutl -encrypt -pubin -inkey "$PUBPEM" -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256 -pkeyopt rsa_mgf1_md:sha256 -in "$PASSFILE" -out "$KEYCIPHER"
base64 -w0 "$CIPHER" > "$OUTDIR/awg31-full.payload.enc.b64"
base64 -w0 "$KEYCIPHER" > "$OUTDIR/awg31-full.key.enc.b64"
echo secure_handoff=ready
unset CLIENT_PRIV CLIENT_PUB CLIENT_PSK

echo "awg31=$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || echo missing)"
echo "main_vless=$(docker inspect -f '{{.State.Running}}' xray-vless-47005 2>/dev/null || echo missing)"
echo NEW_AWG31_FULL_READY
