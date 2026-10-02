# Ping and dispatcher telemetry validation

## Scope and provenance

Client branch: `feat/ping-latency-cpp23`, based on updated main `b6723587`.
Server branch: `feat/astra-ping-telemetry`, based on PR #318 at `ff7600fa`.
The ItemRegistry lifetime pin and the rest of #318 are retained, not recreated.
See [ping-latency.md](ping-latency.md) for the implementation and exact wire bytes.

The test environment is an isolated synthetic database/map, not the user's
production world. Only benchmark accounts are reset. The user's XML, DAT/SPR,
world, normal configuration and existing executable are not committed or replaced.
No ASan, UBSan or ThreadSanitizer run was performed.

## Builds and deterministic checks

Windows: native `vc23/otclient.vcxproj`, DirectX x64, MSVC 19.51/v145,
`/std:c++23preview`. Full compile/link succeeded. Outputs were isolated under
`%LOCALAPPDATA%/Temp/astra-ping-build`, not copied over the normal client.

```powershell
& 'C:/Program Files/Microsoft Visual Studio/18/Community/MSBuild/Current/Bin/MSBuild.exe' `
  vc23/otclient.vcxproj /m:3 /p:Configuration=DirectX /p:Platform=x64 `
  /p:OutDir=C:\Users\Mateus\AppData\Local\Temp\astra-ping-build\bin\ `
  /p:IntDir=C:\Users\Mateus\AppData\Local\Temp\astra-ping-build\obj\ `
  /p:VcpkgManifestInstall=false /verbosity:minimal
```

Linux client: GCC 13.3, CMake 3.28, Ninja, Release/C++23, dynamic system
dependencies and LuaJIT. Full compile/link succeeded. Windows/Linux pre-existing
deprecation warnings remain visible; they are not suppressed by this change.

```sh
cmake -S AstraClient -B /home/mateus/astra-ping-cpp23-linux -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DUSE_STATIC_LIBS=OFF -DLUAJIT=ON
cmake --build /home/mateus/astra-ping-cpp23-linux --parallel 3
c++ -std=c++23 -Wall -Wextra -pedantic .github/tests/ping_latency.cpp -I. -o /tmp/astra-ping-test
/tmp/astra-ping-test
c++ -std=c++17 -Wall -Wextra -pedantic .github/tests/ping_latency.cpp -I. -o /tmp/astra-ping-legacy-test
/tmp/astra-ping-legacy-test
luajit .github/tests/ping_stats.lua
```

Tracker/decoder checks pass with C++23 and C++17. The Lua UI test passes,
including deliberately different proxy/gameplay RTT values in the production
topmenu handler. Existing spell cooldown and negative-offset C++ tests also pass
with C++23; negative-offset and Bestiary Lua regressions pass.
The C++17 helper check is not a full Android build. Android/WASM are unvalidated
optional targets, with the explicit Android legacy exception documented separately.

Linux server: existing PR #318 Release build, GCC 13.3/unity/LTO. Full `tfs` and
focused test targets build successfully. The following command passes 5/5:

```sh
cmake --build /home/mateus/atlas-perf-20261001-gcc \
  --target tfs test_astra_ping test_protocolgame_pipeline --parallel 3
ctest --test-dir /home/mateus/atlas-perf-20261001-gcc --output-on-failure \
  -R 'astra_ping|spell_cooldown|protocolgame_pipeline|custom_ping_tracker|combat_packets'
```

`test_astra_ping` passes four production-path cases: negotiated/legacy bytes,
monotonic/clamped deltas, short input, and normal/spy/spectator/stopped sessions.
The unchanged pipeline suite retains admission/expiration/lifetime coverage.

## Stress methodology

Intel Core i5-10300H (4 cores/8 threads), WSL2 Ubuntu, approximately 7.7 GiB RAM.
Server CPU is process CPU time divided by wall time: **100% means one logical
core**, not the whole machine. Main-thread CPU is the Reactor thread; network
CPU sums two ASIO threads identified by read-only stack inventory before load.
No debugger or compiler runs inside measurement windows.

The frozen Release StressBot drives 1,000 synthetic arena monsters, seed 180252,
20 ms login pacing and an 18 packets/s/bot configured cap. REALISTIC and TORTURE
retain their existing movement/combat settings. Each window requires every bot
online, 20 seconds of full-population warm-up and at least 60 seconds of sampling.
Metrics are enabled in this private environment.

One **actual newly built Astra client** also logs into the same server and
samples the production Game RTT/smoothing/jitter/queue APIs approximately once
per second. Its renderer runs under Xvfb/software OpenGL, so client scheduling
is part of observed RTT. Sampling is not every ping and can miss shorter spikes.
The normal extended ping cadence remains 250 ms. No response is moved to ASIO.
This exercises one telemetry-capable client amid the bot load, not 1,000 Astra
clients generating 4,000 negotiated telemetry requests/s. No such throughput
claim follows from this run. Millisecond queue values are truncated: a measured
sub-millisecond queue displays 0 ms; an unsupported queue remains -1/unavailable.

