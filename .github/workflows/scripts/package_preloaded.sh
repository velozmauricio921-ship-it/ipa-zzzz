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

# Remove any exposed Preloaded folder inside the app bundle to avoid leaking patches
if [ -d "$APP_PATH/Preloaded" ]; then
  rm -rf "$APP_PATH/Preloaded"
fi

echo "package_preloaded: done"
exit 0
