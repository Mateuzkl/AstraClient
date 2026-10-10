# PR #204: coherent HD transitions and standalone-build fix

Date: 2026-10-10. Follow-up to `ced3b00`, on
`feat/optional-sprite-hd-minimap`. No new PR, main checkout or merge.
The earlier full audit is a historical snapshot, not a claim that this follow-up
had already been tested.

## Evidence and root cause

Inspected the user-provided comparison image and `video aqui.mp4` in the local
`PR204` folder, including extracted frames between 24.5 and 28.5 seconds.
The enlarged/zoomed map briefly shows flat colored rectangles around ready HD
imagery; the rectangles disappear when the remaining imagery is available.

The existing draw order was classic OTMM followed by satellite PNGs. A zoom or
viewport change selected the new LOD immediately. Each ready PNG was drawn
independently, while pending chunks were skipped, exposing the colored OTMM
underneath. Async loading was bounded, but presentation was not coherent. LRU
eviction could also discard the previous covering LOD during admission.
Preloading alone would only reduce the probability of this race.

The shared-edge `lround` projection and clipping are retained. The evidence does
not establish a corrupt PNG decode or a driver-specific texture corruption.

## Rendering fix

- Keep the finest complete cached LOD covering the **visible indexed region**
  while the target loads. Promote the target only when all required indexed
  chunks have textures. Do not mix individual newly ready child chunks with
  an exposed classic background during refinement.
- Load and protect a covering coarsest-level overview of the visible region.
  Request target chunks center-out after overview demand; failed overview files
  do not permanently prevent finer-level requests.
- Protect overview, target and the selected fallback from LRU eviction. Release
  the old finer LOD once the target is ready. Coarsen the target when the union
  cannot fit; do not increase the cache budget.
- Reserve at most 24 conservative target-view slots within the existing
  32-entry texture cache. Up to four neighboring indexed chunks in a one-chunk
  halo may be prefetched **after** visible demand. Outstanding PNG jobs remain
  limited to four, including canceled tasks awaiting completion.
- No whole-world/floor decode, synchronous PNG wait, protocol change, generated
  pack rewrite, artificial rectangle overlay or forced classic-mode removal.

Cold startup can show the whole classic view before the first overview is ready.
Unindexed regions, transparent pixels and unavailable/corrupt packs retain OTMM
fallback. Floor changes never display imagery from a different floor. These are
intentional fallback semantics, not a promise of HD for missing data.

## CI compilation failure

All three completed failed checks at `ced3b00` reported the same source error:
`src/client/luafunctions_client.cpp:241`: `g_app` was undeclared.
The local Visual Studio unity build had incidentally supplied its declaration
from another source; CMake/Clang compile this translation unit independently.
Added its direct `framework/core/application.h` include and explicit dependencies
for the new rendering code. No workflow suppression or error allowlist added.

Failed baseline logs:

- [Windows push](https://github.com/Mateuzkl/AstraClient/actions/runs/38058114272)
- [Windows PR](https://github.com/Mateuzkl/AstraClient/actions/runs/38058118341)
- [WebAssembly push](https://github.com/Mateuzkl/AstraClient/actions/runs/38058114274)

The replacement commit's CI must be checked separately; old red checks are not
rerun evidence for the corrected source.

## Local validation

Final sources: MSBuild OpenGL x64 and DirectX x64 both PASS, **0 warnings / 0 errors**.
Both changed translation units also PASS standalone MSVC `/Zs`, with neither
unity sources nor precompiled headers. Reproduce that check with:

```powershell
./tests/minimap_hd/Check-TranslationUnits.ps1
```

Five native suites pass on **both** final binaries: default, Satellite, Export,
Audit, Glitches. Lua options/syntax and Python pyramid tests pass as well.

The new `-Glitches` suite uses isolated synthetic opaque 512x512 PNGs, five LODs
and two floors over deliberately contrasting OTMM. A 150 ms decode delay makes
partial completion observable. Test-only Lua bindings capture the **production
minimap draw queue** through real GPU offscreen framebuffers; Python/Pillow
independently checks the pixels and geometry. No login or user profile writes.

Assertions cover:

- ready parent retained immediately after zoom and after the first child decode;
- complete target promotion and no OTMM-colored holes or black shared-edge seams;
- odd widget dimensions at fractional scale 5.5;
- actual full-map controller entry/return, another floor and classic-only fallback;
- 100 real view pans with at most 32 cache entries and four outstanding jobs.

Local renderer evidence: Intel UHD OpenGL 4.6; DirectX via ANGLE/D3D11, OpenGL ES
3.0. Nine captures per renderer pass pixel comparison. This checks these drivers,
not every GPU. Test-only delay defaults to zero and is not exposed in normal Lua.

Final smoke log directories under `%TEMP%`:

| Suite | OpenGL suffix (`astra-hd-minimap-`) | DirectX suffix |
| --- | --- | --- |
| Default | `4d98c51c46e04f888afdd37ca2cf77d2` | `29e3801a2d464a1ea7c26e9aedc96e21` |
| Satellite | `b706fe3a29eb47eda10403ad536740ba` | `a6658b8ae53c484699597ab69433fcb6` |
| Export | `e006c217a73a425199ed1f3550aa868b` | `349136551df3495da59969c900437a42` |
| Audit | `ad8917cdc12f456da6cf3a64c917c6b8` | `b8b57028413d42e880680fc26d04a8e2` |
| Glitches | `0a433d9f3db245b78e52cd9dff13ae6c` | `38dddd5d7d334056a960ccbd7169b517` |

Captures/metadata are retained in the isolated smoke profile, directories
`glitch-1791642694-2417` (OpenGL) and `glitch-1791642730-2758` (DirectX).
Build logs: `build/hd-minimap-glitch-gl.log` and `build/hd-minimap-glitch-dx.log`.

## Performance scope

Admission, nearby prefetch and cache membership are bounded and covered by tests.
Presentation does not wait for decoding. This does **not** measure FPS, frame-time
percentiles, RAM/VRAM totals or eliminate the graphics driver's texture-upload
cost. Draw queues/atlas can retain GPU resources beyond cache membership. No new
FPS guarantee, whole-map memory estimate or sanitizer result is asserted here.
WebAssembly execution was not tested locally; remote CI supplies its build check.
