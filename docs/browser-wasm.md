# AstraClient in the browser

For WSL build and local TFS test commands in Portuguese,
see [Compilar e testar localmente](browser-local-test-pt.md).

The browser target is a WebAssembly/WebGL 2 build with Emscripten pthreads.
It runs logic and graphics on one application pthread, uses Lua 5.1.5 instead
of LuaJIT, persists `/user` through IndexedDB, and transports the Tibia byte
stream inside binary WebSocket frames. The native rendering/logic split is
unchanged. Browser thread ownership is initialized in `main()` before the
framework starts, because Emscripten static initialization runs on another
thread with `PROXY_TO_PTHREAD`.

## Toolchain

The CI-pinned toolchain is Emscripten **6.0.8**. CMake 3.24 or
newer, Ninja, Python 3, Git and a C/C++ host toolchain are also required. The
browser target does not use vcpkg; Lua 5.1.5 and PhysicsFS are fetched from
pinned upstream sources by CMake.

```bash
git clone https://github.com/emscripten-core/emsdk.git
cd emsdk
git checkout 6.0.8
./emsdk install 6.0.8
./emsdk activate 6.0.8
source ./emsdk_env.sh

cd /path/to/AstraClient
./browser/build-wasm.sh Release
```

PowerShell after activating `emsdk_env.ps1`:

```powershell
./browser/build-wasm.ps1 -BuildType Release
```

Equivalent manual commands:

```bash
emcmake cmake --fresh -S . -B build-wasm-release -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build-wasm-release --parallel
python tools/check_browser_assets.py
```

Extract the Git LFS `data/things/860.rar` before configuring (CI does this
automatically). Do not overwrite a customized local pack: extract to a separate
directory and pass `-DASTRA_WASM_THINGS_DIR=/path/to/extracted/860` to CMake, or
`-ThingsDirectory` to the PowerShell build script. The shell build script accepts
extra CMake options after the build type and build directory arguments.

Artifacts are written to `build-wasm-release/dist/`. A Debug build enables
Emscripten assertions, safe heap checks and stack overflow checks.

## Run locally

Do not open the HTML with `file://`. The pthread build needs `SharedArrayBuffer`
and therefore a cross-origin-isolated HTTP response:

```bash
python browser/serve.py build-wasm-release/dist --port 8000
```

Open `http://127.0.0.1:8000/astraclient.html`. The server adds:

```http
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
Cross-Origin-Resource-Policy: same-origin
```

The shell stops with a visible error when WebGL 2 or cross-origin isolation is
missing.

## Endpoint configuration

TCP sockets are unavailable to browser code. A game connection must go through
a binary-transparent WebSocket bridge:

```text
AstraClient WASM -> ws:// or wss:// WebSocket bridge -> TCP TFS port
```

There is no special-case rewrite from port 7172 to 443. The game endpoint is
configured at deployment time in `config.js`, shipped beside the generated
HTML. **Endpoint query parameters are ignored**, so opening a crafted URL
cannot redirect the account/password to a different server. Only edit the
deployment-owned configuration (not URL parameters or untrusted input).

Classic TFS uses separate TCP login (7171) and game (7172) ports. A bridge to
7172 alone cannot service the initial protocol login. Configure two routes:

The `ws://` endpoints below are **local HTTP development only**. Production
deployments must serve the page over HTTPS and use `wss://` endpoints.

```js
window.ASTRA_CONFIG = {
  websocketOverrides: {
    '127.0.0.1:7171': 'ws://127.0.0.1:7174/',
    '127.0.0.1:7172': 'ws://127.0.0.1:7173/'
  }
};
```

The keys must match the login host in `init.lua` and the world host/port
advertised by TFS. If TFS advertises another IP/name, add that exact game
authority as well. Each route is independent; do not route both TCP ports to
the same game-only bridge. An explicit `ws://`/`wss://` URL keeps its own port,
path and query unless the trusted configuration deliberately overrides them.

For production, `browser/nginx.conf.example` exposes two same-origin routes:

