set -euo pipefail
export GIT_TERMINAL_PROMPT=0

echo '=== auth probes ==='
command -v gh || true
gh auth status 2>&1 || true
printf 'git_credential_helper='; git config --global --get credential.helper || true

echo '=== private repo access ==='
git ls-remote https://github.com/rklman228-png/Plagin_1.git HEAD 2>&1 || true

echo '=== runner checkout auth config ==='
git config --local --get-regexp '^http\..*extraheader$' 2>/dev/null | sed 's/AUTHORIZATION:.*/AUTHORIZATION: REDACTED/' || true
