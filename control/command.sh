set -euo pipefail
cd /opt/actions-runner/_work/Niga/Niga
git rev-parse HEAD || true
wc -c control/payload.part00 control/payload.part01 control/payload.part02
sha256sum control/payload.part00 control/payload.part01 control/payload.part02
