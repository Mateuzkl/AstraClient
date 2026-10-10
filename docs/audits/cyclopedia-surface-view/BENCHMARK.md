# Callback measurements — not an FPS/network/RAM guarantee

User evidence before the fix: RealMap marker callbacks up to 497 ms, approximately 81-82% of measured callback time, and 18,220 live widgets. These screenshots came from a connected session; they are not directly comparable to the offline fixture below and do not prove network saturation.

## Local production-controller fixture

100 panel opens/closes per backend, with 20,000 off-screen data markers and 200 dense visible markers. The same production Lua/controller/native widgets are used, capped at 128 marker icons and 32 labels. GPU readback/PNG encoding completes before the callback timing phase. `g_clock.millis()` records wall time with integer-ms resolution (0 does not mean zero cost).

Observed run on Intel UHD Graphics, Windows x64, 10 October 2026:

| Backend / phase | Mean ms | P95 ms | Max ms |
|---|---:|---:|---:|
| OpenGL / open | 18.25 | 33 | 67 |
| OpenGL / close | 0.22 | 0 | 16 |
| OpenGL / marker update | 0.83 | 2 | 2 |
| DirectX ANGLE / open | 19.62 | 34 | 102 |
| DirectX ANGLE / close | 0.27 | 0 | 17 |
| DirectX ANGLE / marker update | 0.73 | 2 | 3 |

Artifacts: `surface-1791648186-2570` (GL) and `surface-1791648202-2541` (DX) under the isolated `astra_hd_minimap_smoke` write directory. Each contains `timings.json`, `frames.json`, and GPU PNG captures. Later runs may differ with cold assets, drivers, scheduler and background load. An earlier run with simultaneous screenshot encoding had a 251 ms opening outlier and 16 ms marker-update outlier; these were not hidden or converted into a zero-lag claim.

Standalone LuaJIT data-index test, 20,000 entries, 100 whole-world queries: observed 0.149-0.336 seconds total across runs. A bounded heap selects nearest/priority top-k without sorting/allocating every visible marker. All records remain available as data; zooming in reveals markers omitted by the 128-icon display budget.

The fix removes the repeated world-sized UI materialization and quadratic revisit loop. Opening still constructs the finite Cyclopedia controls, so its cold/UI cost is not zero. A 4 ms creation-admission deadline is checked between icons; a single texture/UI creation or OS preemption cannot be forcibly interrupted.

## Bounds and honest limits

- At most 128 icon widgets and 32 city-label widgets per Cyclopedia map; no pool growth across the 100 destruction cycles.
- One shared 32-entry satellite texture LRU and at most four outstanding minimap decode slots, including canceled work. These are cache/admission bounds, not a total-process/GPU memory measurement; other modules, queued frames and atlas allocations also consume memory.
- No new live-terrain snapshots from Surface mode, and no bank/inventory resource requests per Map opening. Explicit teleport/autowalk/other tabs retain their normal existing network behavior.
- PNGs are decoded on demand with bounded visible/nearby prefetch, not a whole-world image preload. The PNG index and compact marker data catalog are retained, not every map texture/widget.
- Connected gameplay FPS/ping/bytes, working set after long gameplay, and other operating systems were not measured. Re-test those in-game with the optional monitor closed, since the diagnostic window itself consumes time. Its initial 12 ms SlowLua warning is not the sustained 200-497 ms marker stall.
