set -euo pipefail
J=/opt/minecraft/server/mods/brigada-core-0.1.0.jar
javap -classpath "$J" -p dev.brigada13.core.challenge.ChallengeService | grep -E 'tick|zone|Zone|ring|Ring|particle|Particle|hold|Hold|extraction|Extraction|split|Split|spawn|Spawn|event' | sed -n '1,240p'
