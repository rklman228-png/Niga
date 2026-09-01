#!/usr/bin/env bash
set -euo pipefail

section() { printf '\n===== %s =====\n' "$1"; }
run() {
  printf '$ %s\n' "$*"
  bash -lc "$*" 2>&1 || true
}

section host
run 'date -Is'
run 'hostnamectl 2>/dev/null || hostname'
run 'uname -a'
run 'id'

section network
run 'ip -br addr'
run 'ip route'
run 'ip -6 route'
run 'sysctl net.ipv4.ip_forward net.ipv6.conf.all.forwarding 2>/dev/null'
run 'ss -lunpt'

section services
run "systemctl --no-pager --type=service --state=running | grep -Ei 'amnezia|wireguard|wg|awg|xray|docker|podman' || true"
run "systemctl --no-pager list-unit-files | grep -Ei 'amnezia|wireguard|wg|awg|xray' || true"

section containers
run 'docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true'
run 'docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" 2>/dev/null || true'
run 'podman ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true'

section vpn_interfaces
run 'wg show 2>/dev/null || true'
run 'awg show 2>/dev/null || true'
run 'ip -details link show | grep -EA4 -i "wireguard|amnezia|awg" || true'

section config_files
run "find /opt/amnezia /etc/amnezia /etc/wireguard /etc/amneziawg /etc/awg /etc/xray /usr/local/etc/xray -maxdepth 5 -type f 2>/dev/null | sort || true"

section sanitized_configs
while IFS= read -r f; do
  [ -f "$f" ] || continue
  echo "--- $f ---"
  sed -E \
    -e 's/^([[:space:]]*(PrivateKey|PresharedKey|Password|Token)[[:space:]]*=[[:space:]]*).*/\1<REDACTED>/I' \
    -e 's/("(privateKey|presharedKey|password|token)"[[:space:]]*:[[:space:]]*")[^"]*/\1<REDACTED>/Ig' \
    "$f" 2>/dev/null || true
  echo
done < <(find /opt/amnezia /etc/amnezia /etc/wireguard /etc/amneziawg /etc/awg /etc/xray /usr/local/etc/xray -maxdepth 5 -type f \( -name '*.conf' -o -name '*.json' -o -name '*.ini' \) 2>/dev/null | sort)

section firewall
run 'iptables-save 2>/dev/null || true'
run 'ip6tables-save 2>/dev/null || true'
run 'nft list ruleset 2>/dev/null || true'

section modules
run "lsmod | grep -Ei 'wireguard|amnezia|awg' || true"
run "modinfo amneziawg 2>/dev/null | head -100 || true"
run "modinfo wireguard 2>/dev/null | head -100 || true"

section amnezia_logs
for c in $(docker ps -a --format '{{.Names}}' 2>/dev/null | grep -Ei 'amnezia|wireguard|awg|xray' || true); do
  echo "--- container: $c ---"
  docker logs --tail 120 "$c" 2>&1 | sed -E \
    -e 's/^([[:space:]]*(PrivateKey|PresharedKey|Password|Token)[[:space:]]*=[[:space:]]*).*/\1<REDACTED>/I' \
    -e 's/("(privateKey|presharedKey|password|token)"[[:space:]]*:[[:space:]]*")[^"]*/\1<REDACTED>/Ig' || true
  echo
done

echo VPN_DIAGNOSTICS_OK
