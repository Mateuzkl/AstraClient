# RTT and Astra dispatcher telemetry

## What is measured

`g_game.getPing()` and `onPingBack` retain the latest client-observed round-trip
time in integer milliseconds. The latency graph also retains this raw RTT.
The value includes network transit, server admission/copy, dispatcher backlog,
processing/output and client scheduling. It is **not Internet latency**.
The UI keeps its existing 250/500 ms thresholds on this latest value, so a spike
is not hidden by smoothing. `showPing` and `showFps` now control their own labels.

The former map retained every answered ID until logout: approximately 14,400
entries/hour at the normal 250 ms interval. `PingTracker`, owned by `Game`, now
uses 64 fixed pending slots and a 64-entry recent-answer ring. Replies remove
their requests before graph/Lua callbacks. Requests expire after 10 seconds;
no new request is sent if all slots are occupied. Unknown, expired and duplicate
replies cannot change RTT or allocate state. Older duplicates outside the recent
ring are counted as unknown. Zero is skipped and wrapping IDs avoid live slots.

Logout clears requests, diagnostics and smoothing and advances a generation.
The Game-owned ID sequence intentionally continues across sessions to reduce
late-reply collisions. Scheduling cancels the prior event before replacing it;
callbacks check their captured generation, online state and live connection.
Callbacks from a superseded ProtocolGame connection are ignored.

All internal times use `std::chrono::steady_clock` and integer microseconds.
The first smoothed sample is RTT; initial jitter is RTT/2. Thereafter smoothing
uses alpha=1/8 and jitter uses beta=1/4 with absolute deviation from the previous
smoothed RTT. Integer divisions truncate to microseconds. Loss is
`100 * timedOut / (received + timedOut)`; pending requests are not declared lost.

## Negotiation and wire layout (8.60, little-endian integers)

Login's existing authenticated Astra `A` marker/signature remains unchanged.
The `C` capabilities byte advertises bit 7 (`0x80`). The server advertises
`GameAstraPingTelemetry = 153` via feature packet `0x43` only for a capable Astra
connection. The client never enables it from the version profile alone.

| Message | Payload, excluding outer headers/checksum/encryption |
| --- | --- |
| Legacy request | `40 + u32 id + u16 previous RTT + u16 FPS` (9 bytes) |
| Legacy response | `40 + u32 id` (5 bytes) |
| Telemetry request | Identical legacy request (9 bytes) |
| Negotiated response | `40 + u32 id + u32 serverQueueMicros` (9 bytes) |

Example ID `0x12345678`, RTT 15 ms, FPS 60, queue 1,000 microseconds:

```text
request:           40 78 56 34 12 0F 00 3C 00
legacy response:   40 78 56 34 12
telemetry response:40 78 56 34 12 E8 03 00 00
```

The historical OTCv8 previous-RTT/FPS fields are deliberately retained; this TFS
does not consume them. Unknown RTT is represented by 65535 and numeric fields
are saturated rather than wrapped. The decoder validates 4 or 8 available bytes
before consuming any payload and reads the queue only when negotiated.

On the server, the timestamp is captured on ASIO in `parsePacket`, before
backlog admission and packet copy, and carried by value in the existing task.
The second timestamp is captured at entry to `parsePacketOnDispatcher`.
This metric includes admission/copy/enqueue plus waiting until dispatch starts;
it excludes subsequent handler/output processing. It saturates at UINT32_MAX
microseconds. Pings still use existing admission limits and dispatcher ordering.
The response uses `PacketBuffer<9>`, not a 65 KB temporary or JSON.

Per-ping queue time and Reactor interval p95/p99 sample different populations.
Do not equate them or label RTT minus queue as measured network latency.

## Lua API and consumers

Existing consumers remain compatible: game/client stats, topmenu `onPingBack`,
terminal ping commands, game_helper scripting and cavebot/MACHINE_UTILS.
Legacy `setPingDelay` still controls the separate legacy ping loop; extended
pings retain the 250 ms cadence. No RTT scaling is introduced.
The remaining topmenu proxy override was removed: the topmenu now uses the same
gameplay RTT as `onPingBack`, rather than substituting proxy transport latency.

Additional APIs: `getSmoothedPing`, `getPingJitter`, `getServerQueueDelay`
(integer ms; -1 if unavailable), `getPingLossPercent`, `getPendingPingCount`,
`getPingSentCount`, `getPingReceivedCount`, `getPingTimeoutCount`,
`getPingUnknownReplyCount`, `getPingDuplicateReplyCount`.
`setPingDiagnostics(true)` enables optional logs at most once per five seconds
on accepted replies; disabled by default. Unknown queue is -1, not a fake zero.

## Desktop C++23

Top-level CMake requires CMake 3.20+ and C++23, with no compiler-extension
fallback. Framework CMake inherits that requirement. All six native vc23
configurations use `stdcpp23` (`/std:c++23preview` in current MSVC).
Primary CI remains Windows/VS2022 with current tools and Linux/Ubuntu; vcpkg
dependencies/baseline are unchanged. Tested locally with MSVC 19.51/v145 and
GCC 13.3. Native Windows requires a toolset providing `/std:c++23preview`.

Migration fixes are limited to a const equality operator, invalid null string
returns/initialization, and a UTF-8 `char8_t` bridge at the libzip C API.
Pre-existing deprecation warnings are not suppressed globally.

The optional Android vcxproj is an explicit **legacy C++17 exception**: it still
targets NDK r21d/Clang 5.0. The ping helper intentionally remains C++17-compatible,
with an independently compiled compatibility test; a full Android build was not
validated. WASM inherits C++23 from CMake but its hardcoded SDK paths have no
maintained CI and were not validated. Neither exception silently lowers the
desktop target.

## Validation

Deterministic tests: `.github/tests/ping_latency.cpp` exercises consumption,
duplicates/unknown IDs, expiry, capacity, wrap/zero, reset/generation, EWMA,
100,000 requests, legacy decoding, negotiated decoding and truncated replies.
`.github/tests/ping_stats.lua` checks option ownership, queue availability and
unchanged classification boundaries. Content CI includes all ping/negotiation
sources and runs these tests with C++23/LuaJIT.

Stress measurements and remaining validation status are recorded separately in
`ping-validation.md`. Stress results are not production-capacity guarantees.