Client p95/max below describe the sampled latest RTT, not all individual replies.
Reactor p95/p99 are the worst reported five-second histogram upper bounds, not
exact whole-run quantiles. Reactor maximum is the observed interval maximum.
These populations must not be compared as though they were identical.

Raw artifact naming: `<label>-result.json`, `-ping.json`, `-telemetry.json`,
`-client.log`, `-server.log`, `-bots.log`, `-window.log`, `-thread-inventory.log`.
They remain in the local `atlas-performance-results-20261001` directory outside
both repositories. Private runtime data and benchmark credentials are not uploaded.

## Measured results

All final scenarios completed with the full requested bot population. Every
listed window has zero bot disconnects, parser errors and unknown opcodes;
the real client has zero ping timeouts, unknown replies, duplicate replies and
observed loss. No Reactor task drops were reported. Server and observer both
exit with code 0 in the final runs. Existing UI teardown warnings remain visible.

### Server CPU and memory

CPU percentages below use the one-core convention described above. Network CPU
is the sum of two ASIO threads, not just the busiest thread. Small rounding and
other-thread contributions explain differences between components and total.

| Server / scenario | Window s | Total CPU % | Main CPU % | Network CPU % | Mean RSS MiB |
| --- | ---: | ---: | ---: | ---: | ---: |
| Telemetry / LOGIN_ONLY 600 | 60.47 | 23.58 | 8.04 | 15.56 | 303.99 |
| Telemetry / REALISTIC 300 | 60.58 | 50.21 | 20.09 | 30.12 | 259.09 |
| Telemetry / REALISTIC 600 | 60.58 | 101.84 | 38.92 | 62.89 | 334.12 |
| Telemetry / REALISTIC 1000 | 60.01 | 161.50 | 64.44 | 97.03 | 442.83 |
| Telemetry / TORTURE 1000 | 60.72 | 132.75 | 79.33 | 53.39 | 479.36 |
| Legacy reference / REALISTIC 600 | 60.01 | 104.48 | 39.69 | 64.80 | 338.05 |
| Legacy reference / TORTURE 1000 | 60.78 | 134.66 | 79.93 | 54.76 | 476.74 |

### Real client measurements, milliseconds

RTT is sampled latest RTT. Smoothed RTT and jitter show mean/maximum; queue and
RTT show mean/p95/maximum. These are real measurements, not RTT subtraction.

| Server / scenario | Samples | RTT mean / p95 / max | Smoothed mean / max | Jitter mean / max | Queue mean / p95 / max | Max pending |
| --- | ---: | --- | --- | --- | --- | ---: |
| Telemetry / LOGIN_ONLY 600 | 62 | 10.10 / 13 / 16 | 10.82 / 17 | 3.05 / 12 | 0.00 / 0 / 0 | 1 |
| Telemetry / REALISTIC 300 | 62 | 10.03 / 18 / 37 | 9.48 / 14 | 2.58 / 7 | 1.27 / 7 / 24 | 1 |
| Telemetry / REALISTIC 600 | 62 | 9.77 / 18 / 22 | 13.34 / 21 | 6.81 / 24 | 0.69 / 4 / 6 | 1 |
| Telemetry / REALISTIC 1000 | 60 | 22.58 / 49 / 101 | 36.47 / 95 | 27.27 / 87 | 5.57 / 19 / 45 | 2 |
| Telemetry / TORTURE 1000 | 61 | 230.56 / 463 / 559 | 242.38 / 305 | 80.20 / 148 | 144.67 / 264 / 311 | 2 |
| Legacy reference / REALISTIC 600 | 62 | 11.27 / 16 / 26 | 12.39 / 25 | 4.35 / 19 | Unavailable | 1 |
| Legacy reference / TORTURE 1000 | 63 | 226.43 / 446 / 563 | 244.51 / 354 | 82.60 / 143 | Unavailable | 2 |

Last in-window snapshots, rather than averages:

| Scenario | Latest RTT | Smoothed RTT | Jitter | Server queue | Timeouts | Pending |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| REALISTIC 600 | 7 ms | 11 ms | 2 ms | 0 ms | 0 | 1 |
| TORTURE 1000 | 182 ms | 246 ms | 116 ms | 99 ms | 0 | 0 |

### Reactor tails and useful work

Packet rates are deltas of the bots' packet counters over the CPU window, not
bytes/s or extrapolations from bot count. They exclude the additional observer.
Successful execution rates use the existing `successful_attacks` reports in
`Player::doAttacking` after `useWeapon`/`useFist` returns success; they are not
attack-request rates. These interval-report rates are approximate, since the
five-second reporting boundaries and CPU snapshots are not exactly aligned.

