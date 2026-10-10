# Optional persistent HD minimap

[Step-by-step tutorial in Portuguese](hd-minimap.pt-BR.md).

Enable **Options → Graphics → HD Minimap (Satellite View)** for terrain rendered
with the actual DAT/SPR sprites. A matching offline PNG pack provides the entire
map without exploration; live sprites update currently received terrain.
The **HD** button immediately to the left of **Go to Cyclopedia Map** toggles the
same saved preference without opening Options. Green means HD is enabled; its
tooltip describes the next action. Both controls stay synchronized.
The option defaults to **off**, persists in the existing settings system, and
switches live. Unchecking it restores the classic minimap and its previous zoom.
It is independent of **HD Sprite Upscaling** (xBRZ); enabling the minimap does not
enable upscaling, change the interface layout, or require server/protocol changes.

## Rendering and limits

- The client snapshots items received from the server, including their tile
  positions and subtypes (ground patterns, fluids, and stacks).
- It reuses the existing sprite textures and draws ground, borders/bottom/common
  items, then top items. Creatures, effects, lights, and animation are excluded.
- At most 8,192 tiles and 32,768 items are retained in an in-memory LRU cache.
  Eviction is O(1). Unchanged terrain does not allocate replacement items when a
  creature moves. Classic mode skips snapshot creation entirely.
- A tile with more than 64 items falls back to its classic color. A view covering
  more than 4,096 tiles (including oversized-sprite neighbors), or containing more
  than 8,192 cached items, skips live-sprite rendering to bound draw work;
  pre-rendered satellite imagery remains available (classic colors without a pack).
- Full-map view (`Ctrl+Shift+M`) draws pre-rendered satellite LOD images without live-sprite work.
  Without a pack, it falls back to classic. HD/classic zooms are saved separately.
  Returning restores the map behind its toolbar, keeping HD, Cyclopedia, zoom
  and floor controls visible and clickable in either mode.
- Enabling HD while stationary rehydrates visible terrain from the current map.
  Recent explored terrain remains cached after leaving awareness. Disabling HD,
  logging out, cleaning the minimap, or resetting the world clears live snapshots
  and decoded images, but not persistent images on disk or the satellite index.
- Classic OTMM data, downloads, flags, party markers, floor controls, and autowalk
  remain unchanged. Areas without a cached snapshot use classic colors.

The persistent pack in `data/minimap_hd` is rendered from the selected server's
OTBM/items.otb with this client's DAT/SPR. Reopening the client loads the same
coverage, including areas never received from the server. Visible PNGs have
priority: four asynchronous decode jobs and 32 cached textures maximum. Eleven
LOD levels (1–1024) keep distant/full-map views bounded; the index does not eagerly
decode images. Wide views reserve at most 24 slots for the desired LOD, leaving
headroom for a covering overview and transitions within the 32-texture budget;
if no level fits, they use classic colors. Completed off-screen decode
jobs release their slots even after panning away. HD off releases images/live
snapshots, retaining the small index.
During zoom or full-map changes, the finest complete cached LOD covering the
visible indexed region remains displayed until every required target chunk is
ready. The covering overview and transition chunks are protected from LRU
eviction. This prevents partial new imagery from exposing colored OTMM
rectangles. A cold cache may initially show the classic map until the visible
overview is ready. Unindexed areas and transparent PNG pixels still use OTMM.
Only after visible demand is satisfied are up to four nearby chunks prefetched
within a one-chunk halo; the same cache/job bounds apply. The entire map/floor
is never loaded into RAM for prefetch.
Runtime checks asset header signatures and static 512×512 PNGs with bounded
encoded size. Missing/corrupt chunks fall back to OTMM; PNGs do not alter movement
or pathfinding flags. Budgets are not a measured FPS guarantee.

Without a matching pack, live HD remains session-local and cannot reconstruct
unseen terrain. The full-map classic fallback is retained in that case.

## Source map and offline generation

The inspected Tenkaiser folder contains 29,707 wrapped BMP/LZMA images with several
zoom levels but a different world/floor layout (filenames include floors up to
47; this server/client uses 0–15). Copying another world's images or guessing a
floor offset is not a conversion of the player's map.

