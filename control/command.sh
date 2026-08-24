#!/usr/bin/env bash
set -Eeuo pipefail

FILE_ID="1Jq-I46uJnETDpxUWXxw9qfDDb3OLJxf4"
DRIVE_URL="https://drive.google.com/file/d/${FILE_ID}/view?usp=drivesdk"
DEST_DIR="/root/uploads"
DEST="${DEST_DIR}/Писькострелковая_бригада_13.zip"
PART="${DEST}.part"
EXPECTED_SIZE="1470937885"
GDOWN="/opt/gdown-venv/bin/gdown"

mkdir -p "$DEST_DIR"

printf 'target=%s\n' "$DEST"
printf 'expected_bytes=%s\n' "$EXPECTED_SIZE"
df -h "$DEST_DIR"

if [[ -f "$DEST" ]] && [[ "$(stat -c '%s' "$DEST")" == "$EXPECTED_SIZE" ]]; then
  echo "File already present with expected size; skipping download."
else
  if [[ ! -x "$GDOWN" ]]; then
    echo "Installing isolated Google Drive downloader..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq python3-venv unzip ca-certificates
    rm -rf /opt/gdown-venv
    python3 -m venv /opt/gdown-venv
    /opt/gdown-venv/bin/pip install --no-cache-dir --quiet gdown
  fi

  echo "Downloading from Google Drive..."
  "$GDOWN" --fuzzy --continue "$DRIVE_URL" -O "$PART"

  ACTUAL_SIZE="$(stat -c '%s' "$PART")"
  printf 'downloaded_bytes=%s\n' "$ACTUAL_SIZE"

  if [[ "$ACTUAL_SIZE" != "$EXPECTED_SIZE" ]]; then
    echo "ERROR: downloaded size does not match Drive metadata." >&2
    exit 2
  fi

  mv -f "$PART" "$DEST"
fi

echo "Calculating SHA-256..."
sha256sum "$DEST"

echo "Testing ZIP integrity..."
unzip -tq "$DEST"

stat -c 'path=%n%nbytes=%s%nmodified=%y' "$DEST"
echo "DRIVE_UPLOAD_TO_HOST_OK"
