#!/usr/bin/env bash
set -euo pipefail
umask 077
IMAGE='amneziavpn/amneziawg-go:latest'
NAME='amnezia-awg31-mobile'
STATE='/root/amnezia-awg31-mobile'
GEN="$GITHUB_WORKSPACE/control/generated"
OVERRIDE='WG_I_PREFER_BUGGY_USERSPACE_TO_POLISHED_KMOD=1'
IFACE='awg3m'

[ "$(docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null || echo false)" = true ]
[ -s "$STATE/awg0.conf" ] && [ -s "$STATE/mobile-awg31.conf" ]
mkdir -p "$GEN"

echo '===== rotate compromised mobile credentials ====='
NEW_CLIENT_PRIV="$(docker run --rm --entrypoint awg "$IMAGE" genkey)"
NEW_CLIENT_PUB="$(printf '%s\n' "$NEW_CLIENT_PRIV" | docker run --rm -i --entrypoint awg "$IMAGE" pubkey)"
NEW_PSK="$(docker run --rm --entrypoint awg "$IMAGE" genpsk)"
NEW_HPK="$(docker run --rm --entrypoint awg "$IMAGE" genkey)"
export NEW_CLIENT_PRIV NEW_CLIENT_PUB NEW_PSK NEW_HPK
python3 - <<'PY'
from pathlib import Path
import os

def rewrite(path, server=False):
    lines=Path(path).read_text().splitlines()
    section=None
    out=[]
    for line in lines:
        s=line.strip()
        if s.startswith('[') and s.endswith(']'):
            section=s[1:-1]
        if '=' in line and not s.startswith('#'):
            key=line.split('=',1)[0].strip()
            if server:
                if section=='Interface' and key=='HeaderProtectionKey':
                    line=f'HeaderProtectionKey = {os.environ["NEW_HPK"]}'
                elif section=='Peer' and key=='PublicKey':
                    line=f'PublicKey = {os.environ["NEW_CLIENT_PUB"]}'
                elif section=='Peer' and key=='PresharedKey':
                    line=f'PresharedKey = {os.environ["NEW_PSK"]}'
            else:
                if section=='Interface' and key=='PrivateKey':
                    line=f'PrivateKey = {os.environ["NEW_CLIENT_PRIV"]}'
                elif section=='Interface' and key=='HeaderProtectionKey':
                    line=f'HeaderProtectionKey = {os.environ["NEW_HPK"]}'
                elif section=='Peer' and key=='PresharedKey':
                    line=f'PresharedKey = {os.environ["NEW_PSK"]}'
        out.append(line)
    Path(path).write_text('\n'.join(out)+'\n')

rewrite('/root/amnezia-awg31-mobile/awg0.conf', True)
rewrite('/root/amnezia-awg31-mobile/mobile-awg31.conf', False)
PY
unset NEW_CLIENT_PRIV NEW_CLIENT_PUB NEW_PSK NEW_HPK
chmod 600 "$STATE/awg0.conf" "$STATE/mobile-awg31.conf"

# Apply the new peer/HPK without restarting or touching legacy AWG interfaces.
docker exec "$NAME" sh -lc 'awg-quick strip /config/awg0.conf >/tmp/rotated && awg setconf awg3m /tmp/rotated'
echo 'credentials_rotated=yes'

echo '===== prove rotated config through public endpoint ====='
TEST="$STATE/test-rotated.conf"
sed -e 's#AllowedIPs = 0.0.0.0/0#AllowedIPs = 1.1.1.1/32#' \
    -e '/^DNS = /d' "$STATE/mobile-awg31.conf" > "$TEST"
chmod 600 "$TEST"
TEST_OUT="$(docker run --rm --cap-add NET_ADMIN --device /dev/net/tun -e "$OVERRIDE" \
  -v "$STATE:/config:ro" --entrypoint /bin/sh "$IMAGE" -lc '
    set -e
    export WG_I_PREFER_BUGGY_USERSPACE_TO_POLISHED_KMOD=1
    amneziawg-go -f awg0 >/tmp/client.log 2>&1 & pid=$!
    trap "kill $pid >/dev/null 2>&1 || true" EXIT
    sleep 1; kill -0 $pid
    awg-quick strip /config/test-rotated.conf >/tmp/c
    awg setconf awg0 /tmp/c
    ip addr add 10.31.0.2/32 dev awg0
    ip link set mtu 1280 up dev awg0
    ip route add 1.1.1.1/32 dev awg0
    wget -qO- -T 12 http://1.1.1.1/cdn-cgi/trace | grep -E "^(ip|warp)="
    echo HANDSHAKE
    awg show awg0 latest-handshakes
    echo TRANSFER
    awg show awg0 transfer
  ' 2>&1)"