```js
window.ASTRA_CONFIG = {
  title: 'AstraClient',
  websocketOverrides: {
    '127.0.0.1:7171': '/login',
    '127.0.0.1:7172': '/game'
  },
  loginUrl: 'https://api.example.com/login',
  httpOverrides: {
    'http://legacy-api.example.com/': 'https://api.example.com/'
  }
};
```

Relative WebSocket routes use `wss` on HTTPS and `ws` otherwise. The older
`game: { scheme, host, port, path }` override remains available for a deployment
with a single multiplexed bridge or HTTP login; it affects **all** protocol
connections, not only gameplay. Allowed schemes, ports and credentials are
validated before starting a request; URL-embedded credentials are not accepted.

`loginUrl` replaces requests whose final path is `login` (optionally with a
file extension). `httpOverrides` applies longest-prefix URL rewrites to all
HTTP operations, including updater and asset calls. On HTTPS, `http://` and
`ws://` requests are rejected with a controlled mixed-content error before the
browser request starts.

For a local bridge, one possible setup is:

This example uses local, unencrypted bridges only. Production clients must
connect through `wss://` TLS routes, not directly to these `ws://` listeners.

```bash
websockify 7173 127.0.0.1:7172
websockify 7174 127.0.0.1:7171
```

Run these as separate processes and use the local `config.js` above. In
production, terminate TLS at nginx and proxy `/game` and `/login` to their
respective bridges. The example includes isolation headers, WebSocket upgrade
settings and preserves the default JavaScript MIME mapping under `nosniff`.

## HTTP, CORS and credentials

Cross-origin login/API servers must allow the page origin through CORS and must
handle `OPTIONS` preflight for JSON posts. Redirect targets need the same CORS
policy. The client does not disable browser security and does not implicitly
send credentials; deploy same-origin endpoints or configure CORS deliberately.
An HTTPS page must use HTTPS APIs and `wss://` game transport.

## Persistent files

The packaged application is read-only under `/astraclient`. User-writable data
uses `/user`, mounted as IDBFS. The initial IndexedDB sync completes before
`main()` starts. Changes are flushed every 15 seconds and when the page becomes
hidden or is being left. Browser storage can still be removed by the user,
private-browsing policy, or storage eviction.
Application-triggered reload waits for the flush callback (and resyncs newer
writes if a periodic flush was already running). If persistence fails, it logs
the error and still reloads. Closing a tab cannot guarantee an async flush.

## Assets and deployment

The bundle preloads `init.lua`, `data/` (excluding the complete `things` tree),
`layouts/`, `mods/`, `modules/` and only the selected 8.60 DAT/SPR pack. Backups,
logs and RAR archives are excluded. Additional packs must be selected explicitly,
not shipped as duplicate sprites. The launcher uses IndexedDB in the pinned
SDK's `EM_PRELOAD_CACHE` format, preserving existing installations. SHA-256
chunk identities and total lengths come from `asset-manifest.json`. Play reads
and verifies chunks into one package buffer, supplied through Emscripten's
public `getPreloadedPackage` hook; the SDK must not perform a second cache read.
`Module.locateFile` resolves artifacts relative to the HTML, so the
whole `dist/` directory can be hosted in a subdirectory. Keep all generated
files together, including `config.js` and `runtime.js`, and preserve their exact
filename case. Include `launcher.js`, `launcher.css`, `asset-cache.js`,
`launcher-background.png` and `asset-manifest.json`. The shell and packaged assets are link dependencies, so an
incremental build updates the bundle after edits.

The initial package is intentionally complete rather than lazy-loaded. For a
large production deployment, a follow-up can split optional assets behind a
versioned CDN/cache after measuring startup and runtime behavior.

The Astra Web launcher loads before the WASM engine. Install persists verified
game data; Update refreshes the manifest and reinstalls it; Uninstall removes
only this deployment's asset entries, not `/user` settings. Play installs on
demand or uses verified cached data. If storage is unavailable or quota is
exceeded, Play can use a verified network package for the current session.
Partial/corrupt entries are never marked installed. Interrupted downloads can
be retried; the complete package is still required before engine startup.

