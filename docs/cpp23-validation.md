# C++23 validation evidence

Local validation: 2026-10-11. Base `96a0953`, branch
`feat/astra-cpp23-migration`. See [migration and reproduction](cpp23-migration.md)
and the complete classified [before](cpp23-inventory-before.tsv) /
[after](cpp23-inventory-after.tsv) inventories. The inventories include legacy
Android, C and vendor/documentation references; they are not a blind replacement
list. Compiler/dependency versions are recorded in the migration document.

## Actual builds and mode checks

Every row below describes execution, not just edited configuration. The command
counts include application/test C++ commands, exclude fetched vendor targets and
C files, and reflect unity builds where explicitly selected. Each audited C++
command has exactly one `c++23` / `c++23preview` switch.

| Target | Result | Actual mode / test evidence |
| --- | --- | --- |
| Windows `vc23` OpenGL x64 | Full build + real login/logout/reconnect + GPU tests passed | MSVC 19.51, `/std:c++23preview /Zc:__cplusplus`; 16 MSBuild command entries |
| Windows `vc23` DirectX x64 | Full build + real login/logout/reconnect + GPU tests passed | Same toolchain; 17 MSBuild command entries; ANGLE renderer |
| Windows `vc23` Debug x64 | Full build passed | Same toolchain; 17 MSBuild command entries |
| Windows CMake Release x64 | Fresh full build; CTest 3/3; 100-cycle production UI/GPU smoke passed | 167 C++ commands, no unity; sound enabled |
| Windows CMake Debug x64 | Fresh full build; CTest 3/3; 100-cycle production UI/GPU smoke passed | 23 C++ commands, unity explicitly selected for this local test; matching Debug CRT/dependencies |
| Win32 | Actual compiler/feature probe passed; full application not linked | MSVC x86 `__cplusplus=202302`, `_MSVC_LANG=202302`; ABI-matched x86 dependencies unavailable |
| Linux GCC Release | Full desktop build; CTest 3/3; real Xvfb/Mesa GPU smoke passed | GCC 13.3, `-std=c++23`, `__cplusplus=202100`; 167 commands |
| Linux Clang Debug | Full desktop build; CTest 3/3; instrumented production UI/GPU smoke and normal shutdown passed | Clang 18.1, `-std=c++23`, `__cplusplus=202302`; 24 commands; ASan + UBSan |
| Web Release | Full production bundle + three Node probes passed | Emscripten 6.0.8 / Clang 24, `-std=c++23`, `__cplusplus=202302`; 158 commands |
| Web Debug | Full production bundle + three Node probes passed | Same pinned SDK; 23 commands; existing SAFE_HEAP / ASSERTIONS / stack checks retained |
| Android | **Blocked** by an actual build attempt | MSB4019: legacy `Android.Default.props` import absent; SDK/NDK/ABI dependency bundle absent; no APK/device claim |

MSVC x64 probes report `__cplusplus=202302`, `_MSVC_LANG=202302`,
`_MSC_VER=1951`. Actual C++17 and C++20 negative compiler probes are rejected
by the source guard. Feature probes compile/run `std::to_underlying` and
`if consteval`; UTF-8 probes exercise Portuguese, Japanese and emoji paths.
The compatibility executable covers missing/existing TinyXML attributes and
sparse attribute copy/move/update/removal with multiple keys.

The final Windows CMake builds used new build directories, not reused objects.
This machine's Portuguese-only MSVC installation exposes an existing
CMake/Ninja `showIncludes` prefix-encoding issue: incremental header dependency
tracking was not trustworthy in the earlier local directories. No localized
hardcoded prefix, disabled dependency tracking, or compiler hack was added.
Clean final builds provide the evidence above; this tooling/environment issue
still needs attention before relying on incremental Ninja builds here.

Existing warnings remain visible (including Find-module package-name warnings,
legacy override/copy warnings and Debug linker diagnostics). This is not a
warning-free certification. Dependency pins, C Lua compilation modes, protocol
opcodes and persistent binary layouts were not changed.

## Regression execution

