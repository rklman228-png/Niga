set -euo pipefail
HOT=/opt/brigada-hotfix-src
RUNTIME="$HOT/src/main/java/dev/brigada13/hotfix/RuntimeFixes.java"

python3 - <<'PY'
from pathlib import Path
p = Path('/opt/brigada-hotfix-src/src/main/java/dev/brigada13/hotfix/RuntimeFixes.java')
s = p.read_text()
s = s.replace('import net.minecraft.core.registries.Registries;\n', 'import net.minecraft.core.registries.BuiltInRegistries;\nimport net.minecraft.core.registries.Registries;\n')
s = s.replace('import net.minecraft.world.level.block.Blocks;\n', 'import net.minecraft.world.level.block.Block;\nimport net.minecraft.world.level.block.Blocks;\n')
s = s.replace('private static final double MOB_EDGE_MARGIN = 2.35;\n', '''private static final double MOB_EDGE_MARGIN = 2.35;\n    private static final Block GRAY_BOUNDARY = BuiltInRegistries.BLOCK.getValue(Identifier.parse("minecraft:gray_stained_glass"));\n    private static final Block BROWN_BOUNDARY = BuiltInRegistries.BLOCK.getValue(Identifier.parse("minecraft:brown_stained_glass"));\n    private static final Block LIME_BOUNDARY = BuiltInRegistries.BLOCK.getValue(Identifier.parse("minecraft:lime_stained_glass"));\n''')
s = s.replace('level.isDay()', 'isDay(level)')
s = s.replace('if (block == Blocks.GRAY_STAINED_GLASS || block == Blocks.BROWN_STAINED_GLASS\n                    || block == Blocks.LIME_STAINED_GLASS) {', 'if (block == GRAY_BOUNDARY || block == BROWN_BOUNDARY || block == LIME_BOUNDARY) {')
needle = '    private static void fixDefense(ServerLevel level, ChallengeDefinition definition, ActiveChallengeState state) {'
insert = '''    private static boolean isDay(ServerLevel level) {\n        long time = Math.floorMod(level.getDayTime(), 24000L);\n        return time < 12000L;\n    }\n\n'''
if insert not in s:
    s = s.replace(needle, insert + needle)
p.write_text(s)
PY

cd "$HOT"
echo '=== compile hotfix v2 retry ==='
./gradlew clean build --no-daemon --stacktrace
JAR=$(find build/libs -maxdepth 1 -type f -name 'brigada-hotfix-*.jar' ! -name '*sources*' ! -name '*dev*' -print -quit)
test -n "$JAR" -a -s "$JAR"
sha256sum "$JAR"
jar tf "$JAR" | grep -E 'RuntimeFixes|ChallengeServiceMixin|brigada_hotfix.mixins.json'
echo BUILD_V2_OK