### Local diagnostics and measurements

Use **Web options** (bottom right) → **Performance diagnostics**, or the panel's
close button, to enable/disable diagnostics before or during play. The preference
is saved locally; production defaults to off. A trusted `config.js` can set
`performance: true` as its initial default. Nothing is sent to a telemetry server.

`launcherMs` measures launcher readiness. `cacheReadMs` and `downloadMs` measure
package preparation. `startupMs` is engine start → first client frame, while
`playToFirstFrameMs` also includes verification/download. `firstFrameMs` includes
time the player spent on the launcher before clicking Play, so it is not a pure
startup benchmark. `wasmReadyMs` separates runtime/FS preparation from
`clientInitMs` (application, graphics, Lua/modules and the first draw); this is
not a Lua-only profiler. FPS/frame percentiles describe a bounded sample, not
total session CPU.

`wasmHeapCapacityMiB` is the linear memory capacity; `wasmMallocAllocatedMiB`
comes from the allocator's live allocation counter. Neither includes JS-owned
preload data, GPU textures, stacks or the entire browser process. `lastFrameVertices`
counts vertices; `lastFrameGlDrawCalls` counts the painter's actual `glDrawArrays`
calls, including per-color splits. It is not the vertex counter previously
mislabeled as draw calls. Keep the 768 MiB initial memory until representative
long-session tests justify changing it.

Generate reproducible raw/group and gzip measurements without changing assets:

```bash
python3 tools/browser_manifest.py build-wasm-release/dist --compression-report
```

The existing 64 MiB chunks are the SDK's persistent storage format, not an
unbounded hot-memory LRU. The launcher retains one complete package plus at most
one cache chunk while preparing Play; installing alone streams one chunk at a
time. Lazy SPR access, optional-module deferral and new renderer/atlas caches
remain separate, profile-driven work, not part of this safe launcher change.

## Current platform behavior

- WebGL 2 is required; desktop OpenGL, X11, GLEW and DirectX are not linked.
- Sound is off by default for the browser target and has not been certified.
- Native `PacketPlayer`, `PacketRecorder`, Boost.Asio connections and the
  internal proxy remain unchanged. The internal proxy is a safe no-op only in
  the browser build.
- `Application::restart()` reloads the page in the browser; process spawn and
  native filesystem/window operations are unavailable.
- Generic Astra HTTP WebSockets use browser WebSockets. Game WebSockets ignore
  textual frames and enforce a bounded byte-stream buffer.

The browser client can be fully integration-tested only against a compatible
login API, WebSocket bridge and TFS instance. Build/startup tests alone do not
prove game login or protocol correctness.

## Focused regression checks

```bash
node --test browser/tests/runtime.test.cjs
python3 tools/check_browser_assets.py
em++ -std=c++17 -I src browser/tests/websocket_callbacks.cpp \
  -lwebsocket.js --pre-js browser/tests/mock-websocket.js \
  -sENVIRONMENT=node -sSINGLE_FILE=1 -sASSERTIONS=1 \
  -o build-wasm-release/websocket-test.js
node build-wasm-release/websocket-test.js
em++ -std=c++17 -I src browser/tests/rsa.cpp -sUSE_BOOST_HEADERS=1 \
  -sENVIRONMENT=node -sSINGLE_FILE=1 -sASSERTIONS=1 \
  -o build-wasm-release/rsa-test.js
node build-wasm-release/rsa-test.js
```

These exercise the actual browser endpoint/persistence helpers, including
separate login/game routing, malicious query parameters, explicit URL and IPv6
handling, mixed-content rejection, async reload and overlapping flushes. The
C++ check uses the actual callback teardown helper and the pinned Emscripten
WebSocket library with a Node-only socket fixture; it checks late events after
close/delete and socket-handle reuse. These are not a substitute for a real
login/gameplay session.
