#!/usr/bin/env bash
set -euo pipefail
binary=$(realpath "${1:?Pass a built native client}")
repo=$(cd "$(dirname "$0")/../.." && pwd)
fixture=$(mktemp -d -t astra-cpp23-smoke-XXXXXXXX)
cp "$repo/tests/minimap_hd/bootstrap.lua" "$fixture/init.lua"
cp "$repo/init.lua" "$fixture/production-init.lua"
cp "$repo/tests/minimap_hd/cyclopedia_test.lua" "$fixture/test.lua"
# PhysFS stat reports a symlink itself, not a resource-root directory. Use real
# directories; on the same filesystem this can reuse an existing staged pack
# through hard links, never a memory preload or a copy into the user profile.
resources=${ASTRA_SMOKE_RESOURCES:-$repo}
for resource in data modules mods layouts; do
  source="$repo/$resource"
  # A Web pack intentionally omits native-only developer modules. Only reuse
  # its data assets; production native module manifests must remain complete.
  if [[ "$resource" == data ]]; then source="$resources/data"; fi
  if [[ "$(stat -c %d "$source")" == "$(stat -c %d "$fixture")" ]]; then
    cp -al "$source" "$fixture/$resource"
  else
    cp -a "$source" "$fixture/$resource"
  fi
done
python3 -B "$repo/tests/minimap_hd/surface_fixture.py" "$repo/data/minimap_hd/source.json" "$fixture"
cd "$fixture"
set +e
xvfb-run -a env LIBGL_ALWAYS_SOFTWARE=1 ALSOFT_DRIVERS=null \
  UBSAN_OPTIONS="${UBSAN_OPTIONS:-halt_on_error=1:print_stacktrace=1}" \
  ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=1}" \
  timeout --kill-after=10s 180s "$binary" --test >stdout.log 2>stderr.log
status=$?
set -e
cat stdout.log
if (( status != 0 )); then cat stderr.log; printf 'Failed smoke artifacts: %s\n' "$fixture"; exit "$status"; fi
if ! grep -q '\[HD MINIMAP TEST\] PASS:' stdout.log; then cat stderr.log; exit 1; fi
frames=$(sed -n 's/^.*SURFACE FIXTURE: //p' stdout.log | tr -d '\r')
python3 -B "$repo/tests/minimap_hd/surface_pixels_test.py" "$frames"
printf 'Linux smoke artifacts: %s\n' "$fixture"
