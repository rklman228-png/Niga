set -euo pipefail

echo '=== bridge ==='
whoami
hostname
uname -a
pwd

echo '=== minecraft service ==='
systemctl is-active minecraft || true
systemctl show minecraft -p MainPID -p FragmentPath -p WorkingDirectory --no-pager || true
ss -ltnp | grep ':25565 ' || true

echo '=== java/gradle/git ==='
java -version 2>&1 | head -n 3 || true
git --version || true
command -v gradle || true
gradle --version 2>/dev/null | head -n 8 || true

echo '=== server tree ==='
ls -lah /opt/minecraft/server || true
ls -lah /opt/minecraft/server/mods || true

echo '=== current brigada jar ==='
sha256sum /opt/minecraft/server/mods/brigada-core-0.1.0.jar 2>/dev/null || true
stat /opt/minecraft/server/mods/brigada-core-0.1.0.jar 2>/dev/null || true

echo '=== likely source dirs ==='
find /opt /root -maxdepth 3 -type d \( -name '.git' -o -name 'Plagin_1' -o -name 'brigada*' \) -print 2>/dev/null | head -n 80 || true

echo '=== recent server log ==='
journalctl -u minecraft -n 120 --no-pager | tail -n 120 || true
