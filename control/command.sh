#!/usr/bin/env bash
set -euo pipefail
NAME='amnezia-awg31-mobile'

echo '===== container inspect ====='
docker ps -a --filter name="^/${NAME}$" --format 'name={{.Names}} status={{.Status}} ports={{.Ports}}'
docker inspect "$NAME" --format 'running={{.State.Running}} restarting={{.State.Restarting}} exit={{.State.ExitCode}} error={{.State.Error}} restart_count={{.RestartCount}}' 2>/dev/null || true

echo '===== container logs ====='
docker logs --tail 200 "$NAME" 2>&1 || true

echo '===== inside container ====='
docker exec "$NAME" /bin/sh -lc '
  echo PROCESSES
  ps -ef || true
  echo LINKS
  ip -br link || true
  echo ADDRS
  ip -br addr || true
  echo AWG_SHOW
  awg show || true
  echo SOCKETS
  ls -la /var/run/amneziawg /var/run/wireguard 2>/dev/null || true
  echo CONFIG_STRIP
  awg-quick strip /config/awg0.conf 2>&1 | sed -E "s#^(private_key|preshared_key)=.*#\\1=<REDACTED>#" || true
'

echo '===== old VPN survival ====='
echo "old_awg0=$([ -d /sys/class/net/awg0 ] && echo up || echo missing)"
echo "old_awg1=$([ -d /sys/class/net/awg1 ] && echo up || echo missing)"
echo AWG31_DIAG_OK
