# Web mobile, cache and remembered credentials

The changes preserve native desktop authentication and asset formats. They do not
publish a new deployment or modify the production server.

## Behaviour

- Mobile layouts inherit base fonts/styles, then load their overrides. TopMenu
  fails with a meaningful diagnostic if its base style is missing, and discards
  delayed callbacks after teardown/recreation.
  Console and miniwindow overrides inherit the current widget trees; obsolete
  copies missing read-only chat controls and additional window buttons were removed.
- Browser connection errors return to the login inside the running client after
  protocol teardown, without restarting the page or asset downloader. Desktop
  continues returning to the character list. Cast and waiting-list handling remain
  separate.
- Cache keys are stable per deployment folder. Existing SDK keys containing build
  paths can be reused after integrity verification. Removal is limited to this
  deployment; an obsolete alias cannot resurrect an uninstalled package. Update
  checks content identity before requesting another download.
- Remember Password is opt-in and only saves successful password logins in a
  separate AES-256-GCM IndexedDB vault. OAuth, 2FA, session keys and Web autologin
  are not persisted. Settings remain scrubbed. Uncheck the option or choose
  **Web options > Forget saved login** to remove the local entry. After Forget,
  uncheck/recheck the option if you want to enable saving again.
- Vault errors are non-fatal and visible. Passwords remain in memory while needed
  for authentication. Local encryption is not protection against malicious
  same-origin code, a compromised browser profile or a compromised device.

## Repeatable checks

From the repository root:

```sh
node --test browser/tests/*.test.cjs
luajit .github/tests/mobile_styles.lua
luajit .github/tests/web_credentials.lua
luajit .github/tests/web_disconnect.lua
luajit .github/tests/module_lifecycle.lua
luajit .github/tests/startup_lifecycle.lua
python3 tools/check_browser_assets.py
```

Build with the pinned Emscripten 6.0.8 toolchain using `browser/build-wasm.sh` or
`browser/build-wasm.ps1`. To inspect real mobile startup without modifying the
production bundle:

```sh
python3 browser/tests/smoke_server.py /absolute/path/to/built/dist
```

Open `http://127.0.0.1:8014/mobile.html` for the mobile layout or
`http://127.0.0.1:8014/astraclient.html` for desktop. These are local startup tests,
not an iOS Safari certification or a production login/load test. In Web options,
performance diagnostics distinguish network download bytes from cached reads.

## Deployment acceptance

Publish the entire rebuilt dist together, including `credentials.js`, not just
the HTML or Lua source. Preserve deployment-specific `config.js` endpoints,
branding, CSP/COOP/COEP and HTTPS/WSS settings. Do not copy development endpoints
over production settings.

On a physical iPhone/Safari and Android device, verify first Play, repeat Play,
unchanged Update, failed/re-established connection, saved login after closing the
tab, and Forget after reopening. Site data can still be removed by the user,
private browsing, storage quota or browser eviction. No client-side cache can
guarantee persistence against those conditions. The full asset package and WASM
heap still require substantial memory; these changes do not claim to eliminate
all low-memory terminations on mobile.

## Recorded validation — 14 October 2026

- 80/80 Node tests passed under the pinned SDK runtime, including real Nginx
  TLS/WSS, Origin checks and production headers; no skipped tests in that run.
- Production Lua tests passed for mobile styles/TopMenu, Web credentials,
  disconnect routing, startup/module lifecycle, indexed SPR and Cam Viewer.
- The actual C++ credential bridge passed 200 main-thread UTF-8 round trips under
  pthreads and SAFE_HEAP. SDK transport/cancellation tests and native ASan/UBSan
  message-queue/Lua-parser tests passed, including 6,000 invalid Lua parses.
  The non-Web platform implementation also compiled with warnings treated as errors.
- Release Web build passed its source/byte audit: 5,036 files, 631,204,152 bytes.
  Text/path validation checked 932 textual assets and 4,387 static references.
- The browser-control skill exposed an additional real startup failure after
  TopMenu: obsolete mobile ConsolePanel lacked the current readOnly widget. The
  obsolete console/miniwindow copies were replaced with scalar inherited styles.
  Retesting reached the login screen with no warning/error console entries in
  Chromium, both in the mobile layout at 393 x 852 and the normal desktop layout.
- Real repeat mobile Play reported cacheHit=true, trusted-installed cache mode,
  631,204,152 bytes read from IndexedDB and downloadBytes=0. Unchanged Update
  displayed "No download needed". No production credentials were entered.

These results do not establish physical iOS/Safari compatibility, a complete
native-desktop regression test, or a successful production world login/reconnect.
No production deployment was performed as part of this validation.