- Native OpenGL and DirectX each completed two authorized local TFS 8.60
  sessions: actual RSA/XTEA world login, character/health/position validation,
  HD/full map, Cyclopedia, classic toggle, logout and reconnect. The isolated
  runner did not move/fight/buy/issue commands or change/restart the server.
  Temporary credentials were removed in `finally`; they are not committed.
- Real Windows GPU tests exercised coherent LOD changes/full-map transitions
  (nine captured frames), classic fallback, Surface floor composition and alpha
  (eight captured frames), 100 production Cyclopedia lifecycles, virtualized
  markers, QuickLoot focus without a player profile, persistent flags and map
  filters. Export pixel tests and negative PNG/OTMM fixtures passed in OpenGL.
- Linux Release and Debug used production native module manifests and real
  Xvfb/Mesa software OpenGL, not a mocked renderer. Debug ran with
  `UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1` and
  `ASAN_OPTIONS=detect_leaks=1`; the final full smoke exited normally without
  ASan/UBSan reports. This is bounded execution, not a proof of no races/leaks
  in all gameplay paths. No sanitizer was disabled.
- The Windows CMake Debug stress smoke exceeded the original 60-second test
  budget; it completed with the opt-in 180-second bound. The default remains
  60 seconds. Instrumented Linux smoke similarly bounds the client, not Xvfb,
  so a timeout cannot destroy the X server while client threads are running.
- All three existing direct Windows C++ suites passed in the new mode:
  utility/UTF-8, HTTP/TLS/WSS/cancellation (including negative trust/hostname/
  expiry cases), and native splash/cursor lifecycle fixtures.
- All content-validation `Verify` / `Validate` / `Test` steps were executed
  locally under the actual workflow commands, including all six independent
  C++ compiles plus Lua syntax, module/asset manifests, GameBot startup,
  QuickLoot, Outfit, NPC trade, DAT/SPR selection/lifecycle, wheel, hotkeys,
  spell cooldown and memory-monitor regressions. These fixtures do not replace
  connected combat/store/NPC transactions.
- The pinned SDK security suite passed real WebSocket teardown, RSA/UUID/
  credentials, Fetch cancellation/stale callbacks/budgets, keyboard pthread
  focus/clipboard, logic timer cancellation, message-queue ASan/UBSan, cursor
  images and the C Lua parser's 6000 invalid-input cleanup cases. C remains
  `gnu99`; no C++ flag is assigned to it.
- Browser JavaScript tests: 71 passed, zero failed, one nginx integration test
  initially skipped; that exact integration test was then run with real nginx
  TLS/WSS/Origin/COOP/COEP and passed (one passed, zero skipped). This is evidence
  across two runs, not a claim that the first run had no skip.
- Build-policy unit tests: 3/3 passed, including old/missing/double flags,
  vendor/C exclusions and actual MSBuild `.tlog` syntax. Complete command
  databases and MSBuild logs were also audited, not just sample source flags.

## Real browser smoke

The final Release bundle was served on loopback with the production security
headers and opened in the actual in-app Chromium browser. The launcher reached
`Ready to Play`; clicking Play booted production Lua modules, DAT/SPR 8.60 and
the WebGL 2 client/login screen. Console error/warning inspection returned no
entries. Screenshots: `build/cpp23/web-release.jpg` (diagnostics) and
`build/cpp23/web-release-ui.jpg` (client UI).

The observed warm-cache run reported `cacheHit=true`, zero asset download bytes,
764,797,660 cache-read bytes, 729.37 MiB preloaded package and 9,733 ms from Play
to first frame. At the recorded idle-login-screen sample: 60 FPS, average frame
16.67 ms, p95 18.78 ms, p99 18.83 ms, no frame above 33.3 ms in that rolling
window; WASM capacity 768 MiB and malloc allocation 173.42 MiB. WASM capacity
is not live allocation or total browser RAM. This is an observed sample, not
a connected-gameplay FPS baseline or an assertion that cold boot is equally fast.

The bundle contains 5,037 allowlisted files after restoring the missing
`core/mapmarkers.lua` dependency. SDK/Web Debug probes passed separately;
an actual browser Debug session and Web-to-TFS login were not executed.

## Matched C++17 / C++23 measurements

