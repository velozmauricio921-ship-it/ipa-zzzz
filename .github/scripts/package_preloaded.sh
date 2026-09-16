#!/usr/bin/env bash
set -euo pipefail

# Usage: package_preloaded.sh <repo_preloaded_dir> <app_path>
REPO_PRELOADED_DIR="$1"
APP_PATH="$2"

echo "package_preloaded: repo dir=$REPO_PRELOADED_DIR, app path=$APP_PATH"
if [ ! -d "$REPO_PRELOADED_DIR" ]; then
  echo "package_preloaded: no Preloaded dir found in repo"
  exit 0
fi

TMPDIR=$(mktemp -d)
echo "package_preloaded: creating archive in $TMPDIR"

# Create archive with files at root (no top-level Preloaded/ folder inside archive)
(cd "$REPO_PRELOADED_DIR" && zip -r "$TMPDIR/Preloaded.tendies" . -x "*.DS_Store" >/dev/null)

if [ ! -f "$TMPDIR/Preloaded.tendies" ]; then
  echo "package_preloaded: failed to create archive"
  exit 1
fi

echo "package_preloaded: embedding Preloaded.tendies into app bundle"
mv "$TMPDIR/Preloaded.tendies" "$APP_PATH/Preloaded.tendies"

# Encrypt the archive with a fixed AES-256-CBC key (embedded in app). This is option B (key
# embedded/obfuscated in the binary). The key below must match the one in the Swift code.
HEXKEY="d4b2f3a9c6e7f8a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a"
if command -v openssl >/dev/null 2>&1; then
  echo "package_preloaded: encrypting archive with embedded key"
  HEXIV=$(openssl rand -hex 16)
  # Create encrypted file at TMPDIR/Preloaded.tendies.aes
  openssl enc -aes-256-cbc -K "$HEXKEY" -iv "$HEXIV" -in "$APP_PATH/Preloaded.tendies" -out "$TMPDIR/Preloaded.tendies.aes"
  if [ -f "$TMPDIR/Preloaded.tendies.aes" ]; then
    # Prepend raw IV (binary) to the ciphertext for easy extraction in Swift
    printf "%b" "$(echo $HEXIV | sed 's/\(..\)/\\x\1/g')" > "$TMPDIR/Preloaded.tendies.aes.prefixed"
    cat "$TMPDIR/Preloaded.tendies.aes" >> "$TMPDIR/Preloaded.tendies.aes.prefixed"
    mv "$TMPDIR/Preloaded.tendies.aes.prefixed" "$APP_PATH/Preloaded.tendies.aes"
    rm -f "$TMPDIR/Preloaded.tendies.aes" || true
    # Remove plaintext archive to avoid leaving it in the bundle
    rm -f "$APP_PATH/Preloaded.tendies" || true
    echo "package_preloaded: encrypted archive written as Preloaded.tendies.aes"
  else
    echo "package_preloaded: encryption failed, keeping plaintext archive"
  fi
else
  echo "package_preloaded: openssl not found, skipping encryption"
fi

echo "package_preloaded: listing top-level app bundle contents before cleanup"
ls -la "$APP_PATH" || true

# Remove any exposed Preloaded directories inside the app bundle (any depth)
echo "package_preloaded: searching for Preloaded directories inside app bundle"
FOUND_PRELOADS=$(find "$APP_PATH" -type d -name "Preloaded" 2>/dev/null || true)
if [ -n "$FOUND_PRELOADS" ]; then
  echo "package_preloaded: found Preloaded dirs:"
  echo "$FOUND_PRELOADS"
  # Remove all found Preloaded directories
  find "$APP_PATH" -type d -name "Preloaded" -prune -exec rm -rf {} + || true
  echo "package_preloaded: removed Preloaded directories"
else
  echo "package_preloaded: no Preloaded directories found inside app bundle"
fi

echo "package_preloaded: listing top-level app bundle contents after cleanup"
ls -la "$APP_PATH" || true

echo "package_preloaded: done"
exit 0
