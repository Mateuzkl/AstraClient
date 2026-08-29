# Browser/WASM source PR audit

Source reviewed: `opentibiabr/otclient` PR #894, merge commit
`0700333f639e9221561344b3f60ec3f4eabd8b92` against its first parent. The
range contains exactly **90 files**, **2,479 insertions** and **70 deletions**.
The AstraClient baseline was `efaaea81a382ec6b3f89e52fa67ac2a5d527c450`.

Status meanings:

- `PORTED`: the same responsibility was brought over directly.
- `ADAPTED`: the responsibility was reimplemented for Astra's architecture.
- `NOT_NEEDED`: the source responsibility/dependency is absent or irrelevant.
- `ALREADY_PRESENT`: Astra already had the required behavior or a safer form.
- `REJECTED_AS_UNSAFE`: the source change was deliberately replaced or omitted.

`Exists` refers to the same path/responsibility in the Astra baseline. `Div.`
means that Astra's implementation materially diverged from the source project.

| # | PR file | Purpose in PR | Exists | Div. | Decision | Risk / rationale |
|---:|---|---|:---:|:---:|---|---|
| 1 | `.github/workflows/analysis-sonarcloud.yml` | Exclude browser-only analysis paths | No | Yes | NOT_NEEDED | Astra has no matching Sonar workflow. Low. |
| 2 | `.github/workflows/build-ubuntu.yml` | Add WASM build conditions | No | Yes | ADAPTED | Separate pinned `build-wasm.yml` avoids disturbing native CI. Medium. |
| 3 | `.github/workflows/build-windows.yml` | Add WASM build conditions | No | Yes | ADAPTED | Portable shell and PowerShell scripts replace source workflow assumptions. Medium. |
| 4 | `browser/include/bitlib/LICENSE` | Vendored Lua bit library | Yes | Yes | REJECTED_AS_UNSAFE | Astra already owns `lbitlib`; duplicating it risks conflicting globals. High. |
| 5 | `browser/include/bitlib/bit_limits.h` | Vendored bit implementation detail | Yes | Yes | REJECTED_AS_UNSAFE | Existing Astra implementation is reused. High. |
| 6 | `browser/include/bitlib/lbitlib.c` | Register a second `bit` module | Yes | Yes | REJECTED_AS_UNSAFE | Browser registers Astra `bit32` as `bit`, without duplicate code. High. |
| 7 | `browser/overlay-ports/abseil/portfile.cmake` | WASM Abseil overlay | No | Yes | NOT_NEEDED | Astra browser target does not link Abseil. Low. |
| 8 | `browser/overlay-ports/abseil/use_pthread.patch` | Patch Abseil for pthread | No | Yes | NOT_NEEDED | No Abseil dependency. Low. |
| 9 | `browser/overlay-ports/abseil/vcpkg.json` | Abseil overlay manifest | No | Yes | NOT_NEEDED | No Abseil dependency. Low. |
| 10 | `browser/overlay-ports/physfs/portfile.cmake` | Build PhysicsFS for WASM | Yes | Yes | ADAPTED | CMake FetchContent pins exact PhysicsFS 3.2.0 commit. Medium. |
| 11 | `browser/overlay-ports/physfs/usage` | Overlay usage metadata | No | Yes | ADAPTED | Replaced by browser deployment/build documentation. Low. |
| 12 | `browser/overlay-ports/physfs/use_pthread.patch` | Compile PhysicsFS with pthread | Yes | Yes | ADAPTED | Target compile options add `-pthread`; no source patch. Medium. |
| 13 | `browser/overlay-ports/physfs/vcpkg-cmake-wrapper.cmake` | Normalize overlay target | Yes | Yes | ADAPTED | Upstream `PhysFS::PhysFS-static` target is linked directly. Low. |
| 14 | `browser/overlay-ports/physfs/vcpkg.json` | PhysicsFS overlay manifest | Yes | Yes | ADAPTED | Pinned FetchContent replaces the browser vcpkg overlay. Medium. |
| 15 | `browser/overlay-ports/protobuf/fix-arm64-msvc.patch` | Protobuf host patch | No | Yes | NOT_NEEDED | Astra browser target has no Protobuf. Low. |
| 16 | `browser/overlay-ports/protobuf/fix-default-proto-file-path.patch` | Protobuf path patch | No | Yes | NOT_NEEDED | No Protobuf dependency. Low. |
| 17 | `browser/overlay-ports/protobuf/fix-static-build.patch` | Protobuf static patch | No | Yes | NOT_NEEDED | No Protobuf dependency. Low. |
| 18 | `browser/overlay-ports/protobuf/fix-utf8-range.patch` | Protobuf dependency patch | No | Yes | NOT_NEEDED | No Protobuf dependency. Low. |
| 19 | `browser/overlay-ports/protobuf/portfile.cmake` | Build Protobuf for WASM | No | Yes | NOT_NEEDED | Avoided an unused dependency tree. Low. |
| 20 | `browser/overlay-ports/protobuf/protobuf-targets-vcpkg-protoc.cmake` | Host protoc targets | No | Yes | NOT_NEEDED | Astra does not generate Protobuf for browser. Low. |
| 21 | `browser/overlay-ports/protobuf/use_pthread.patch` | Patch Protobuf pthread flags | No | Yes | NOT_NEEDED | No Protobuf dependency. Low. |
| 22 | `browser/overlay-ports/protobuf/vcpkg-cmake-wrapper.cmake` | Protobuf target wrapper | No | Yes | NOT_NEEDED | No Protobuf dependency. Low. |
| 23 | `browser/overlay-ports/protobuf/vcpkg.json` | Protobuf overlay manifest | No | Yes | NOT_NEEDED | No Protobuf dependency. Low. |
| 24 | `browser/shell.html` | Canvas, loading and browser boot | Yes | Yes | ADAPTED | Rebuilt with Astra branding, IDBFS, endpoint config, isolation checks and error UI. High. |
| 25 | `mods/game_bot/default_configs/cavebot_1.3/cavebot/actions.lua` | Lua 5.1 string compilation | Yes | Yes | ADAPTED | Applied to Astra's renamed `modules/game_bot` path, preserving LuaJIT branch. Medium. |
| 26 | `mods/game_bot/default_configs/cavebot_1.3/tools.lua` | Lua 5.1 string compilation | Yes | Yes | ADAPTED | Same targeted Lua 5.1/LuaJIT split. Medium. |
| 27 | `mods/game_bot/default_configs/vBot_4.8/cavebot/actions.lua` | Lua 5.1 string compilation | Yes | Yes | ADAPTED | Same targeted Lua 5.1/LuaJIT split. Medium. |
| 28 | `mods/game_bot/default_configs/vBot_4.8/vBot/ingame_editor.lua` | Lua 5.1 string compilation | Yes | Yes | ADAPTED | Same targeted Lua 5.1/LuaJIT split. Medium. |
| 29 | `mods/game_bot/executor.lua` | `loadstring`/`setfenv` on Lua 5.1 | Yes | Yes | ADAPTED | Uses one context compiler helper; native LuaJIT behavior remains. High. |
| 30 | `mods/game_bot/functions/script_loader.lua` | Context-aware Lua 5.1 load | Yes | Yes | ADAPTED | Uses executor-provided loader instead of duplicating unsafe load forms. Medium. |
| 31 | `mods/game_bot/panels/waypoints.lua` | Context-aware Lua 5.1 load | Yes | Yes | ADAPTED | Uses executor-provided loader. Medium. |
| 32 | `modules/corelib/bitwise.lua` | Only newline-at-EOF change | Yes | No | ALREADY_PRESENT | No browser behavior change to port. Low. |
| 33 | `modules/game_cyclopedia/images/bestiary/creatures/Construct.png -> construct.png` | Linux/WASM filename case | No | Yes | NOT_NEEDED | Astra has a different Cyclopedia asset tree; checker found no matching bad reference. Low. |
| 34 | `.../Demon.png -> demon.png` | Filename case | No | Yes | NOT_NEEDED | Divergent/absent asset. Low. |
| 35 | `.../Dragon.png -> dragon.png` | Filename case | No | Yes | NOT_NEEDED | Divergent/absent asset. Low. |
| 36 | `.../Extra_Dimensional.png -> extra_dimensional.png` | Filename case | No | Yes | NOT_NEEDED | Divergent/absent asset. Low. |
| 37 | `.../Fey.png -> fey.png` | Filename case | No | Yes | NOT_NEEDED | Divergent/absent asset. Low. |
| 38 | `.../Giant.png -> giant.png` | Filename case | No | Yes | NOT_NEEDED | Divergent/absent asset. Low. |
| 39 | `.../Human.png -> human.png` | Filename case | No | Yes | NOT_NEEDED | Divergent/absent asset. Low. |
| 40 | `.../Humanoid.png -> humanoid.png` | Filename case | No | Yes | NOT_NEEDED | Divergent/absent asset. Low. |
| 41 | `.../Lycanthrope.png -> lycanthrope.png` | Filename case | No | Yes | NOT_NEEDED | Divergent/absent asset. Low. |
| 42 | `.../Magical.png -> magical.png` | Filename case | No | Yes | NOT_NEEDED | Divergent/absent asset. Low. |
| 43 | `.../Mammal.png -> mammal.png` | Filename case | No | Yes | NOT_NEEDED | Divergent/absent asset. Low. |
| 44 | `.../Plant.png -> plant.png` | Filename case | No | Yes | NOT_NEEDED | Divergent/absent asset. Low. |
| 45 | `.../Reptile.png -> reptile.png` | Filename case | No | Yes | NOT_NEEDED | Divergent/absent asset. Low. |
| 46 | `.../Slime.png -> slime.png` | Filename case | No | Yes | NOT_NEEDED | Divergent/absent asset. Low. |
| 47 | `.../Undead.png -> undead.png` | Filename case | No | Yes | NOT_NEEDED | Divergent/absent asset. Low. |
| 48 | `.../Vermin.png -> vermin.png` | Filename case | No | Yes | NOT_NEEDED | Divergent/absent asset. Low. |
| 49 | `modules/game_cyclopedia/tab/boss_slots/boss_slots.lua` | Remove UTF-8 BOM | No | Yes | NOT_NEEDED | Astra uses `mods/game_cyclopedia/classes`; repository-wide checker is clean. Low. |
| 50 | `modules/game_cyclopedia/tab/bosstiary/bosstiary.lua` | Remove UTF-8 BOM | No | Yes | NOT_NEEDED | Divergent path; checker is clean. Low. |
| 51 | `modules/game_cyclopedia/tab/charms/charms.lua` | Remove UTF-8 BOM | No | Yes | NOT_NEEDED | Divergent path; checker is clean. Low. |
| 52 | `modules/game_cyclopedia/tab/house/house.lua` | Remove UTF-8 BOM | No | Yes | NOT_NEEDED | Divergent path; checker is clean. Low. |
| 53 | `modules/game_cyclopedia/tab/map/map.lua` | Remove UTF-8 BOM | No | Yes | NOT_NEEDED | Divergent path; checker is clean. Low. |
| 54 | `modules/game_cyclopedia/utils.lua` | BOM/punctuation normalization | Yes | Yes | ALREADY_PRESENT | Astra counterpart is BOM-free valid UTF-8; unrelated prose changes omitted. Low. |
| 55 | `modules/game_interface/widgets/statsbar.lua` | Whitespace-only change | Yes | Yes | NOT_NEEDED | No browser effect. Low. |
| 56 | `modules/game_playerdeath/playerdeath.lua` | UI resource case fix | Yes | Yes | ALREADY_PRESENT | Astra imports lowercase `deathwindow` and uses a different widget flow. Low. |
| 57 | `modules/game_quickloot/quickloot.lua` | Remove UTF-8 BOM | Yes | Yes | ALREADY_PRESENT | Astra file is already BOM-free. Low. |
| 58 | `modules/game_shaders/shaders/fragment/bloom.frag` | WebGL loop declarations | No | Yes | NOT_NEEDED | Shader is absent; all Astra shaders were enumerated and no matching loop exists. Medium. |
| 59 | `src/CMakeLists.txt` | Detect/configure browser target | Yes | Yes | ADAPTED | Implemented in root/framework CMake without desktop libraries or absolute paths. High. |
| 60 | `src/client/protocolgame.cpp` | Route game connection and rewrite 7172 to 443 | Yes | Yes | REJECTED_AS_UNSAFE | Port rewrite removed; configurable resolver is transport-level and protocol bytes stay unchanged. High. |
| 61 | `src/framework/const.h` | Report WASM architecture | Yes | No | PORTED | Adds `BUILD_ARCH=wasm32`. Low. |
| 62 | `src/framework/core/application.cpp` | Browser network polling/platform shutdown | Yes | Yes | ADAPTED | Same Connection API is retained; restart reloads, native Boost.Process remains guarded. High. |
| 63 | `src/framework/core/graphicalapplication.cpp` | Browser-compatible main loop | Yes | Yes | ADAPTED | Surgical loop preserves Astra draw pools, caches, worker and dispatcher topology. Critical. |
| 64 | `src/framework/core/graphicalapplication.h` | Browser loop state/API | Yes | Yes | ADAPTED | Adds only Emscripten-specific tick/state declarations. Medium. |
| 65 | `src/framework/core/resourcemanager.cpp` | Browser user directory | Yes | Yes | ADAPTED | `/astraclient` package plus IDBFS-backed `/user`; native paths unchanged. High. |
| 66 | `src/framework/graphics/glutil.h` | GLES includes for browser | Yes | No | ALREADY_PRESENT | Astra already selected GLES headers under Emscripten. Low. |
| 67 | `src/framework/luaengine/luainterface.cpp` | Browser Lua and bit module | Yes | Yes | ADAPTED | Official Lua 5.1.5 and Astra `lbitlib`; `bit` aliases `bit32`. High. |
| 68 | `src/framework/luaengine/luainterface.h` | Lua 5.1 headers | Yes | Yes | ADAPTED | CMake exposes official Lua headers; no vendored fake LuaJIT define. Medium. |
| 69 | `src/framework/luafunctions.cpp` | Browser bindings / exclude native server | Yes | Yes | ADAPTED | Adds minimal `isBrowser`; native Server binding is omitted only on WASM. Medium. |
| 70 | `src/framework/net/connection.cpp` | Exclude native TCP transport | Yes | Yes | ADAPTED | Browser binary WebSocket stream is implemented inside Astra Connection; native Asio body is intact. Critical. |
| 71 | `src/framework/net/connection.h` | Select browser connection API | Yes | Yes | ADAPTED | One API/type avoids protocol-wide substitutions and preserves weak ownership. High. |
| 72 | `src/framework/net/declarations.h` | Browser connection pointer alias | Yes | Yes | ALREADY_PRESENT | Reusing `ConnectionPtr` works for both target-specific implementations. Low. |
| 73 | `src/framework/net/httplogin.cpp` | Fetch-based browser login | No | Yes | ADAPTED | Astra's public `g_http` Get/Post/Download API uses asynchronous Fetch instead. High. |
| 74 | `src/framework/net/httplogin.h` | Browser login state/errors | No | Yes | NOT_NEEDED | Astra has no LoginHttp class; duplicating it would bypass existing Lua HTTP lifecycle. Medium. |
| 75 | `src/framework/net/protocol.cpp` | Integrate browser transport | Yes | Yes | ADAPTED | Only native proxy/local shortcut is guarded; recorder/player/checksum/XTEA/compression remain. Critical. |
| 76 | `src/framework/net/protocol.h` | Store alternate connection type | Yes | Yes | ALREADY_PRESENT | Common Connection API makes an alternate pointer type unnecessary. Medium. |
| 77 | `src/framework/net/server.cpp` | Exclude TCP listener on browser | Yes | No | ADAPTED | Source is excluded from WASM and Lua binding is guarded; native target is unchanged. Low. |
| 78 | `src/framework/net/webconnection.cpp` | Browser WebSocket transport | No | Yes | ADAPTED | Implemented in Connection to minimize churn and preserve Astra consumers. Critical. |
| 79 | `src/framework/net/webconnection.h` | Browser transport contract | No | Yes | ADAPTED | Conditional Connection internals expose the existing contract. High. |
| 80 | `src/framework/platform/browserplatform.cpp` | Browser-safe OS/platform services | No | Yes | PORTED | Adapted to Astra's smaller Platform interface; unsafe native operations return controlled values. Medium. |
| 81 | `src/framework/platform/browserwindow.cpp` | WebGL/input/window backend | No | Yes | ADAPTED | Rewritten for Astra input arrays, dispatcher rules, explicit swap and virtual keyboard. Critical. |
| 82 | `src/framework/platform/browserwindow.h` | BrowserWindow contract | No | Yes | ADAPTED | Implements every Astra PlatformWindow virtual. High. |
| 83 | `src/framework/platform/platform.h` | Browser detection | Yes | Yes | ADAPTED | Adds only `isBrowser()` rather than importing source device enums. Low. |
| 84 | `src/framework/platform/platformwindow.cpp` | Select BrowserWindow | Yes | No | PORTED | Replaces the incomplete SDL browser selection with one backend. Medium. |
| 85 | `src/framework/platform/platformwindow.h` | Make cursor load overrideable | Yes | Yes | ALREADY_PRESENT | Astra BrowserWindow uses existing cursor loader hook and internal image callback. Low. |
| 86 | `src/framework/platform/unixplatform.cpp` | Exclude Unix implementation on WASM | Yes | No | ALREADY_PRESENT | Guard existed in Astra baseline. Low. |
| 87 | `src/framework/platform/x11window.cpp` | Exclude X11 on WASM | Yes | No | ALREADY_PRESENT | Guard existed; browser CMake also excludes X11 source. Low. |
| 88 | `src/framework/ui/uitextedit.cpp` | Open mobile virtual keyboard | Yes | Yes | ADAPTED | Calls BrowserWindow editor after normal cursor/selection handling. Medium. |
| 89 | `src/protobuf/CMakeLists.txt` | Add pthread to Protobuf | No | Yes | NOT_NEEDED | No Astra browser Protobuf target. Low. |
| 90 | `vcpkg.json` | Exclude LuaJIT on wasm32 | Yes | No | ADAPTED | LuaJIT and Boost.Process are conditional; native dependency set remains. High. |

## Additional Astra-only findings

The source diff could not cover Astra-only code. The port also audited and
implemented Astra's `g_http` updater/image/WebSocket uses, internal proxy no-op,
PacketPlayer/PacketRecorder preservation, optimized draw loop, custom shader
tree, downloadable resource cache, and 919 browser-loaded text assets. Twenty
legacy Windows-1252/BOM assets were normalized, and three sound references were
corrected to exact case.