The locally requested Astra pack uses `world.otbm` and `items.otb` from
`DLL and Server/forgottenserver-downgrade-1.8-8.60`, using the active `data/world`
map selected by that base's `config.lua`, not DBO's `Super.otbm` or `world global`.
`source.json` records map/OTB SHA-256, floors, levels and DAT/SPR header signatures.
Regenerate after map/asset changes, including edits that preserve header signatures.
The pack belongs to the selected world, not every server the client can connect to.

### Step-by-step generation and installation (Windows)

1. Build the native client from this branch using `vc23/otclient.vcxproj` or the
   normal CMake instructions. Use the resulting executable with this checkout's
   Lua modules. An older executable cannot export or display the satellite pack.
2. Place the server's matching DAT/SPR assets in `data/things/860/`. The offline
   script explicitly selects protocol/client version 860 and loads assets through
   `game_things`. The normal default is `Tibia.dat` / `Tibia.spr`; custom OTFI,
   OTML or indexed sprite-part files must accompany the assets when required.
   Do not substitute another world's sprites or an unrelated `items.otb`.
3. Identify the actual `.otbm` selected by the server's `config.lua` (`mapName`)
   and its matching `data/items/items.otb`. `items.xml` is not needed for image
   generation: the OTB supplies the ServerID-to-ClientID mapping.
4. Install **Python 3.11 or newer** and Pillow for the offline tool only. A local
   virtual environment keeps the dependency isolated:

   ```powershell
   python -m venv .venv
   ./.venv/Scripts/python.exe -m pip install Pillow
   ```

5. Open PowerShell in this repository's root. Run the exporter with the matching
   executable and an output directory that **does not exist**. Replace the sample
   paths below; `-Python` must reference the environment containing Pillow.

```powershell
./tools/minimap_hd/Export-Pack.ps1 `
  -BinaryPath ./build/hd-minimap/bin/otclient_gl_x64.exe `
  -WorldPath 'C:/path/to/server/data/world/world.otbm' `
  -ItemsPath 'C:/path/to/server/data/items/items.otb' `
  -OutputPath 'C:/path/to/a/new/minimap_hd' `
  -Python './.venv/Scripts/python.exe'
