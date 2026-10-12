# C++23 migration and validation

Base: `main` at `96a0953`. Work branch: `feat/astra-cpp23-migration`.
No merge into `main`, server changes, protocol changes, or installed executable
replacement is part of this migration. Android is explicitly **blocked**.

## Build policy

`cmake/AstraCxx23.cmake` owns the dialect: C++23, required, extensions off,
with a real configure-time compiler-mode check. The application header guard
rejects C++17/20 too. `tools/check_cpp23.py` audits owned build routes and the
actual `compile_commands.json` / MSBuild `.tlog` commands: exactly one C++23
switch is required. Vendor and C translation units are not relabeled as C++23.

MSVC 19.43+ uses `/std:c++23preview`. The recognized MSBuild enum is `stdcpp23`,
confirmed against the installed compiler's `cl.xml`; all six configurations
were changed. Inspected CMake versions map dialect 23 to `c++latest`, so the
MSVC dialect mapping is replaced before configuration tests. No duplicate
standard switch, global `char8_t` disable, or fallback to C++20 is used.

`__cplusplus` is not assumed to be exactly 202302 on every implementation:
GCC 13 reports 202100; older MSVC previews report 202004 through `_MSVC_LANG`.
The probes also compile `std::to_underlying` and `if consteval`.

References: [MSVC language modes](https://learn.microsoft.com/en-us/cpp/build/reference/std-specify-language-standard-version?view=msvc-170),
[CMake required standard](https://cmake.org/cmake/help/latest/prop_tgt/CXX_STANDARD_REQUIRED.html).

## Inventory

Complete line-numbered snapshots are saved in
[`cpp23-inventory-before.tsv`](cpp23-inventory-before.tsv) and
[`cpp23-inventory-after.tsv`](cpp23-inventory-after.tsv). Regenerate classified
inventories without changing the checkout:

```sh
python3 -B tools/check_cpp23.py --inventory --ref 96a0953
python3 -B tools/check_cpp23.py --inventory
python3 -B tools/check_cpp23.py
python3 -B tests/cpp23/guard_test.py
```

| Category / base location | Before | After |
| --- | --- | --- |
| Build: `CMakeLists.txt:10`, `src/framework/CMakeLists.txt:180` | Two conflicting C++17 definitions | One C++23 policy, required / no extensions |
| Build: `vc23/otclient.vcxproj:190,232,273,320,366,422` | Six `stdcpp17` settings | Six recognized `stdcpp23` settings, `/Zc:__cplusplus` |
| Test: `build-vcpkg.yml:144,148,163` | Three direct C++17 commands | Three MSVC C++23 preview commands + forced guard |
| Test: `build-wasm.yml:145,156,160,164,174,184,195,206,222` | Nine direct C++17 commands | Nine C++23 commands + forced guard |
| Test: `content-validation.yml:150,157,167,184,187,199` | Six direct C++17 commands | Six C++23 commands + forced guard |
| Test: `browser/tests/run-security.sh` | Six direct commands (including a loop) | C++23; C Lua parser mode unchanged |
| Test: `tests/minimap_hd/Check-TranslationUnits.ps1:20` | C++17 | C++23 preview, actual standalone TUs |
| Blocked: `android/otclientv8_lib/otclientv8_lib.vcxproj` | `Clang_5_0`, three `c++1z` entries | Retained legacy, explicitly unsupported |
| Vendor / C | Own macros / C modes | No cosmetic dialect replacement |
| Documentation | Obsolete Android build instructions | Honest blocked status and requirements |

The inventory tool classifies documentation, owned build/test files, the
Android exception and the vendored thread-pool header separately. C flags
such as Lua 5.1's `-std=gnu99` remain visible in the inventory and unchanged.

## Restricted source fixes

- UTF-8 `std::filesystem::path::u8string()` now returns `char8_t` code units.
  `stdext::path_to_utf8` copies those bytes for libzip instead of using the
  Windows locale or an unsafe pointer cast. Portuguese, Japanese and emoji
  path tests cover the production helper.
- Missing TinyXML string attributes return an empty string instead of
  constructing one from a null pointer. The supplied numeric value remains
  untouched; an existing numeric attribute is tested too.
- Unreachable FileStream string returns use `{}` rather than a null pointer.
- `UnjustifiedPoints::operator==` is const, as required by rewritten equality.
- Enum / floating-point arithmetic has explicit numeric operands, retaining
  the original values and truncation behavior.
- The existing Windows utility UTF-8 fixture now explicitly copies `u8`
  bytes into strings rather than relying on pre-C++20 literal types.
- Full UBSan execution reproduced misaligned STL construction in `Item`;
  an independent regression also reproduced misaligned pointer references
  in sparse attributes. Runtime `Item`, `packed_any` and `packed_storage`
  retain natural alignment now. Sparse storage and public APIs are preserved.
  These objects are not binary wire/file records; OTMM's packed tile record
  and protocol serialization remain unchanged. Padding may increase their
  in-memory size; measurements must include this fix.
- A complete Web boot exposed a missing `core/mapmarkers.lua` dependency in
  the reviewed production asset list. It is now explicitly bundled (5037
  files), rather than weakening the bundle allowlist.
- Lua 5.1's C target opts out of optional application unity builds: internal
  `getline` macros must not leak across vendor translation units. Lua syntax,
  C language mode, and dependency versions are unchanged.

## Toolchain / dependencies

| Route | Actual local toolchain |
| --- | --- |
| Windows | VS 18 Community, MSVC 19.51.36260, toolset 14.51.36231 / v145; CMake 4.3.1-msvc1, Ninja |
| Linux Release | Ubuntu 24.04 WSL, GCC 13.3, CMake 3.28.3 |
| Linux sanitizer Debug | Clang 18.1.3, libstdc++ 13; ASan + UBSan |
| Web | Unchanged pinned Emscripten 6.0.8, Clang 24, SDK Node 24.19 |
| Android | No SDK/NDK / ABI dependency bundle; legacy VS Android imports missing |

The repository dependency manifest and its baseline are not upgraded.
Windows uses the existing `x64-windows-static` vcpkg dependencies. Local Linux
uses distro development libraries and a separately built curl 8.21.0 (the
distro's older curl does not satisfy the existing application requirement).
The Linux CI job uses pinned vcpkg instead; local distro builds are not claimed
to be execution of that remote vcpkg job.

## Reproduction

Native CMake, in an initialized compiler environment with matching dependencies:

```sh
cmake -S . -B build-release -G Ninja -DCMAKE_BUILD_TYPE=Release -DFRAMEWORK_SOUND=ON
cmake --build build-release --parallel 2
ctest --test-dir build-release --output-on-failure
python3 -B tools/check_cpp23.py --compile-commands build-release/compile_commands.json
```

For vcpkg add `-DCMAKE_TOOLCHAIN_FILE=<vcpkg>/scripts/buildsystems/vcpkg.cmake`
and the platform triplet. Debug must use ABI-matched debug libraries; legacy
LuaJIT/libzip/audio find modules may need explicit library paths when reusing
a preinstalled static dependency tree. Do not mix release and debug CRTs.

Windows direct builds (all selected configurations require C++23):

```powershell
MSBuild vc23/otclient.vcxproj /t:Build /p:Configuration=OpenGL /p:Platform=x64
MSBuild vc23/otclient.vcxproj /t:Build /p:Configuration=DirectX /p:Platform=x64
MSBuild vc23/otclient.vcxproj /t:Build /p:Configuration=Debug /p:Platform=x64
python -B tools/check_cpp23.py --tlog <IntDir>/otclient.tlog/CL.command.1.tlog
tests/cpp23/Run-WindowsUnits.ps1 -VcpkgTriplet <installed-triplet>
```

Linux sanitizers:

```sh
cmake -S . -B build-sanitized -G Ninja -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
  -DCMAKE_CXX_FLAGS='-fsanitize=address,undefined -fno-omit-frame-pointer'
cmake --build build-sanitized --parallel 2
UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1 ASAN_OPTIONS=detect_leaks=1 \
  ctest --test-dir build-sanitized --output-on-failure
bash tests/cpp23/run-linux-smoke.sh build-sanitized/AstraClient
```

The GPU smoke uses an isolated profile, production modules, real Xvfb/Mesa,
100 Cyclopedia lifecycle cycles, contrasting classic/HD fixtures and pixel
comparisons. The bounded timeout applies to the client, not the X server:
killing Xvfb during an instrumented run produces misleading exit-handler
reports while application threads are still alive. No sanitizer is disabled.

Web:

```sh
source <emsdk>/emsdk_env.sh
bash browser/build-wasm.sh Release
python3 -B tools/check_cpp23.py --compile-commands build-wasm-release/compile_commands.json
bash browser/tests/run-security.sh
node --test browser/tests/*.test.cjs
```

Debug uses the existing `ASSERTIONS=2`, `SAFE_HEAP=1` and stack checks. Open a
served production bundle with COOP/COEP and WebGL 2; test actual launcher,
Lua/DAT/SPR startup, first GPU frame, persistent cache and console errors, not
only Node compilation. The native account test is opt-in:
`Run-LiveSession.ps1` requires user-supplied credentials, does not embed them,
uses a separate profile and removes its temporary credential file in `finally`.
It does not move, fight, issue commands, buy anything or restart the server.

## Focused ownership / lifetime review

| Area | Reviewed behavior / bounded evidence |
| --- | --- |
| Creature / Thing / Tile / Map | Existing timed-event cancellation, weak creature callbacks, map cleanup and shared tile/item ownership retained; instrumented real UI startup and attribute copy/move tests exercise runtime objects |
| UIWidget / Lua userdata | `destroy` retains self during callbacks, breaks parent/child/layout links and releases Lua fields; 100 production Cyclopedia open/close cycles check stable widget count |
| Dispatcher / shutdown | Existing bounded drain and callback cancellation release Lua references before VM shutdown; no new raw `this` callbacks introduced |
| Native sockets / Protocol | Asio handlers retain Connection; Protocol callbacks use weak ownership; cancel/close and completion draining retained; TLS/WSS/cancel regressions and actual login/logout/reconnect exercise the paths |
| HTTP worker | Global owner stops accepting work, cancels sessions and joins worker before teardown; Web stale callbacks / cancellation tests retained |
| HD decode / render / resources | Worker captures only path and cancellation token, not Map/GL owner; textures remain renderer-owned; actual GPU LOD/full-map/classic transition pixel tests |

No blanket conversion of pointers, API renaming or claim that all lifetime
bugs are eliminated. UI parent cycles still rely on explicit destroy; unusual
module unload paths, multithread races and long gameplay sessions need further
soak testing. TSan, macOS, ARM64/Android and full Win32 application linking are
not certified by this work. The actual Win32 C++23 compiler/feature probe is
separate from a complete Win32 client build.

## Android blocker

An actual `MSBuild android/otclientv8/otclientv8.androidproj` attempt fails with
**MSB4019**: `Microsoft/MDD/Android/V150/Android.Default.props` is absent.
Known SDK/NDK paths and `C:/android` are absent too. The retained legacy project
selects `Clang_5_0` / `c++1z` and old Android API/Ant infrastructure; it cannot
be certified by replacing a dialect string.

A follow-up must select/test a modern NDK/libc++, implement real Gradle/CMake
ARM64 packaging, rebuild all ABI-specific native dependencies, produce an APK
and test it on a device/emulator. Until that evidence exists, the source guard
must reject legacy C++ modes and CI/README must not advertise Android success.

## Validation evidence and performance

Final results, command audits and the matched C++17/C++23 benchmark are recorded
in `cpp23-validation.md`. Full local logs are retained under ignored
`build/cpp23/`; CI archives compiler/configure/build/CTest diagnostics. Tests
are regression evidence for exercised paths, not a promise of universal
feature coverage or automatic FPS/memory improvement from C++23.
