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