rm -f "$TEST"
printf '%s\n' "$TEST_OUT"
printf '%s\n' "$TEST_OUT" | grep -q '^ip=143.246.197.187$'
echo 'rotated_tunnel=ok'

# Hybrid encrypted handoff: random AES passphrase, encrypted itself with an RSA public key.
cat > /tmp/handoff_pub.pem <<'PUBKEY'
-----BEGIN PUBLIC KEY-----
MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAk/A6gVidBWe9eowmYDR5
iTJDdeVyOhzzidAeBtG0CcQrOzWZsY6DnvuuBrf7ELr2M3gA7agoyt3HvfCqeqd0
HXKu68w+efCPJhzT/QZ0+BQsG03cvMzum8q2PfEiogS+zt7nnmZo1tbjuHOXILzb
ronKKgDUW7hdJU1tcPv6ifymMUpgPdtabeJDKuO4aoNuyj7TeU3wYNW7ypsnrNx1
AWWmg8xMeh91J7nsT/hCsOtaf5ZeWiXImQlHsgXxoCgLSfY/RneGrXOogm5B7glB
exEAJuRnLmBF5m78Jltw2fRZGXIY0dYoqGFpMzAm+dDZhkCSDLy3YQ45pLaIeDGL
JL56DINT7wVyI55zOpEOXZf+RYTM4UZoFRE5h7JiONHnDeEEy1tmtJb8nBnXzvMb
VhYyiM9w/2/8oAZVkujLYOuOZT+4F6o5vGi/UL3lGDe6j35t//snpEL4gVaUwDWX
ug3ObsyCyXxV0L5O0/+eAy5zeXV1OQW3+jcqe5Hchnuo8lY0/T8GMep02dpu4W7m
JKBUy/YpEDwHFsgleu8YKVcnVVUsUVSBB3dWZ8MZK4hJYQNcIpcI53GteKwiP/cj
ekenKyJjnRgbINe5sP4e3bO9b+DDjOfjE0QaF+biCoFr/RI69j0eqSrLufGdguuJ
c9hiRApn2OcDvkmxELaGpS0CAwEAAQ==
-----END PUBLIC KEY-----
PUBKEY
HANDOFF_PASS="$(openssl rand -base64 32 | tr -d '\n')"
printf '%s' "$HANDOFF_PASS" | openssl pkeyutl -encrypt -pubin -inkey /tmp/handoff_pub.pem \
  -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256 | base64 -w0 > "$GEN/mobile-awg31.key.enc.b64"
printf '\n' >> "$GEN/mobile-awg31.key.enc.b64"
openssl enc -aes-256-cbc -pbkdf2 -salt -pass pass:"$HANDOFF_PASS" \
  -in "$STATE/mobile-awg31.conf" | base64 -w0 > "$GEN/mobile-awg31.conf.enc.b64"
printf '\n' >> "$GEN/mobile-awg31.conf.enc.b64"
unset HANDOFF_PASS
rm -f /tmp/handoff_pub.pem

echo '===== final safe status ====='
echo "awg31_mobile=$(docker inspect -f '{{.State.Running}}' "$NAME")"
echo "host_iface=$([ -d /sys/class/net/$IFACE ] && echo up || echo missing)"
echo "udp585=$(ss -lunH | grep -c ':585 ')"
echo "old_awg0=$([ -d /sys/class/net/awg0 ] && echo up || echo missing)"
echo "old_awg1=$([ -d /sys/class/net/awg1 ] && echo up || echo missing)"
echo "legacy_xray=$(docker inspect -f '{{.State.Running}}' amnezia-xray 2>/dev/null || echo missing)"
echo 'secure_handoff=ready'
echo 'MOBILE_AMNEZIAWG31_ROTATED_OK'
