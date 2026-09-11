# Browser/WebAssembly port report

Date: 2026-08-29
Target repository: `Mateuzkl/AstraClient`
Target base: `efaaea81a382ec6b3f89e52fa67ac2a5d527c450`
Reference: `opentibiabr/otclient` PR #894, merge commit
`0700333f639e9221561344b3f60ec3f4eabd8b92`

## Result

AstraClient now has a dedicated Emscripten/WebAssembly browser target. The
implementation was adapted to Astra's architecture instead of applying the
reference PR as a raw patch. It preserves the native protocol framing,
recording, proxy and optimized render-loop code paths while adding WebGL 2,
browser input/window integration, binary WebSocket transport, Fetch-based HTTP,
Lua 5.1.5, IDBFS persistence and reproducible browser builds.

The complete source-PR disposition is recorded in
`BROWSER_PORT_AUDIT.md`. It contains exactly 90 rows, including intentionally
rejected or unnecessary reference changes.

## Validated toolchain

- Emscripten 6.0.8 (`aeb67926e7de656da38bc807d83050af93578758`)
- CMake 3.31.6
- Ninja 1.13.0
- Lua 5.1.5, fetched from a pinned archive and verified by SHA-256
- PhysicsFS, fetched from pinned commit
  `eb3383b3fe267fd85264b80ca9756e200d8cd485`

The repository contains PowerShell and shell entry points, and CI uses pinned
GitHub Action commit SHAs. There are no developer-specific dependency paths.

## Validation performed

| Check | Result |
| --- | --- |
| Fresh Release configure/build from an empty build directory | PASS, 204 Ninja steps |
| Reproducible Lua 5.1 parser adaptation during fresh dependency fetch | PASS |
| Browser asset UTF-8/BOM and exact-case checker | PASS, 919 text assets and 4,409 references |
| WebGL context | PASS, WebGL 2 / OpenGL ES 3.0 reported by Chromium |
| Cross-origin isolation development server | PASS |
| Browser bootstrap and module loading | PASS |
| Login interface rendering | PASS |
| Runtime stability after bootstrap | PASS, no new console errors during a 12-second observation window |
| PR #894 file-by-file audit | PASS, 90/90 rows |
| `git diff --check` | PASS |

An earlier Debug build also completed during development. The final clean build
recorded here is Release and includes the final Lua parser and font bootstrap
fixes.

## Release artifacts

Generated in `build-wasm-clean-release/dist` (build directories are ignored):

| File | Bytes | SHA-256 |
| --- | ---: | --- |
| `astraclient.html` | 4,351 | `3905bc3c4182e3931185ab4288f2ba6c48d91d01d50f4146f6354f89971856ec` |
| `astraclient.js` | 726,481 | `a20bc4390f4d2be0c27ab5596a2c9d147497a95f5ff1dd03cb18aba6bd19d964` |
| `astraclient.wasm` | 5,612,118 | `224f7c5bfc612795b1eab6040ecb53009ad0e7b7e9a4cc8b1e3d7739ce3a88cb` |
| `astraclient.data` | 319,035,744 | `e1ede2cdb296a696795ce057a5dbe6b7b0bdff0ba49c1a022baf12f1e10e6c54` |

The complete first delivery intentionally preloads Astra's assets. The 319 MB
data package is functional but too large for an ideal public deployment. Asset
splitting, compression and a versioned CDN/cache are the recommended next
performance phase.

## Not yet integration-tested

The following require an actual compatible login API, a binary WebSocket-to-TCP
bridge, TFS credentials and game data, which were not available for this pass:

- real account login and character selection;
- complete protocol/map entry and gameplay;
- logout, character switching and repeated reconnect stress testing;
- production CORS/TLS/redirect behavior against the intended domains;
- persistence of every user-facing setting across multiple real sessions;
- final native Windows/Linux and Android regression builds after this port.

These items are not claimed as passing. The transport, HTTP and lifecycle paths
are implemented and compile, but end-to-end server validation remains the next
test phase.

## Deployment requirements

The pthread build requires `SharedArrayBuffer`, so the web server must return
cross-origin isolation headers. Game traffic must use a binary WebSocket bridge;
browsers cannot connect directly to the TFS TCP port. HTTPS deployments must use
`wss://` and HTTPS APIs, with correct CORS configuration. See
`docs/browser-wasm.md` and `browser/nginx.conf.example` for the build, endpoint
and deployment configuration.
