# Cyclopedia PNG Surface View audit

Base: Astra `d47e0281b0aeee6581c6bdff45e5aaa757536a4a` (merged PR #204).
The user subsequently requested a separate branch and pull request; no main merge is authorized.

References were cloned outside both repositories and inspected:

- OpenTibiaBR/otclient: `53c3878a1c5119c78e148adb32def53fea3c53f2`, MIT.
- OpenTibiaBR/canary: `09fde48ffa9afaf5c424bde460ec0c4c7c734e51`, GPL-2.0.

Only semantics were reused: floors 7 down to the selected surface floor, background opacity, and the selected floor remaining opaque. No Canary code, BMP/LZMA reader, second satellite cache, or external map/art was copied.

## Server and assets

TFS remote main inspected: `0ad2669dca7659f91a747c7e1ccda64e8e7ba1ce`.
The user's dirty `perf/realistic-load-latency` checkout was left intact, as requested.
Protocol 8.60 marker opcode 0xDD already matches the client's legacy parser. Surface/Map switching and town labels are local rendering; no new opcode, SQL table, or server change is needed.

Local `data/world/world.otbm` matches the installed PNG pack:
SHA256 `324c52b909c6924d57a84ea40796056143ed9808a0884cd4e46725379b815788`.
Its OTBM towns are Classic City (1000,1000,7), Timberport (772,967,7), and Sandstone (1033,1122,7). These are temple anchors, not guessed visual city centers. The exporter produces optional, hash-associated `cities.json`; map assets remain outside Git.

## Implementation

Surface renders through the existing indexed PNG service and shared 32-texture / 4-decode-job limits. Visible demand across all composed floors participates in one LOD plan; only complete compositions are promoted. A surface subscriber does not enable live terrain snapshots or change the HUD HD setting.

Cyclopedia no longer reloads/saves global OTMM on each open. Map is classic OTMM; underground forces Map while preserving the user's Surface preference. Slider 0-100 controls background floors. City names use a culled, decluttered pool of at most 32 labels.

Quickloot is sandboxed. Cyclopedia now queries its owning module through a read-only `getLootSelection` API instead of indexing an unrelated nil global. Map redirection no longer opens Items first.

## Initial validation / follow-up

Desktop OpenGL x64 and DirectX x64 builds succeeded. Existing GL real-GPU glitch regression passed (coherent LOD, delayed decode, zoom/full-map/floor transitions, fractional edges, and classic fallback).

The user's subsequent profiler screenshots identify a separate marker-widget bottleneck in `RealMap.setUIMarkers`: callbacks up to 497 ms and over 18,000 live widgets. Initial feature commit `aca73d0` preserves that evidence. The follow-up in PR #205 replaces eager marker materialization with a shared data-only spatial catalog and a viewport pool of at most 128 icons, plus focused performance/lifecycle tests. Network overload has not been demonstrated by these screenshots.

Map no longer requests bank/inventory resources on every open. Closing an unrelated tab no longer serializes the auto-aim profile without actual edits. Existing static marks are retained as data, with nearest/user-priority bounded selection when a view contains more than 128 candidates. Destroying a map cancels its refresh, disconnects automap callbacks, releases native subscriptions and drops its pool; the immutable catalog is reused across opens.

Final validation includes both desktop GPU backends, 100 production panel lifecycles each, actual Items focus and absent quickloot configuration, missing-pack fallback, filters/flags/labels, and all six minimap smoke modes per backend. No connected gameplay/FPS/RAM/network guarantee is claimed. See TESTES.md and BENCHMARK.md for scope and measurements.
