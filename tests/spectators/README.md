# Mehah spectator port: focused validation

## Pinned references

- Astra base: `6a84fd4ec76853fd71d07e7c1cd2244bd47c4e9f` (main).
- Latest verified upstream: `53c3878a1c5119c78e148adb32def53fea3c53f2`,
  committed 2026-10-08, verified again on 2026-10-12.
- Original optimization: `294606e47c962dfaf72ca70452a9fdd7a5201f14`.
- Sources: upstream `src/client/map.cpp`, `src/client/tile.cpp`,
  `src/client/tile.h` in https://github.com/opentibiabr/otclient.
- Branch: `perf/mehah-spectator-retrieval`; no direct main push or merge.

## Patch and necessary adaptations

`map.cpp` uses upstream reservations, call-local ID deduplication, Z/Y/X bounds
and traversal, direct reverse-stack append, and first-seen/null cleanup.
`tile.cpp` maintains the creature span on insertion and every successful stack
removal; `clean()` already removes through that same path. Effect/walking lists
remain separate. All other tile mutation sites were checked.

`tile.h` adds the two span indexes, a constant-time `hasCreatures()` and
`appendSpectators()`. Necessary differences from upstream:

1. Astra has no upstream `m_thingTypeFlag` system. Availability uses the
   first-index sentinel instead; no rendering/flag architecture is replaced.
2. Indexes use `int`, matching Astra's existing stack-position API without
   narrowing to upstream `int16_t`. Reverse-iterator bounds are equivalent.
3. Removal rebuilds only the creature span instead of upstream's broader flag
   recalculation. Insertion shifts/extends the span before any stack trimming.
4. Existing scanning `getCreatures()` and `hasCreature()` implementations stay
   untouched, preserving their forward order and existing Lua/caller behavior.
5. Vertical margins retain Astra's signed `int` type. A query center outside
   the map's aware floors can produce negative differences; upstream's
   `uint8_t` margins wrap those differences and scan unintended floors.

Deduplication by ID is intentional: distinct objects sharing an ID and a single
object referenced by multiple tiles produce only the first traversal occurrence.
There is no persistent spectator cache. `getSpectatorsByPattern`, Battle List,
bot scripts, protocols, TFS, Quick Loot and drawing implementations are untouched.

`CMakeLists.txt` adds only an opt-in native test executable and CTest entry.
The MSBuild test import replaces the entry point without changing production
project files. Tests include the real `map.cpp` so its anonymous null/dedup
helper can be exercised without a new public API; the separate map TU is removed
only from the test executable. Fixtures retain protected/virtual visibility.

## Windows commands

From the repository root, with ordinary vcpkg dependencies installed:

```powershell
./tests/spectators/Run-Native.ps1
./tests/spectators/Run-Native.ps1 -Configuration OpenGL -Benchmark
```