| Server / scenario | Reactor queue p95 / p99 / max ms | Bot packets to server / from server per s | Successful weapon/fist executions per s |
| --- | --- | --- | ---: |
| Telemetry / LOGIN_ONLY 600 | 2.10 / 16.78 / 74.03 | 118.11 / 3165.41 | 0.00 |
| Telemetry / REALISTIC 300 | 8.39 / 33.55 / 55.11 | 113.36 / 6919.96 | 322.55 |
| Telemetry / REALISTIC 600 | 33.55 / 134.22 / 123.94 | 239.62 / 14059.99 | 624.59 |
| Telemetry / REALISTIC 1000 | 134.22 / 536.87 / 375.24 | 399.66 / 19207.72 | 900.91 |
| Telemetry / TORTURE 1000 | 536.87 / 536.87 / 432.14 | 2097.39 / 7199.95 | 1959.70 |
| Legacy reference / REALISTIC 600 | 16.78 / 67.11 / 98.90 | 236.62 / 13996.43 | 620.83 |
| Legacy reference / TORTURE 1000 | 536.87 / 536.87 / 429.33 | 2122.49 / 7331.43 | 1939.49 |

A histogram p99 upper bound can exceed the observed maximum (for example,
134.22 versus 123.94 ms). This is histogram bucket resolution, not an impossible
timing result. Each row contains twelve five-second Reactor reports.

TORTURE increases both sampled per-ping queue (144.67 ms mean) and RTT
(230.56 ms mean). That is consistent with retained dispatcher backlog semantics.
The sparse client sample need not catch the slowest task in the Reactor's much
larger population: REALISTIC 600's sampled queue maximum is only 6 ms while
Reactor task queue maximum is 123.94 ms. Neither measurement replaces the other.

### Compatibility reference and comparison limits

The frozen `combat-packet-after` binary is a legacy-protocol reference from the
earlier performance experiment. Its exact correspondence to `ff7600fa` is not
asserted. Both reference runs use the **same newly built client**, not the former
unbounded client. This validates fallback and supplies a local reference, not an
isolated before/after attribution to this patch.

Raw CPU differences are -2.64 percentage points for REALISTIC 600 and -1.91 for
TORTURE 1000. However, TORTURE mean RTT is slightly **higher** with telemetry:
230.56 versus 226.43 ms. REALISTIC 600's Reactor p99 bound is also higher:
134.22 versus 67.11 ms. Single windows, different sampled task populations,
host scheduling and imperfect binary provenance do not establish a speedup
or a regression attributable to this instrumentation. No guaranteed CPU or
latency improvement is claimed.

Final artifact labels:

```text
ping-v2-login-600
ping-v1-realistic-300
ping-v1-realistic-600
ping-v1-realistic-1000
ping-v2-torture-1000
ping-legacy-reference-realistic-600
ping-v2-legacy-reference-torture-1000
```

Binary SHA-256 identifiers:

```text
telemetry tfs: 56b9c649a83542471e50772d553c7cc72ddaf8a9edb633616d6f9518ee80d581
legacy tfs:    90059975b55338307b2d144b1f45ff81d16472a5cf902400e131190bfeb738f6
Linux client:  d648f6fd7bef28dcc6a3a3fc1de60060b696d4e31654bb09036a5c183f9c03e6
```

### Failed attempts and repeats retained

No failed attempt is silently counted as successful ping validation:

| Artifact label | CPU % | RTT/queue validation | Reason for exclusion/repetition |
| --- | ---: | --- | --- |
| `ping-after-login-600` | 22.03 | No client samples | Private asset directories were symlinks not accepted by the resource layer |
| `ping-after-login-600-v2` | 22.40 | No client samples | WSL bind mounts were not in the client's launch namespace |
| `ping-after-login-600-final` | 25.02 | No client samples | Direct-login fixture had not loaded the 8.60 feature profile |
| `ping-v1-login-600` | 23.13 | 62 samples; RTT mean 21.40 ms, queue mean 9.85 ms | Client aborted after measurement during private observer teardown |
| `ping-v1-torture-1000` | 132.18 | 63 samples; RTT mean 232.48 ms, queue mean 139.46 ms | Same post-window direct-login teardown issue |
| `ping-legacy-reference-torture-1000` | 139.88 | No client samples | Private fixture accessed a nonsandboxed module through the wrong namespace |

The fixture now initializes the normal character-selection UI before direct
login and defers observer application exit until Game finishes disconnecting.
The affected final cases were repeated successfully, including observer exit 0.
Those corrections affect only the private harness, not production ping/UI code.
Initial smoke attempts also exposed startup/lifecycle fixture issues; their logs
are retained. The legacy smoke ultimately received five real Game RTT samples.

## Interpretation limits

RTT includes dispatcher backlog; server queue is only the measured interval up
to dispatcher entry. Queue subtraction does not produce guaranteed Internet
latency. The instrumentation is intended to clarify measurement, not to promise
lower CPU or lower RTT. One local synthetic window per scenario does not establish
production capacity, a statistically significant performance gain, or mobile
compatibility. No main branch is automatically merged by this work.
