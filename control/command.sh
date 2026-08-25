set -euo pipefail
HOT=/opt/brigada-hotfix-src
sed -i 's/modCompileOnly files/compileOnly files/' "$HOT/build.gradle"
cd "$HOT"
echo '=== build locally on VPS ==='
./gradlew clean build --no-daemon --stacktrace
JAR=$(find build/libs -maxdepth 1 -type f -name 'brigada-hotfix-*.jar' ! -name '*sources*' ! -name '*dev*' -print -quit)
test -n "$JAR" -a -s "$JAR"
echo "built=$JAR"
sha256sum "$JAR"
jar tf "$JAR" | grep -E 'BrigadaHotfix|RuntimeFixes|ChallengeServiceMixin|brigada_hotfix.mixins.json'
echo BUILD_OK