Three sequential repetitions on the same Windows machine / Intel UHD OpenGL
backend, same MSVC 19.51 toolchain, Release configuration and dependencies.
Baseline executable was compiled from `96a0953` in C++17 before applying the
migration. Both executables used the same production Lua/resources, isolated
test profile and 100-cycle Cyclopedia fixture with 20,200 marker data records.
Compilers were idle and the Web client was stopped during measurement.
Baseline ran first in each pair; OS/cache/order variation is a limitation.

`tests/cpp23/Benchmark.ps1` retains binary hashes, exit codes, elapsed time,
sampled private peak (50 ms), process peak working set and artifact paths.
Each fixture also writes 100 individual open/close/marker callback timings
to `timings.json` using the production millisecond clock. All six runs passed
the lifecycle assertions and GPU comparisons.

| Run | Mode | Total seconds | Peak private MiB (sampled) | Peak working set MiB | Open median / p95 ms | Marker median / p95 ms |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | C++17 | 11.804 | 683.66 | 738.78 | 17 / 18 | 1 / 2 |
| 1 | C++23 | 11.688 | 678.37 | 731.18 | 17 / 18 | 1 / 2 |
| 2 | C++17 | 11.829 | 668.71 | 727.02 | 17 / 18 | 1 / 2 |
| 2 | C++23 | 11.915 | 681.50 | 735.48 | 17 / 18 | 1 / 2 |
| 3 | C++17 | 11.971 | 677.50 | 731.85 | 16 / 18 | 1 / 2 |
| 3 | C++23 | 11.689 | 687.80 | 740.57 | 17 / 18 | 1 / 2 |

Close median/p95 were 0/0 ms at the clock's resolution in both modes; isolated
outliers were up to 33 ms. Open maxima ranged 51–83 ms in C++17 and 50–83 ms
in C++23. Aggregate medians: private 677.50 → 681.50 MiB (+4 MiB), working set
731.85 → 735.48 MiB; total 11.829 → 11.689 seconds. Ranges overlap: there is
no meaningful regression demonstrated by this bounded fixture, and no basis
for attributing a performance improvement to the language standard.

This is not a matched connected-gameplay FPS benchmark or a many-item world
memory test. Natural alignment fixes can increase runtime object padding;
the sparse storage is preserved but zero RAM impact is not promised. Full
combat/store/outfit workloads and long-session memory trends need further
measurement. C++23 alone is not advertised as an optimization.

Baseline SHA-256:
`9C1EC02943D2618FA870389FC8D913C82FE3CDA2143440E70DFAC99803498BC5`.
C++23 OpenGL SHA-256:
`1BC7394096CDA169DDDE366F1B42715AC5CAC6F5A5DE7E30EA1DF2B620F65F8A`.

## Logs and remaining limits

Local full logs / command databases / screenshots are retained under ignored
`build/cpp23/` and the separate WSL tool/build directories. They contain large
compiler diagnostics and generated artifacts and are not source commits.
Relevant local logs include:

- `gl.log`, `dx.log`, `debug.log`, `baseline-gl.log`, `x86-probe.log`,
  `actual-command-audit.log`, `rejected-cpp17.log`, `rejected-cpp20.log`.
- `cmake-final-{release,debug}-{config,build,tests,smoke}.log`.
- `linux-{release,debug}-build.log`, `linux-debug-smoke.log`,
  `linux-release-final-smoke.log`, `wasm-{release,debug}-build.log`.
- `live-{gl,dx}.log`, `{gl,dx}-{cyclopedia,glitches}.log`,
  `gl-export.log`, `gl-negative-inputs.log`.
- `windows-units.log`, `content-workflow.log`, `security-tests.log`,
  `browser-js-tests.log`, `nginx-tests.log`, `benchmark/run{1,2,3}/`,
  `android-blocker.log`.

Remote GitHub CI is separate from local execution. Workflows upload compiler,
configure/build/CTest logs and command databases for seven days. A green local
build is not a claim that the remote pinned-vcpkg Linux job has already passed.
No automatic merge is performed.

Android, macOS, full Win32 linking, TSan/race certification, long connected
gameplay, and an actual Web-to-TFS account session through a WSS bridge remain
unverified. The production Web asset allowlist does not include the optional
satellite PNG pack; native HD tests do not imply browser HD-pack certification.
