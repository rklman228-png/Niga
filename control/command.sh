set -euo pipefail

echo '=== source ==='
cd /opt/brigada-core-src
pwd
ls -lah
printf 'git_dir='; test -d .git && echo yes || echo no
if test -d .git; then
  git status --short --branch
  git remote -v || true
  git rev-parse HEAD || true
fi
printf 'gradlew='; test -x ./gradlew && echo yes || echo no
printf 'gradle='; command -v gradle || true
find build/libs -maxdepth 1 -type f -printf '%TY-%Tm-%Td %TH:%TM:%TS %s %p\n' 2>/dev/null | sort || true

echo '=== server jar ==='
sha256sum /opt/minecraft/server/mods/brigada-core-0.1.0.jar
