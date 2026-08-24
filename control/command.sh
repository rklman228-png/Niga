set -euo pipefail
systemctl stop minecraft.service || true
printf '%s' 'ewogICJzY2hlbWFWZXJzaW9uIjogMSwKICAiaWQiOiAiYnJpZ2FkYV9jb3JlIiwKICAidmVyc2lvbiI6ICIke3ZlcnNpb259IiwKICAibmFtZSI6ICJCcmlnYWRhIENvcmUiLAogICJkZXNjcmlwdGlvbiI6ICJQcml2YXRlIGNvb3BlcmF0aXZlIHNlcnZlciBzeXN0ZW1zIGZvciBCcmlnYWRhIE5vLiAxMy4iLAogICJhdXRob3JzIjogWyJCcmlnYWRhIDEzIl0sCiAgImNvbnRhY3QiOiB7CiAgICAic291cmNlcyI6ICJodHRwczovL2dpdGh1Yi5jb20vcmtsbWFuMjI4LXBuZy9QbGFnaW5fMSIKICB9LAogICJsaWNlbnNlIjogIk1JVCIsCiAgImVudmlyb25tZW50IjogInNlcnZlciIsCiAgImVudHJ5cG9pbnRzIjogewogICAgIm1haW4iOiBbCiAgICAgICJkZXYuYnJpZ2FkYTEzLmNvcmUuQnJpZ2FkYUNvcmUiCiAgICBdCiAgfSwKICAiZGVwZW5kcyI6IHsKICAgICJmYWJyaWNsb2FkZXIiOiAiPj0wLjE5LjMiLAogICAgIm1pbmVjcmFmdCI6ICIyNi4zLWFscGhhLjkiLAogICAgImphdmEiOiAiPj0yNSIsCiAgICAiZmFicmljLWFwaSI6ICI+PTAuMTU4LjEiCiAgfQp9Cg==' | base64 -d > /opt/brigada-core-src/src/main/resources/fabric.mod.json
cd /opt/brigada-core-src
./gradlew --no-daemon clean build
install -m 0644 build/libs/brigada-core-0.1.0.jar /opt/minecraft/server/mods/brigada-core-0.1.0.jar
systemctl start minecraft.service
sleep 15
systemctl --no-pager --full status minecraft.service || true
printf '\n=== RECENT LOG ===\n'
journalctl -u minecraft.service --since '-3 minutes' --no-pager -o cat | tail -n 260
