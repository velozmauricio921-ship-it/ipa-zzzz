#!/bin/bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
OUT=$(mktemp -d "${TMPDIR:-/tmp}/baij-scoped-file-tests.XXXXXX")
trap 'rm -rf -- "$OUT"' EXIT

swiftc \
    "$ROOT/ThreeOneOSFive/helpers/ScopedFileAccessProvider.swift" \
    "$ROOT/ThreeOneOSFive/helpers/FileReplacementService.swift" \
    "$ROOT/tests/ScopedFileAccessProviderTests.swift" \
    -o "$OUT/ScopedFileAccessProviderTests"
"$OUT/ScopedFileAccessProviderTests"