set -euo pipefail
find /root /tmp /var/tmp /opt -type f -path '*/bin/gradle' 2>/dev/null | head -30
find /root /tmp /var/tmp /opt -type f -name 'gradle-9.6.1-bin*.zip' 2>/dev/null | head -20
