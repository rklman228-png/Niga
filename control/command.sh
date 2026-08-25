set -euo pipefail
J=/opt/minecraft/server/mods/brigada-core-0.1.0.jar
O=/tmp/csvc.javap
javap -classpath "$J" -c -p dev.brigada13.core.challenge.ChallengeService > "$O"
for m in tickExtraction tickSplit tickHold renderZone participantsSplit; do
  echo "===== $m ====="
  awk -v m="$m" '
    $0 ~ "^[ ]+(private|public|protected).* " m "\\(" {p=1}
    p {print}
    p && NR>1 && $0 ~ "^[ ]+(private|public|protected).*\\(" && $0 !~ " " m "\\(" {exit}
  ' "$O" | head -n 700
 done
