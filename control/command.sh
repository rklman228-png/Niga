set -euo pipefail
JAR=$(find /root/.gradle/caches -type f -name '*.jar' | while read -r f; do if unzip -l "$f" 2>/dev/null | grep -q 'net/minecraft/network/chat/FontDescription.class'; then echo "$f"; break; fi; done)
echo "JAR=$JAR"
javap -classpath "$JAR" 'net.minecraft.network.chat.FontDescription' || true
javap -classpath "$JAR" 'net.minecraft.network.chat.FontDescription$Resource' || true
