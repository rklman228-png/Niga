#!/usr/bin/env bash
set -euo pipefail

echo '===== nginx 443 layout ====='
echo '--- nginx.conf relevant ---'
nl -ba /etc/nginx/nginx.conf | sed -n '1,220p'

echo '--- amneziawg-miniapp ---'
nl -ba /etc/nginx/sites-enabled/amneziawg-miniapp 2>/dev/null | sed -n '1,220p' || true

echo '--- enihub ---'
nl -ba /etc/nginx/sites-enabled/enihub 2>/dev/null | sed -n '1,220p' || true

echo '--- dynamic modules ---'
ls -1 /etc/nginx/modules-enabled 2>/dev/null || true

echo NGINX_LAYOUT_OK
