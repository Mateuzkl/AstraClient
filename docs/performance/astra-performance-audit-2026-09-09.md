# AstraClient performance audit — 2026-09-09

## Scope and baseline

- Baseline revision: `34b4af86f405c6aa65e85483ad3bb01acbfaf455`
- Working branch: `optimize-astra-performance`
- Primary desktop: Windows 11 x64, DirectX/ANGLE, Intel UHD Graphics
- Production package used for measurements: `data.zip`, 5,060 files,
  824,431,138 uncompressed bytes and 513,427,041 compressed bytes
- Historical benchmark evidence from the supplied package was treated as a
  starting point and rechecked against the current branch before keeping a
  change.

## Kept changes

| Area | Finding | Resolution | Status |
| --- | --- | --- | --- |
| DAT/SPR lifecycle | `game_things.load()` had no identity-aware successful-load cache, allowing expensive identical native reloads. | Cache only a fully successful identity (asset version, resolved DAT/SPR paths, asset mode and resource generation); require native DAT and SPR state to remain valid. | Kept |
| Resource archive | Desktop retained the complete compressed `data.zip` buffer after mounting it from memory. | Mount an external desktop archive directly through PhysFS; keep Android and embedded/encrypted fallback paths memory-backed. | Kept |
| Resource invalidation | A same virtual path can refer to new contents after an updater remount. | Expose a monotonic resource generation to Lua and include it in the asset identity. | Kept |
| Actionbar startup | 450 slot widgets were created synchronously even though only 50 belonged to the visible bar. | Create visible slots immediately and prewarm hidden slots in batches of five after visual readiness; cancel prewarm and synchronously complete all bars on login so hidden-bar hotkeys still work. | Kept |
| Shader diagnosis | Shader source reads and GPU compile/link work were not separable in normal logs. | Add opt-in per-program source identity/hash, source-read timing and compile/link timing under `--profile-performance`; default startup has no timing/log work. | Kept |
| Cavebot debug HUD | Waypoint markers were destroyed and recreated every 750 ms. | Retain markers by tile identity and update only changed layout, text and colors; remove only stale owned widgets. | Kept |
| Packaging | Release archives had no automated nested-root/duplicate-name guard. | Add source/ZIP inventory validation, largest-file reporting and large duplicate-payload reporting; fail on duplicate names or suspicious nested roots. | Kept |
| Lua/UI CI | Lua-only and OTUI/content paths could bypass meaningful checks. | Add LuaJIT syntax validation, the deterministic asset lifecycle test, package validation and whitespace checks. | Kept |

No feature was removed. No file was classified as dead or deleted because the
static reference evidence was not sufficient to prove safe removal.

## Asset regression matrix

The headless Lua test executes the real `modules/game_things/things.lua` with
deterministic native/resource doubles.

| Scenario | Result | Evidence |
| --- | --- | --- |
| First load | PASS | DAT and SPR each load once. |
| Same-profile relog/reconnect | PASS | Twenty repeated same-identity calls do not reload either native asset. |
| Character switch using same assets | PASS | Same identity is reused while feature refresh state is restored. |
| Different DAT/SPR path and version | PASS | Identity change reloads and temporarily selects the asset version. |
| Return from another version to 860 | PASS | Returning to the default path reloads 860 and preserves protocol version. |
| Resource remount at same path | PASS | Generation change invalidates the identity and reloads both assets. |
| Native unload/invalidation | PASS | Missing native SPR state forces a full reload. |
| Failed DAT load and retry | PASS | Partial/failed attempts are never cached. |
| Failed SPR load and retry | PASS | Partial/failed attempts are never cached. |
| U32 fallback | PASS | Successful fallback is remembered and its feature is restored on reuse. |
| Modern `.otfi` mode | PASS | U32, idle-animation and enhanced-animation flags are restored. |
| Module reload | PASS | A reloaded module conservatively starts without trusting an old Lua identity. |
| Live authenticated logout/relog | NOT TESTED | No test account/credentials were used in this audit. |
| Android device lifecycle | NOT TESTED | Package path was checked, but no Android device was available. |

Run the deterministic test with:

```sh
luajit tools/tests/game_things_test.lua modules/game_things/things.lua
```

## Performance results

### Process to first window and memory

The same production package and DirectX executable path were used. Memory was
sampled 500 ms after the first window handle appeared.

