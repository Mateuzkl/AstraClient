# Tests and reproducibility

All tests use an isolated client profile, no login, and hidden windows. The GPU suites draw the production minimap queue into actual offscreen framebuffers; they do not use a mock renderer. UI/controller assertions instantiate the production Cyclopedia widgets. They do not prove visual parity of a connected gameplay session.

## Passed on both desktop backends

- OpenGL x64: Intel UHD Graphics, OpenGL 4.6 driver 27.20.100.9664.
- DirectX x64: ANGLE/D3D11, Intel UHD Graphics, ANGLE 2.1.5414.
- MSVC builds: 0 warnings/errors. Standalone `/Zs`, without unity/PCH, also passed for `luafunctions_client.cpp`, `minimap.cpp`, and `uiminimap.cpp`.
- New `-Cyclopedia` suite: eight GPU captures validate floors 0/6/7/8, alpha 0/50/100, selected-floor opacity, transparent spaces, underground classic fallback and the shared 32-texture/4-job bounds.
- Production Map controller: 100 close/reopen cycles with 20,000 off-screen data markers plus 200 dense visible markers. At most 128 marker widgets and 32 label widgets, cancelled refresh events, no orphan panel parents, exactly one added/removed automap handler per live map, and zero leaked Surface subscribers.
- HUD HD independence, floor/radio switching, zoom restore, filters/Show All, label culling/declutter, flag deduplication/add/remove/persistence, flag editor cancellation without rebuilding the map, and repeated Map redirect while already open.
- Actual Items panel/focus path: unavailable quickloot profile disables the controls without nil-global errors. Whitelist/blacklist UI selection is exercised with controlled API responses; a separate contract test loads the real sandbox script to validate its profile states.
- Missing HD pack disables Surface but leaves Map usable.
- House previews keep a single selected surface floor; legacy fullMinimap names remain intact. Automatic floor transitions restore each view's saved zoom. Positional marker exclusions and optional-label parsing failures have separate regressions.
- Existing PR204 suites: native bindings/settings, persistent satellite/OTMM merge and restart, native OTB/OTBM PNG export pixels, negative PNG/ENC3/OTMM inputs and lifecycle budgets, and real-GPU delayed-decode/full-map/zoom/floor glitch frames.
- LuaJIT options, marker index, quickloot contract; Python pyramid and OTBM city-label exporter tests.

## Commands (from Astra repository)

```powershell
$gl = 'build/hd-minimap/bin/otclient_gl_x64.exe'
$dx = 'build/hd-minimap-dx/bin/otclient_dx_x64.exe'
foreach ($binary in @($gl, $dx)) {
  tests/minimap_hd/Run-Smoke.ps1 -BinaryPath $binary -Cyclopedia
  tests/minimap_hd/Run-Smoke.ps1 -BinaryPath $binary
  tests/minimap_hd/Run-Smoke.ps1 -BinaryPath $binary -Satellite
  tests/minimap_hd/Run-Smoke.ps1 -BinaryPath $binary -Export
  tests/minimap_hd/Run-Smoke.ps1 -BinaryPath $binary -Audit
  tests/minimap_hd/Run-Smoke.ps1 -BinaryPath $binary -Glitches
}
tests/minimap_hd/Check-TranslationUnits.ps1
$lua = 'vcpkg_installed/x64-windows-static/x64-windows-static/tools/luajit/luajit.exe'
& $lua tests/minimap_hd/options_test.lua
& $lua tests/minimap_hd/marker_index_test.lua
& $lua tests/minimap_hd/quickloot_contract_test.lua
python -B tests/minimap_hd/pyramid_test.py
python -B tests/minimap_hd/city_labels_test.py
```

Do not run smoke clients concurrently: they share a deliberately isolated test profile. `-Audit` intentionally logs only allow-listed negative-input errors. The other suites passed without unexpected errors.

Each run prints its artifact directory. Surface `frames.json`, `timings.json`, and eight PNG captures live below `%APPDATA%/AstraClient/astra_hd_minimap_smoke/surface-*`. Glitch captures use `glitch-*`. The scripts generate synthetic test assets themselves; private server maps/PNG packs are not committed.

## Remaining manual checks / limitations

Reopen the installed executable, log in, open Map repeatedly, pan at wide zoom, change floors/slider, and compare FPS/ping with the monitor closed, then open it briefly for callback statistics. Actual network bytes, connected gameplay FPS, and total process/GPU memory after hours of gameplay were not benchmarked here. A ping spike can be local dispatcher delay; these tests do not exclude an independent network/server problem.

Cold UI/driver work can still produce isolated opening spikes; see BENCHMARK.md. The optional memory-monitor UI also has its own initial allocation/update cost; its 12 ms SlowLua warning is not a protocol failure. This change does not hide warnings or alter the monitor's threshold.

Linux/Web builds and mobile drivers were not run locally. No modern region-discovery/boost-donation server features were added. The TFS checkout remained on its original branch with its local changes intact.
