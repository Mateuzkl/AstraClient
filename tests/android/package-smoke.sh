#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
if [[ -e "$repo/android/otclientv8/assets/data.zip" ]]; then
    printf 'Refusing to overwrite the existing Android asset pack.\n' >&2
    exit 1
fi
stage=$(mktemp -d "${TMPDIR:-/tmp}/astra-android-assets-XXXXXXXX")
trap 'rm -f "$stage/data.zip"; rmdir "$stage" 2>/dev/null || true' EXIT
# zip takes an explicit list, never personal mods, accounts or arbitrary local files.
cd "$repo"
git ls-files modules/corelib | zip -q "$stage/data.zip" -@
zip -q -j "$stage/data.zip" tests/android/init.lua
cp "$stage/data.zip" android/otclientv8/assets/data.zip
