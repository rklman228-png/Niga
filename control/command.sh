set -euo pipefail
cd /opt/brigada-core-src
echo '=== sound references ==='
grep -R "SoundEvents\|playSound(" -n src/main/java | head -n 80 || true
echo '=== build mappings hint ==='
grep -R "DamageTypes.FALL\|resetFallDistance" -n src/main/java | head -n 40 || true
