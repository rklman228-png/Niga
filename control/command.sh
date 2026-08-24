#!/usr/bin/env bash
set -Eeuo pipefail

echo "::group::identity"
id
printf 'user=%s
' "$(whoami)"
printf 'hostname=%s
' "$(hostname)"
echo "::endgroup::"

echo "::group::system"
uname -a
if command -v systemd-detect-virt >/dev/null 2>&1; then
  systemd-detect-virt || true
fi
if [[ -r /etc/os-release ]]; then
  sed -n '1,12p' /etc/os-release
fi
echo "::endgroup::"

echo "::group::resources"
command -v nproc >/dev/null 2>&1 && printf 'cpus=%s
' "$(nproc)"
command -v free >/dev/null 2>&1 && free -h
command -v df >/dev/null 2>&1 && df -hT /
echo "::endgroup::"

echo "::group::services"
if command -v systemctl >/dev/null 2>&1; then
  systemctl --failed --no-pager || true
fi
echo "::endgroup::"

echo "HOST_CONTROL_OK"
