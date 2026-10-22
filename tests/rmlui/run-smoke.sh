#!/usr/bin/env bash
set -euo pipefail
binary=$(realpath "${1:?Pass the RmlUi-enabled native client}")
repo=$(cd "$(dirname "$0")/../.." && pwd)
fixture=$(mktemp -d "${ASTRA_SMOKE_TEMP:-${TMPDIR:-/tmp}}/astra-rmlui-XXXXXXXX")
mkdir -p "$fixture/modules" "$fixture/data/fonts" "$fixture/data/styles" "$fixture/profile"
cp -a "$repo/modules/corelib" "$fixture/modules/"
cp -a "$repo/data/fonts/rml" "$fixture/data/fonts/"
cp -a "$repo/data/styles/rml" "$fixture/data/styles/"
cp "$repo/tests/rmlui/bootstrap.lua" "$fixture/init.lua"
cp "$repo/tests/rmlui/test.lua" "$fixture/test.lua"
cp "$repo/tests/rmlui/smoke.rml" "$fixture/smoke.rml"
cd "$fixture"
set +e
xvfb-run -a env HOME="$fixture/profile" XDG_CONFIG_HOME="$fixture/profile" LIBGL_ALWAYS_SOFTWARE=1 ALSOFT_DRIVERS=null \
  UBSAN_OPTIONS="${UBSAN_OPTIONS:-halt_on_error=1:print_stacktrace=1}" ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=1}" \
  timeout --kill-after=10s 60s "$binary" --test >stdout.log 2>stderr.log
status=$?
set -e
cat stdout.log
if (( status != 0 )); then cat stderr.log; printf 'Failed smoke artifacts: %s\n' "$fixture"; exit "$status"; fi
grep -q '\[RMLUI TEST\] PASS:' stdout.log
printf 'RmlUi smoke artifacts: %s\n' "$fixture"