| Variant | Raw window times (ms) | Min / median / max (ms) | Median working set | Median private bytes |
| --- | --- | --- | --- | --- |
| Baseline: memory archive, eager Actionbar | 5,158; 4,768; 5,314 | 4,768 / 5,158 / 5,314 | 1,593.6 MB | 1,570.5 MB |
| Direct disk mount only | 5,560; 4,894; 4,826 | 4,826 / 4,894 / 5,560 | 1,106.0 MB | 1,080.1 MB |
| Final: direct mount + staged hidden Actionbar | 4,125; 3,863; 3,768; 3,709; 3,715 | 3,709 / 3,768 / 4,125 | 1,084.1 MB | 1,057.1 MB |

Against the starting implementation, the direct archive mount removed about
487.6 MB (30.6%) from the median working set and about 490.4 MB (31.2%) from
median private bytes. The final five-run startup median was 1,390 ms (27.0%)
lower than the three-run starting median. These wall-clock samples remain
hardware-sensitive and are evidence, not a CI threshold.

### Actionbar exclusive profile

Instrumentation is disabled by default and enabled with
`--profile-performance`. It emits one aggregate line per lifecycle phase.

| Phase | Before | After |
| --- | ---: | ---: |
| Blocking Actionbar initialization | 538.723 ms | 78.827 ms |
| Style import | 0.790 ms | 0.747 ms |
| Signal connection | 0.014 ms | 0.010 ms |
| Actionbar container creation | 28.422 ms | 25.465 ms |
| Immediate slot widget creation | 496.125 ms / 450 widgets | 50.267 ms / 50 widgets |
| Hidden login-screen prewarm | N/A | 400 widgets in batches of five; 639.860 ms aggregate work after first readiness |

The measured bottleneck was widget construction, not styles, settings parsing
or signal wiring. Hidden bars are still fully materialized before online slot
restoration/hotkey binding completes. If the player logs in before background
prewarm finishes, `online()` cancels it and completes the remaining slots.

### Shader experiment (rejected)

The current shader inventory contains 34 logical registrations and 19 unique
source pairs; one text pair is reused by 16 logical materials. A candidate
shared compiled-shader-object cache retained independent painter programs,
uniforms and textures, but did not improve the real endpoint:

- before raw window times: 6,724; 4,169; 4,161; 4,101; 4,927 ms
- candidate raw window times: 4,711; 4,403; 4,224; 4,289; 4,189 ms
- median changed from 4,169 ms to 4,289 ms (2.9% worse)

The candidate was reverted. Blanket shader deferral was not attempted because
the supplied benchmark already showed that it worsened visual readiness.

### Package inventory

- 5,060 files
- 824,431,138 uncompressed bytes
- 513,427,041 compressed bytes
- no duplicate ZIP names
- no nested `data/data`, `modules/modules`, `mods/mods` or `layouts/layouts`
- one pre-existing exact payload alias is reported, not deleted:
  `data/images/bars/animatedlife.png` and
  `data/images/game/game_boss_health_bar/bossdbar_prodgress.png`

## Validation performed

- PASS — all repository Lua files parsed with LuaJIT bytecode compilation
- PASS — deterministic `game_things` lifecycle test
- PASS — source-tree package validator
- PASS — generated 513 MB `data.zip` validator
- PASS — packaged DirectX startup smoke test; no new error/fatal log entries
- PASS — Visual Studio `DirectX|x64` build
- PASS — Visual Studio `OpenGL|x64` build
- PASS — `git diff --check`
- NOT TESTED locally — Linux build (the local WSL environment has no x64-linux dependency tree; the existing Linux vcpkg CI remains the build authority)
- NOT TESTED on device — Android runtime; Android remains on the prior memory-backed archive path
- NOT TESTED — authenticated login-to-playable and repeated live logout/relog memory because credentials were intentionally not used

The startup smoke emitted one existing `SlowLua` warning from
`client_entergame/entergame.otui` (~11.9 ms). It is unrelated to the touched
paths and was not changed without a dedicated reproduction.

## Rollback boundaries

- Asset identity: revert `modules/game_things/things.lua` plus the resource
  generation binding.
- Desktop archive mount: revert the `ResourceManager` disk-mount helpers; the
  former memory-backed path remains available for Android/embedded data.
- Actionbar staging: revert only `modules/game_actionbar/actionbar.lua`.
- Helper marker reuse: revert only `mods/game_helper/cavebot_panel.lua`.
- Content checks: remove the content workflow and validation scripts.
