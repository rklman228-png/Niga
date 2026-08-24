#!/usr/bin/env bash
set -Eeuo pipefail

ZIP="/root/uploads/Писькострелковая_бригада_13.zip"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Archive root entries:"
unzip -Z1 "$ZIP" | sed -n '1,80p'

LEVEL_PATH="$(unzip -Z1 "$ZIP" | grep -E '(^|/)level\.dat$' | head -n 1 || true)"
if [[ -z "$LEVEL_PATH" ]]; then
  echo "ERROR: level.dat not found in archive" >&2
  exit 2
fi

printf 'level_dat_archive_path=%s\n' "$LEVEL_PATH"
unzip -p "$ZIP" "$LEVEL_PATH" > "$TMP_DIR/level.dat"

NBT_PY="/opt/gdown-venv/bin/python"
NBT_PIP="/opt/gdown-venv/bin/pip"
"$NBT_PIP" install --no-cache-dir --quiet nbtlib

"$NBT_PY" - "$TMP_DIR/level.dat" <<'PY'
import sys
import nbtlib

path = sys.argv[1]
root = nbtlib.load(path)
data = root["Data"]
version = data.get("Version", {})

print(f"LevelName={data.get('LevelName')}")
print(f"DataVersion={data.get('DataVersion')}")
print(f"VersionName={version.get('Name')}")
print(f"VersionId={version.get('Id')}")
print(f"VersionSnapshot={version.get('Snapshot')}")
print(f"LastPlayed={data.get('LastPlayed')}")
PY

echo "WORLD_INSPECTION_OK"