An existing dependency installation can be supplied with `-DependencyRoot`.
Local command used (paths are this machine's cached dependencies and outputs):

```powershell
./tests/spectators/Run-Native.ps1 `
  -DependencyRoot 'C:\Users\Mateus\Desktop\DBO BASE\Dragon Ball Universe - DECRYPTED 2026-10-03\vcpkg_installed\x64-windows-static' `
  -BuildRoot 'C:\Users\Mateus\Desktop\DBO BASE\verification-mehah-spectators-20261012' `
  -Benchmark
```

The script uses the project's existing x64 OpenGL/DirectX configurations, MSVC
v145 and C++17; it does not change the compiler standard. No graphics context,
account, server connection, window or game assets are needed by the harness.

## Executed results and explicit pending work

- Latest OpenGL native harness: **4 groups, 38,143 ordered/state checks passed**.
- DirectX harness before the final extra effect/853-order checks:
  **4 groups, 37,858 checks passed**. Its final rebuild was stopped on request;
  the final expanded DirectX suite is **pending**, not claimed as passed.
- Ordinary OpenGL and DirectX client executables both compiled and linked.
  They were not opened, installed or used for live login testing.
- Regression coverage: missing/empty tiles; asymmetric/symmetric ranges;
  map floors 0/7/8/14/15 and query floors 0 through 15 (including outside the
  aware range); pointer order versus the old algorithm; duplicate IDs and
  pointers; null cleanup; 5,000 deterministic mixed mutations; span endpoints;
  legacy stack trimming; 853/860 automatic order; effects; walking-only tiles;
  corpse-highlight state; actual negative-displacement lookup; collision and
  top-creature selection; clear/reload and deterministic repeated queries.
- `git diff --check`: passed.
- Windows ASan was attempted but failed to link against non-instrumented cached
  OpenAL/STL annotation settings. No Windows ASan pass is claimed.
- Linux Clang 18 ASan+UBSan configuration succeeded after preparing cached
  cURL 8.21 in isolated `/tmp` folders (system cURL is 8.5). Compilation was
  **stopped on the user's request before execution**. Sanitizers are **not run**.
- Web/WASM: **not run**; no local Emscripten toolchain was found.
- Live Battle List/bot behavior, gameplay FPS/CPU and visual pixel comparisons:
  **not run**. State tests and unchanged source paths are not visual validation.

All agent-started unfinished builds were stopped when the user elected to
compile and test personally. Completed binaries/intermediates are outside the
repository in `verification-mehah-spectators-20261012`; they are not committed.

## Reproduce Linux sanitizers / CTest

With the project's dependency versions available, including cURL >= 8.21:

```sh
cmake -S . -B /tmp/astra-spectators-check -G Ninja \
  -DASTRA_BUILD_SPECTATOR_TESTS=ON -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_CXX_COMPILER=clang++ -DCMAKE_C_COMPILER=clang -DUSE_STATIC_LIBS=OFF \
  -DFRAMEWORK_SOUND=ON \
  -DCMAKE_CXX_FLAGS='-fsanitize=address,undefined -fno-omit-frame-pointer -D_GLIBCXX_ASSERTIONS' \
  -DCMAKE_C_FLAGS='-fsanitize=address,undefined -fno-omit-frame-pointer' \
  -DCMAKE_EXE_LINKER_FLAGS='-fsanitize=address,undefined'
cmake --build /tmp/astra-spectators-check --target astra_spectator_tests -j 2
ASAN_OPTIONS=detect_leaks=1 UBSAN_OPTIONS=halt_on_error=1 \
  ctest --test-dir /tmp/astra-spectators-check --output-on-failure
```

The agent's exact build directory was `/tmp/astra-spectators-asan-20261012`,
with `-DCMAKE_PREFIX_PATH=/tmp/astra-curl-821-install-20261012`. The test command
above is provided for reproduction; it was not executed in that stopped run.

## Actual algorithm-only microbenchmark

Intel Core i5-10300H, 8 logical CPUs, 16 GiB RAM; Windows x64 OpenGL native
harness, C++17/MSVC release configuration. Each row uses the same real Map/Tile
fixtures and executable: 100 warmups, 1,001 timed calls, steady_clock timing,
median index 500 and p95 index 950. Call-local reservation and seen-ID creation
are included; allocation counts intercept main-thread C++ new/new[]. This is
not a count of every allocator or GPU allocation. Background build activity
was present, so timings should be repeated on an idle machine.

The baseline reproduces the old traversal/temporary-vector algorithm in the
same executable. Both use the post-port Tile layout; this is not a separate
old-engine binary comparison and excludes mutation-maintenance costs. Queries
use an 18x14 rectangle; multi-floor scenes cover floors 0 through 7. Visible
counts are 0/3/40/400, plus 3 visible with 10,000 known; IDs are unique.

| Scene | Floors | Median before/after us | p95 before/after us | Calls/s before/after | C++ allocations before/after |
|---|---|---:|---:|---:|---:|
| Empty | Single | 2.1 / 2.5 | 2.5 / 2.9 | 476190 / 400000 | 0 / 2 |
| Empty | Multi | 16.9 / 17.8 | 19.4 / 20.1 | 59172 / 56180 | 0 / 2 |
| 3 visible | Single | 3.1 / 3.4 | 3.5 / 3.7 | 322581 / 294118 | 4 / 6 |
| 3 visible | Multi | 19.6 / 19.9 | 22.1 / 23.0 | 51020 / 50251 | 6 / 6 |
| 40 visible | Single | 10.2 / 9.3 | 11.1 / 10.1 | 98039 / 107527 | 46 / 44 |
| 40 visible | Multi | 30.7 / 30.1 | 33.0 / 33.0 | 32573 / 33223 | 50 / 44 |
| 400 visible | Single | 74.5 / 57.7 | 90.6 / 67.9 | 13423 / 17331 | 412 / 404 |
| 400 visible | Multi | 111.2 / 94.3 | 127.8 / 108.7 | 8993 / 10604 | 416 / 404 |
| 3 visible, 10000 known | Single | 3.1 / 21.5 | 3.5 / 22.3 | 322581 / 46512 | 4 / 7 |
| 3 visible, 10000 known | Multi | 19.9 / 38.2 | 22.8 / 46.9 | 50251 / 26178 | 6 / 7 |

Dense-scene retrieval improves in this measurement. Empty/tiny scenes do not;
reserving against a large known-creature count creates a substantial regression.
The requested upstream strategy is kept exactly rather than silently capped or
cached. A separately reviewed follow-up could investigate reservation policy.
No FPS improvement or universal speedup is claimed. Re-run the final expanded
harness/benchmark and live gameplay before deciding to merge.

## Review follow-up

- The new floor regression failed against the unsigned margins before the fix.
  It checks query floors 0 through 15 against map centers 0/7/8/14/15, including
  centers above/below the aware range, with ordered multi-floor results and
  unchanged single-floor behavior. Only the two margin types change. The
  corrected focused OpenGL harness passed all 38,143 checks; complete client,
  DirectX and sanitizer builds were not restarted during this follow-up.
- The CMake include finding is already satisfied internally:
  `src/framework/CMakeLists.txt` initializes `framework_INCLUDE_DIRS` with
  `src/framework/..` and calls `include_directories` before the root file
  creates `astra_spectator_tests`. The target inherits `src` and dependency
  includes from that directory; external include configuration is not needed.
- The known-count reservation risk and the 3-visible/10,000-known regression
  are already tracked in the benchmark table above. Reservation policy stays
  unchanged in this fix.
- No runtime ASan allocation-mismatch report was produced; the conditional
  aligned-allocation change is not applied. Sanitizer execution remains pending
  as described above, not validated by the ordinary native run.
- The optional CodeRabbit CLI review was not run: `coderabbit` is not installed.
