set -euo pipefail

echo '=== local source repo ==='
if [ -d /opt/brigada-core-src/.git ]; then
  git -C /opt/brigada-core-src remote -v || true
  git -C /opt/brigada-core-src status --short --branch || true
else
  echo '/opt/brigada-core-src is not a git repo'
fi

echo '=== auth helpers ==='
git config --global credential.helper || true
command -v gh || true
if command -v gh >/dev/null 2>&1; then gh auth status 2>&1 || true; fi

echo '=== non-writing remote check ==='
git ls-remote https://github.com/rklman228-png/Plagin_1.git HEAD refs/heads/main | head -n 5

echo GIT_ACCESS_INSPECTED
