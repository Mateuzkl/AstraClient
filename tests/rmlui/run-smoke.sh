#!/usr/bin/env bash
set -euo pipefail
binary=$(realpath "${1:?Pass the RmlUi-enabled native client}")
scenario=${2:-core}
case "$scenario" in core|skilltree|otui) ;; *) printf 'Unknown RmlUi scenario: %s\n' "$scenario" >&2; exit 2;; esac
repo=$(cd "$(dirname "$0")/../.." && pwd)
fixture=$(mktemp -d "${ASTRA_SMOKE_TEMP:-${TMPDIR:-/tmp}}/astra-rmlui-XXXXXXXX")
mkdir -p "$fixture/modules" "$fixture/data/fonts" "$fixture/data/styles" "$fixture/profile"
mkdir -p "$fixture/data/images/ui"
cp "$repo/data/images/ui/background.png" "$fixture/data/images/ui/"
cp "$repo/tests/rendering/scene.lua" "$fixture/render-scene.lua"
cp -a "$repo/modules/corelib" "$fixture/modules/"
cp -a "$repo/data/fonts/rml" "$fixture/data/fonts/"
cp -a "$repo/data/styles/rml" "$fixture/data/styles/"
cp "$repo/tests/rmlui/bootstrap.lua" "$fixture/init.lua"
cp "$repo/tests/rmlui/test.lua" "$fixture/test.lua"
cp "$repo/tests/rmlui/smoke.rml" "$fixture/smoke.rml"
if [[ "$scenario" == skilltree ]]; then
  cp -a "$repo/modules/game_rmlskilltree" "$fixture/modules/"
  mkdir -p "$fixture/data/images/game/spells" "$fixture/data/images/game/tutorial"
  cp "$repo/data/images/game/spells/spell-icons-32x32.png" "$fixture/data/images/game/spells/"
  cp "$repo/data/images/game/tutorial/backdrop_knight.png" "$fixture/data/images/game/tutorial/"
  cp "$repo/modules/gamelib/spells.lua" "$fixture/spell-catalog.lua"
  cp "$repo/tests/rmlui/skilltree.lua" "$fixture/test.lua"
fi
if [[ "$scenario" == otui ]]; then
  cp "$repo/tests/rmlui/otui.lua" "$fixture/test.lua"
fi
cd "$fixture"
set +e
xvfb-run -a -s "${ASTRA_SMOKE_SCREEN:--screen 0 1920x1080x24}" env HOME="$fixture/profile" XDG_CONFIG_HOME="$fixture/profile" LIBGL_ALWAYS_SOFTWARE=1 ALSOFT_DRIVERS=null \
  UBSAN_OPTIONS="${UBSAN_OPTIONS:-halt_on_error=1:print_stacktrace=1}" ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=1}" \
  timeout --kill-after=10s 60s "$binary" --test >stdout.log 2>stderr.log
status=$?
set -e
cat stdout.log
if (( status != 0 )); then cat stderr.log; printf 'Failed smoke artifacts: %s\n' "$fixture"; exit "$status"; fi
grep -q '\[RMLUI TEST\] PASS:' stdout.log
if grep -qE 'ERROR:|FreeType error' stdout.log stderr.log; then
  printf 'RmlUi logged an error. Artifacts: %s\n' "$fixture"; exit 1
fi
printf 'RmlUi smoke artifacts: %s\n' "$fixture"