```

6. Wait for `Persistent HD pack ready`. The output includes `index.txt`,
   `source.json`, `minimap.otmm`, and `satellite-<level>-<x>-<y>-<z>.png` files.
   All populated map floors are exported separately. Base images cover 16×16
   tiles at 32 pixels per tile, and successive LOD images cover larger areas at
   the same 512×512 image size. This is rendered game terrain, not satellite
   photography, screenshots of the player, or AI-generated imagery.
7. Close the normal client. Back up an existing `data/minimap_hd` folder, then
   install the **complete** generated folder as `data/minimap_hd`. Its
   `index.txt` must be directly inside that directory, not one extra level down.
   Reopen the updated client and enable HD with the minimap button or Graphics
   checkbox. Players need the executable/modules and pack, not Python/Pillow.
8. Run the verification commands below with the same executable. The satellite
   smoke test needs the installed pack. Also check the minimap in-game, zoom out,
   change floors and reopen the client; automated hidden checks do not measure
   FPS or prove visual parity. Regenerate and replace the pack after map/asset
   edits, even when DAT/SPR header signatures remain unchanged.

This runs a hidden, isolated client/profile without login. Source files are
copied/read only; no server process or file is modified. The offline OTB reader
preserves literal ServerIDs (including 20026), instead of legacy fluid-ID
remapping. Rendering respects item position/subtype patterns, displacement,
elevation and ground/border/common/top layers, with a cross-sector sprite halo.
The PNG pyramid/index is published after generation; existing output directories
are refused and failed outputs/logs retained for diagnosis. Place the verified
pack at `data/minimap_hd`, backing up an existing pack when replacing it.
Generation requires a nonempty classic OTMM and limits the complete pyramid,
not just its base level, to 100,000 chunks. The index is written only after all
images, metadata and OTMM have been produced successfully. Native export has a
30-minute deadline; set `-TimeoutSeconds 3600` for a one-hour deadline on larger
maps. A timeout stops only the exporter's process and retains its logs.

Regenerate packs made before the top-item elevation correction: ground/common
item elevation now also offsets the top layer in both live HD and exported PNGs.

The matching export includes a revealed classic `minimap.otmm`, loaded before
the user's existing explored OTMM overlay. Native OTMM/server rules, not images,
remain authoritative for movement. Generated packs are git-ignored distribution
assets: ship the full pack alongside the rebuilt client or in its data archive.
Checking out source alone does not generate a full HD world. Players do not
need Python/Pillow. The export tool never replaces the normal executable/profile.

### Troubleshooting

- **Both HD controls are disabled:** use a native executable built from this
  branch, together with its current Lua modules.
- **HD appears only after walking or is lost after reopening:** the full pack is
  missing, incompatible or installed at the wrong path. Check `index.txt`, the
  images, the client log and `g_minimap.hasSatellitePack()` after assets load.
- **Different DAT/SPR assets:** regenerate the pack with the exact asset set
  distributed to players. Runtime validation checks header signatures, not a
  complete content hash or the identity of the server's current map.
- **Invalid item / OTBM export errors:** check that the map's ServerIDs are
  covered by the selected OTB and that its ClientIDs exist in this DAT. Do not
  solve mismatches by renaming image files or guessing coordinates/floor offsets.
- **Output already exists:** choose a fresh output path. The exporter deliberately
  refuses to overwrite a previous pack. Keep failed output/logs for diagnosis.
- **Python/Pillow missing:** use `-Python` with the interpreter that has Pillow.
- **Export timed out:** inspect the retained logs before increasing
  `-TimeoutSeconds`. Never install an incomplete output directory.
- **A missing or damaged PNG:** that chunk falls back to classic colors and logs
  an error; reinstall a complete verified pack.

## Native build and compatibility

Rebuild the native client with `vc23/otclient.vcxproj` (OpenGL or DirectX x64), or
the normal CMake build. Lua modules and the executable must come from the same
revision. Older executables keep the classic minimap and show both HD controls
disabled instead of calling unavailable native functions.

The native Lua getters intentionally remain non-const for compatibility with the
existing Lua member-function binder.

## Verification

The follow-up audit, confirmed findings, test evidence and unmeasured performance
criteria are documented in [the PR #204 audit](audits/pr204/AUDITORIA_PR204_FULL.md).

From the repository root:

```powershell
luajit tests/minimap_hd/options_test.lua
python tests/minimap_hd/pyramid_test.py
./tests/minimap_hd/Check-TranslationUnits.ps1
./tests/minimap_hd/Run-Smoke.ps1 -BinaryPath ./build/hd-minimap/bin/otclient_gl_x64.exe
./tests/minimap_hd/Run-Smoke.ps1 -BinaryPath ./build/hd-minimap/bin/otclient_gl_x64.exe -Satellite
./tests/minimap_hd/Run-Smoke.ps1 -BinaryPath ./build/hd-minimap/bin/otclient_gl_x64.exe -Export
./tests/minimap_hd/Run-Smoke.ps1 -BinaryPath ./build/hd-minimap/bin/otclient_gl_x64.exe -Audit
./tests/minimap_hd/Run-Smoke.ps1 -BinaryPath ./build/hd-minimap/bin/otclient_gl_x64.exe -Glitches
```

The standalone Lua test covers opt-in defaults, persistence, live toggling,
separate zooms, full-map round trips (including changing the option while full
map is open), and old executable fallback. The native smoke test loads the real
client modules and local 8.60 DAT/SPR, verifies the Graphics checkbox, quick-button
placement/label size, synchronized toggling and persistence, bindings,
terrain updates, tile/item cache limits, world resets, and marker/click alignment.
It also exercises repeated full-map round trips in both modes and actual native
zoom preservation when switching modes inside full-map view. The standalone
mock isolates Lua logic; it does not substitute for these native checks.
It uses a separate `astra_hd_minimap_smoke` profile, a temporary resource directory,
and no server login. The default run hides the window and skips visual rendering.
The pyramid test covers child placement, transparent gaps, floors, manifest counts,
classic OTMM preservation, no-overwrite, final-count overflow, missing OTMM and
copy failures without publishing an index. `-Satellite` requires the generated
local pack and checks lazy close/far LOD decode with zero live map tiles, retained
coverage after logout/reset, disk reloading and optional classic mode. Run twice
to verify fresh launches. These hidden checks do not establish visual parity/FPS.
It also checks that known personal OTMM cells overlay the revealed map without
unknown cells erasing the other revealed sectors in the same block.
It checks abandoned-decode recovery and the 32-texture budget for 4K views.
`-Export` creates synthetic OTB/OTBM inputs using the local DAT/SPR, checks literal
ServerID 20026 and classic OTMM coverage on two floors after reloading, then
compares real exported PNG pixels against an independent Pillow composition to
verify top/common elevation. This test requires Python with Pillow but no server
files, installed satellite pack or login.

For an interactive renderer check and a synthetic-terrain screenshot, add
`-Visual`. That run briefly opens a test window and verifies stationary HD
rehydration through the actual renderer. Logs/artifacts are retained in the
temporary directory printed by the script.

`-Audit` requires the installed pack and Python/Pillow. It tests retained destroyed
widgets, single option callbacks, rapid resets/toggles, empty-view lookups, and
isolated malformed index/PNG/ENC3/OTMM fixtures. Valid plain/encrypted PNGs and
custom-seed discovery remain supported; a conflicting seed is rejected. Only
fixture-specific error messages are allowed by the runner. Normal `--test`
remains fail-fast. These tests do not replace FPS profiling or sanitizers.

`-Glitches` also requires Python/Pillow and local DAT/SPR. It creates an isolated
opaque HD pack over deliberately contrasting OTMM, injects slow PNG decodes,
and captures the production minimap draw queue in real offscreen framebuffers.
Pixel comparisons cover partial-decode retention, coherent LOD promotion,
fractional zoom/shared edges, full-map return, another floor and classic-only
fallback. A 100-view pan sequence checks the cache/job caps under LRU pressure.
Repeat with the DirectX binary to exercise ANGLE/D3D11; no login or visible
window is needed. This is GPU pixel validation, not an FPS benchmark.
See [the visual-glitch follow-up](audits/pr204/VISUAL_GLITCHES_PR204.md) for the
video diagnosis, CI include fix and evidence.

Decode admission is independent of the texture LRU: canceled jobs keep their
slots until completion, including after cache eviction, HD-off and pack resets.
The four-job bound applies to minimap work, not other users of the shared async
dispatcher. Cancellation is cooperative and cannot interrupt an ongoing PNG
decode. Results from canceled jobs cannot enter a replacement pack. A destroyed
HD widget releases its subscription immediately, even if Lua retains the object.

Empty, unavailable and over-budget terrain gets a bounded negative snapshot in
the same 8,192-entry cache. Item notifications replace it when terrain arrives;
stationary empty views no longer repeat map lookups every preparation. The tile
counter includes negative entries; the item counter counts actual snapshots.
Satellite file reads enforce the 4 MiB budget before allocation, also bounding
declared ENC3 decompression size. APNG/truncated chunks are rejected before PNG
decoding. Invalid OTMM compression now returns failure; OTMM loading is still
not transactional and may have applied earlier valid blocks before an error.

Cache diagnostics are available in the Lua terminal:

```lua
g_minimap.getSpriteCacheTileCount()
g_minimap.getSpriteCacheItemCount()
g_minimap.getSatelliteChunkCount()
g_minimap.getSatelliteTextureCount()
g_minimap.getSatelliteDecodeCount() -- Outstanding slots, including completed uncollected results.
g_minimap.getSpriteViewCount()
g_minimap.getSpriteTileLookupCount() -- Cumulative lookups, not frame duration.
g_minimap.getSatelliteViewLevel({width = 3840, height = 2160}, 8)
g_minimap.hasSatellitePack()
g_minimap.hasSatelliteTile(g_game.getLocalPlayer():getPosition())
```
