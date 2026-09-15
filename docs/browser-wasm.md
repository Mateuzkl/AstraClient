# AstraClient in the browser

The browser target is a WebAssembly/WebGL 2 build with Emscripten pthreads.
It keeps AstraClient's native rendering/logic split, uses Lua 5.1.5 instead of
LuaJIT, persists `/user` through IndexedDB, and transports the Tibia byte stream
inside binary WebSocket frames.

## Toolchain

The validated and CI-pinned toolchain is Emscripten **6.0.8**. CMake 3.20 or
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
configured at deployment time. Query parameters are convenient for testing:

```text
astraclient.html?gameScheme=ws&gameHost=127.0.0.1&gamePort=7173&gamePath=/
astraclient.html?gameScheme=wss&gameHost=play.example.com&gamePort=443&gamePath=/game
```

Supported parameters are `gameScheme`, `gameHost`, `gamePort`, `gamePath` and
`loginUrl`. `gameScheme=auto` selects `wss` on an HTTPS page and `ws` otherwise.
Production configuration can set `window.ASTRA_CONFIG` in `browser/shell.html`
before building:

```js
window.ASTRA_CONFIG = {
  title: 'AstraClient',
  game: { scheme: 'wss', host: 'play.example.com', port: 443, path: '/game' },
  loginUrl: 'https://api.example.com/login',
  httpOverrides: {
    'http://legacy-api.example.com/': 'https://api.example.com/'
  }
};
```

`loginUrl` replaces requests whose final path is `login` (optionally with a
file extension). `httpOverrides` applies longest-prefix URL rewrites to all
HTTP operations, including updater and asset calls. On HTTPS, `http://` and
`ws://` requests are rejected with a controlled mixed-content error before the
browser request starts.

For a local bridge, one possible setup is:

```bash
websockify 7173 127.0.0.1:7172
```

Then use the first local URL above. In production, terminate TLS at nginx and
proxy `/game` to the bridge. `browser/nginx.conf.example` includes the required
isolation headers and WebSocket upgrade settings.

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

## Assets and deployment

The initial implementation preloads `init.lua`, `data/`, `layouts/`, `mods/`
and `modules/` into one `.data` package and enables the Emscripten preload
cache. `Module.locateFile` resolves artifacts relative to the HTML, so the
whole `dist/` directory can be hosted in a subdirectory. Keep all generated
files together and preserve their exact filename case.

The initial package is intentionally complete rather than lazy-loaded. For a
large production deployment, a follow-up can split optional assets behind a
versioned CDN/cache after measuring startup and runtime behavior.

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
