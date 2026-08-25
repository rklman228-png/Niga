set -euo pipefail
J=/root/.gradle/caches/fabric-loom/minecraftMaven/net/minecraft/minecraft-merged-deobf/26.3-snapshot-9/minecraft-merged-deobf-26.3-snapshot-9.jar
jar tf "$J" | grep -Ei 'dialog|show.*packet|locator|waypoint' | head -250
