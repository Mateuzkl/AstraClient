/* First screen only. Does not change game input, DPI, credentials or packets. */
(() => {
  'use strict';
  const el = id => document.getElementById(id);
  const api = AstraAssetCache;
  const platformApi = window.AstraPlatform || null;
  const sprPagerApi = window.AstraSprPager || null;
  let manifest, store, current = 'checking', running = false, engineStarted = false;
  let finishStartup, cancelSplashFade, clientReady = false, startupFailed = false;
  let releasePreload, engineScript, sprPager = null, viewportController = null;
  let activeProfile = 'desktop';
  let profileResolution = null;
  let profileBase = '';
  let profileScript = '';
  let profilesIndex = null;
  const repairKey = `astra-full-verify:${location.pathname}`;
  let fullVerify = true; // Denied sessionStorage conservatively verifies each handoff.
  try { fullVerify = sessionStorage.getItem(repairKey) === 'on'; } catch (_) {}
  const closeStore = () => {
    if (store) { const previous = store; store = null; previous.close(); }
  };
  const disposeSprPager = () => {
    if (sprPager) { const previous = sprPager; sprPager = null; previous.dispose(); }
    if (window.Module && window.Module.astraRequestSprPage) window.Module.astraRequestSprPage = null;
  };
  const clearEngineCallbacks = () => {
    if (engineScript) { engineScript.onload = engineScript.onerror = null; engineScript = null; }
  };
  const profileBaseUrl = () => new URL(profileBase || '.', location.href);
  const resolveProfileAsset = (relative) => new URL(relative, profileBaseUrl()).href;
  const safeLocalStorage = () => { try { return window.localStorage; } catch (_) { return null; } };
  const started = performance.now();
  const telemetry = { launcherMs: 0, downloadBytes: 0, cacheVerifiedBytes: 0, startupMs: null };
  let performanceEnabled = window.ASTRA_CONFIG.performance === true;
  const preferenceKey = `astra-performance:${location.pathname}`;
  try {
    const saved = localStorage.getItem(preferenceKey);
    if (saved === 'on' || saved === 'off') performanceEnabled = saved === 'on';
  } catch (_) {} // Private mode can deny localStorage, too.
  window.ASTRA_CONFIG.performance = performanceEnabled;
  el('launcher-performance-toggle').checked = performanceEnabled;
  const report = () => {
    el('astra-performance').hidden = !performanceEnabled;
    if (!performanceEnabled) return;
    if (sprPager) telemetry.sprPager = sprPager.getStats();
    el('astra-performance-values').textContent = JSON.stringify(telemetry, null, 2);
  };
  el('launcher-performance-toggle').addEventListener('change', event => {
    performanceEnabled = event.target.checked;
    window.ASTRA_CONFIG.performance = performanceEnabled;
    try { localStorage.setItem(preferenceKey, performanceEnabled ? 'on' : 'off'); } catch (_) {}
    report();
  });
  el('astra-web-options-button').addEventListener('click', () => {
    const panel = el('astra-web-options-panel');
    panel.hidden = !panel.hidden;
    el('astra-web-options-button').setAttribute('aria-expanded', String(!panel.hidden));
  });
  el('astra-performance-close').addEventListener('click', () => {
    el('launcher-performance-toggle').checked = false;
    el('launcher-performance-toggle').dispatchEvent(new Event('change'));
  });
  function applyProfileAttributes(profile) {
    const overlay = el('astra-launcher');
    if (overlay && typeof overlay.setAttribute === 'function') overlay.setAttribute('data-profile', profile);
    if (document.body && typeof document.body.setAttribute === 'function') document.body.setAttribute('data-profile', profile);
    const webOptions = el('astra-web-options');
    if (webOptions) webOptions.hidden = profile === 'mobile';
    const label = el('launcher-profile-label');
    if (label) {
      const detectedNote = profileResolution && profileResolution.source === 'manual' ? ' (manual)' : '';
      label.textContent = (profile === 'mobile' ? 'Web Mobile Lite' : 'Web Desktop Full') + detectedNote;
    }
  }
  function wireProfileSelects(available, savedPreference) {
    if (!platformApi || available.length <= 1) return;
    const launcherRow = el('launcher-profile-row');
    const launcherSelect = el('launcher-profile-select');
    const webRow = el('web-profile-option');
    const webSelect = el('web-profile-select');
    const onSelectChange = (event) => {
      const choice = event.target.value;
      platformApi.writeSavedPreference(safeLocalStorage(), location.pathname, choice);
      window.location.reload();
    };
    if (launcherRow) launcherRow.hidden = false;
    if (webRow) webRow.hidden = false;
    for (const select of [launcherSelect, webSelect]) {
      if (!select) continue;
      select.value = savedPreference || 'auto';
      select.addEventListener('change', onSelectChange);
    }
  }
  function setupMobileViewport() {
    if (!platformApi || activeProfile !== 'mobile' || viewportController) return;
    const rotateOverlay = el('astra-rotate-overlay');
    const rotateLockBtn = el('astra-rotate-lock');
    const rotateDismissBtn = el('astra-rotate-dismiss');
    viewportController = platformApi.createMobileViewportController({
      window,
      document,
      onViewportChange() {
        if (window.Module && typeof window.Module._astra_browser_viewport_changed === 'function') {
          window.Module._astra_browser_viewport_changed();
        }
      },
      onOrientationState(state) {
        telemetry.orientation = state.orientationType;
        if (rotateOverlay) rotateOverlay.hidden = !state.showRotateOverlay;
      }
    });
    viewportController.install(el('canvas'));
    if (rotateLockBtn) {
      rotateLockBtn.addEventListener('click', () => { viewportController.requestFullscreenAndLandscape(); });
    }
    if (rotateDismissBtn) {
      rotateDismissBtn.addEventListener('click', () => { viewportController.dismissRotatePrompt(); });
    }
  }
  function message(text, error = false) {
    el('launcher-message').textContent = text;
    el('launcher-message').classList.toggle('error', error);
    el('splash-message').textContent = text;
  }
  function mode(value) {
    el('astra-launcher').setAttribute('data-mode', value);
    el('astra-launcher').setAttribute('aria-busy', String(value === 'loading'));
    el('launcher-splash').hidden = value === 'manage';
    el('launcher-splash').setAttribute('aria-busy', String(value === 'loading'));
    el('splash-title').textContent = value === 'error' ? 'Unable to open Astra Client' : 'Loading Astra Client';
    el('splash-progress').hidden = value === 'error';
    el('splash-progress').removeAttribute('value');
  }
  function dismissSplash() {
    const overlay = el('astra-launcher');
    const hide = () => { overlay.hidden = true; el('canvas').focus(); };
    if (window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
      hide(); return;
    }
    let fallback;
    const complete = () => {
      if (!cancelSplashFade) return;
      cancelSplashFade();
      if (!startupFailed) hide();
    };
    const onEnd = event => {
      if (event.target === overlay && event.propertyName === 'opacity' && !event.pseudoElement) complete();
    };
    cancelSplashFade = () => {
      clearTimeout(fallback);
      overlay.removeEventListener('transitionend', onEnd);
      overlay.removeAttribute('data-fading');
      cancelSplashFade = null;
    };
    overlay.addEventListener('transitionend', onEnd);
    overlay.setAttribute('data-fading', '');
    // Visual cleanup only: startup has already reached its first rendered frame.
    fallback = setTimeout(complete, 500);
  }
  function update() {
    const labels = { checking: 'Checking game data', missing: 'Not installed', installed: 'Ready to Play',
      outdated: 'Update available', unavailable: 'Storage unavailable', error: 'Repair required', starting: 'Opening client' };
    el('launcher-state').textContent = labels[current];
    if (manifest) {
      const sprNote = manifest.sprMode === 'paged' ? ' · on-demand sprites' : '';
      el('launcher-size').textContent = `${(manifest.size / 1048576).toFixed(1)} MiB · ${current === 'installed' ? 'cached in your browser' : 'game data package'}${sprNote}`;
    }
    el('launcher-state').className = current === 'installed' ? 'ready' : current === 'error' ? 'error' : '';
    el('launcher-install').disabled = running || !store || current === 'installed';
    el('launcher-update').disabled = running || !store;
    el('launcher-uninstall').disabled = running || !store || current === 'missing';
    el('launcher-play').disabled = running || !manifest;
    el('launcher-card').setAttribute('aria-busy', String(running));
  }
  function progress(bytes, total) {
    const bar = el('launcher-progress');
    bar.hidden = false; bar.max = total; bar.value = bytes;
    message(`${running === 'verify' ? 'Verifying' : 'Installing'} game data · ${(bytes / 1048576).toFixed(1)} / ${(total / 1048576).toFixed(1)} MiB`);
  }
  async function resolveDeploymentProfile() {
    if (!platformApi) {
      applyProfileAttributes(activeProfile);
      return;
    }
    // Detect before downloading any bundle manifest or assets.
    let available = ['desktop'];
    try {
      const response = await fetch('profiles.json', { cache: 'no-store', credentials: 'same-origin' });
      if (response.ok) {
        const parsed = await response.json();
        if (parsed && parsed.schema === 1 && parsed.profiles && typeof parsed.profiles === 'object') {
          const keys = Object.keys(parsed.profiles).filter(k => k === 'desktop' || k === 'mobile');
          if (keys.length) {
            profilesIndex = parsed;
            available = keys;
          }
        }
      }
    } catch (_) {}

    profileResolution = platformApi.resolveProfile({
      window,
      navigator,
      screen,
      pathname: location.pathname,
      storage: safeLocalStorage()
    }, available);
    activeProfile = profileResolution.selected;
    telemetry.profile = activeProfile;
    telemetry.platform = {
      os: profileResolution.info.os,
      formFactor: profileResolution.info.formFactor,
      reason: profileResolution.info.reason,
      source: profileResolution.source,
      fallback: profileResolution.fallback
    };

    if (profilesIndex && profilesIndex.profiles[activeProfile]) {
      const entry = profilesIndex.profiles[activeProfile];
      profileBase = entry.base || '';
      profileScript = entry.script || 'astraclient.js';
    } else {
      profileBase = '';
      profileScript = '';
    }

    if (window.Module) {
      window.Module.arguments = activeProfile === 'mobile' ? ['-mobile-lite'] : [];
      if (profileBase) {
        const base = profileBaseUrl();
        window.Module.locateFile = (filePath) => new URL(filePath, base).href;
      }
    }
    applyProfileAttributes(activeProfile);
    wireProfileSelects(available, profileResolution.preference);
    setupMobileViewport();
  }
  async function loadManifest() {
    const manifestName = (profilesIndex && profilesIndex.profiles[activeProfile] && profilesIndex.profiles[activeProfile].manifest) || 'asset-manifest.json';
    const manifestUrl = profileBase ? resolveProfileAsset(manifestName) : manifestName;
    const response = await fetch(manifestUrl, { cache: 'no-store', credentials: 'same-origin' });
    if (!response.ok) throw new Error('Game data manifest is missing. Rebuild the browser bundle.');
    manifest = api.validateManifest(await response.json());
    el('launcher-version').textContent = manifest.version;
    telemetry.bootPackageBytes = manifest.size;
    if (manifest.sprMode) telemetry.sprMode = manifest.sprMode;
  }
  async function prepareSprPager() {
    disposeSprPager();
    if (!manifest || manifest.sprMode !== 'paged') return;
    if (!manifest.sprManifest || !sprPagerApi) {
      throw new Error('On-demand sprite pager is unavailable for paged mobile bundle.');
    }
    const sprManifestUrl = resolveProfileAsset(manifest.sprManifest);
    const response = await fetch(sprManifestUrl, { cache: 'no-store', credentials: 'same-origin' });
    if (!response.ok) throw new Error('On-demand sprite manifest is missing.');
    const sprManifest = sprPagerApi.validateSprManifest(await response.json());
    const sprNamespace = `${location.pathname}:${activeProfile}`;
    if (fullVerify && typeof sprPagerApi.clearProfilePages === 'function') {
      await sprPagerApi.clearProfilePages(window.indexedDB, sprNamespace).catch(() => {});
    }
    const pageStore = await sprPagerApi.openPageStore(window.indexedDB, sprNamespace);
    sprPager = sprPagerApi.createPager({
      manifest: sprManifest,
      baseUrl: profileBaseUrl().href,
      store: pageStore,
      fetcher: (url, init) => fetch(url, init),
      onDeliver(pageIndex, bytes, ok) {
        if (!window.Module || typeof window.Module._astra_spr_page_loaded !== 'function') return;
        if (!ok || !bytes || !bytes.byteLength) {
          window.Module._astra_spr_page_loaded(pageIndex >>> 0, 0, 0, 0);
          return;
        }
        const ptr = window.Module._malloc(bytes.byteLength);
        if (!ptr) {
          window.Module._astra_spr_page_loaded(pageIndex >>> 0, 0, 0, 0);
          return;
        }
        try {
          const heapView = window.Module.wasmMemory
            ? new Uint8Array(window.Module.wasmMemory.buffer)
            : window.Module.HEAPU8;
          heapView.set(bytes, ptr);
          window.Module._astra_spr_page_loaded(pageIndex >>> 0, ptr, bytes.byteLength >>> 0, 1);
        } finally {
          window.Module._free(ptr);
        }
        if (performanceEnabled) report();
      }
    });
    window.Module.astraRequestSprPage = (pageIndex) => {
      if (sprPager) sprPager.requestPage(pageIndex >>> 0);
    };
  }
  async function download() {
    if (!store) throw new Error('Persistent storage is unavailable. Use Play to load without installation.');
    running = 'install'; update();
    const dataUrl = profileBase ? resolveProfileAsset(manifest.file) : manifest.file;
    await api.install(store, manifest, () => fetch(dataUrl, { cache: 'no-cache', credentials: 'same-origin' }),
      (bytes, total) => { telemetry.downloadBytes = bytes; progress(bytes, total); });
    current = 'installed';
    message('Game data installed successfully. Your adventure is ready.');
  }
  async function task(callback) {
    if (running || engineStarted) return;
    running = true; update(); el('launcher-confirm').hidden = true;
    try {
      // Serialize install/remove/Play across this deployment's launcher tabs.
      // Hold the Play lock until the SDK has consumed its preload package.
      if (navigator.locks && manifest) {
        const name = `astra-preload:${location.pathname}:${manifest.packageName}`;
        await navigator.locks.request(name, { ifAvailable: true }, async lock => {
          if (lock) return callback();
          message('Waiting for another Astra tab to finish preparing game data…');
          return navigator.locks.request(name, callback);
        });
      }
      else await callback();
    }
    catch (error) {
      if (releasePreload) releasePreload();
      disposeSprPager();
      if (engineStarted) { window.AstraLauncher.failed(error.message || String(error)); return; }
      if (viewportController) viewportController.deactivate();
      current = 'error'; message(error.message || String(error), true);
      mode('error'); el('launcher-reload').hidden = false;
    }
    finally { if (!engineStarted) { running = false; el('launcher-progress').hidden = true; update(); } report(); }
  }
  el('launcher-install').addEventListener('click', () => task(download));
  el('launcher-update').addEventListener('click', () => task(async () => {
    const previous = manifest.packageName;
    await loadManifest();
    if (manifest.packageName !== previous) {
      closeStore(); store = await api.openStore(window.indexedDB, location.pathname, manifest.packageName);
    }
    await download();
  }));
  el('launcher-uninstall').addEventListener('click', () => {
    if (!running && !engineStarted) el('launcher-confirm').hidden = false;
  });
  el('launcher-cancel-remove').addEventListener('click', () => { el('launcher-confirm').hidden = true; });
  el('launcher-confirm-remove').addEventListener('click', () => task(async () => {
    await store.remove();
    if (sprPagerApi && typeof sprPagerApi.clearProfilePages === 'function') {
      await sprPagerApi.clearProfilePages(window.indexedDB, `${location.pathname}:${activeProfile}`).catch(() => {});
    }
    current = 'missing'; message('Game data removed. Your saved settings were kept.');
  }));
  el('launcher-play').addEventListener('click', () => {
    if (running || engineStarted) return;
    // Request fullscreen + landscape synchronously inside the user gesture before awaiting storage/network.
    if (viewportController) {
      viewportController.activate();
      viewportController.requestFullscreenAndLandscape();
    }
    mode('loading'); message('Preparing game data…');
    telemetry.playClickedAtMs = Math.round(performance.now() - started);
    return task(async () => {
    message('Preparing game data…');
    if (!self.crossOriginIsolated) throw new Error('This site needs COOP/COEP headers. Start it with browser/serve.py.');
    if (!document.createElement('canvas').getContext('webgl2')) throw new Error('WebGL 2 is unavailable in this browser.');
    const readStarted = performance.now();
    let data = null;
    if (store) {
      running = 'verify'; update();
      try { data = await api.readPackage(store, manifest, (bytes, total) => {
        telemetry.cacheReadBytes = bytes;
        if (telemetry.cacheIntegrityMode === 'full-verify') telemetry.cacheVerifiedBytes = bytes;
        const bar = el('splash-progress'); bar.max = total; bar.value = bytes;
        message(`Preparing game data · ${(bytes / 1048576).toFixed(1)} / ${(total / 1048576).toFixed(1)} MiB`);
      }, { fullVerify, diagnostics: performanceEnabled ? telemetry : null }); } catch (_) { closeStore(); }
    }
    telemetry.cacheReadMs = Math.round(performance.now() - readStarted);
    telemetry.cacheHit = !!data;
    if (!data) {
      running = 'install'; update();
      telemetry.cacheIntegrityMode = 'download';
      const downloadStarted = performance.now();
      const dataUrl = profileBase ? resolveProfileAsset(manifest.file) : manifest.file;
      data = await api.fetchPackage(store, manifest,
        () => fetch(dataUrl, { cache: 'no-cache', credentials: 'same-origin' }),
        (bytes, total) => {
          telemetry.downloadBytes = bytes;
          const bar = el('splash-progress'); bar.max = total; bar.value = bytes;
          message(`Downloading game data · ${(bytes / 1048576).toFixed(1)} / ${(total / 1048576).toFixed(1)} MiB`);
        },
        () => { telemetry.persistentCacheUnavailable = true; });
      telemetry.downloadMs = Math.round(performance.now() - downloadStarted);
    }
    await prepareSprPager();
    // Clear the request only after hashing the cached package or a fresh download.
    try { sessionStorage.removeItem(repairKey); } catch (_) {}
    fullVerify = false;
    telemetry.preloadedPackageMiB = data.byteLength / 1048576;
    const expectedPackageUrl = resolveProfileAsset(manifest.file);
    Module.getPreloadedPackage = (url, size) => {
      if (!data || new URL(url, location.href).href !== expectedPackageUrl || size !== data.byteLength)
        throw new Error('Browser engine/package mismatch. Refresh the deployment.');
      const result = data;
      data = null; // FS owns views into this buffer after the SDK consumes it.
      return result;
    };
    releasePreload = () => { data = null; Module.getPreloadedPackage = null; releasePreload = null; };
    // Keep the canvas full-size underneath the launcher. Hiding/resizing it
    // during initialization would regress the known-good DPI and mouse path.
    running = true; current = 'starting'; update();
    el('launcher-progress').hidden = true;
    el('splash-progress').removeAttribute('value');
    message(store ? 'Opening Astra Web…' : 'Loading without persistent storage. Game data will be downloaded for this session.');
    let engineSrc = '';
    if (profileBase && profileScript) {
      engineSrc = resolveProfileAsset(profileScript);
    } else {
      const source = el('astra-engine').content.querySelector('script[src]');
      if (!source) throw new Error('Browser engine script is missing. Rebuild the bundle.');
      engineSrc = source.src;
    }
    const script = document.createElement('script');
    engineScript = script;
    script.src = engineSrc;
    script.onload = () => {
      clearEngineCallbacks();
      if (!startupFailed) window.AstraLauncher.phase('engineScriptFetchLoad', performance.now() - engineStart);
    };
    script.onerror = () => window.AstraLauncher.failed('Unable to load the browser engine. Refresh to retry.');
    engineStarted = true;
    telemetry.engineStartAtMs = Math.round(performance.now() - started);
    const engineStart = performance.now();
    telemetry.engineClockMs = engineStart;
    const ready = new Promise(resolve => { finishStartup = resolve; });
    document.body.appendChild(script);
    await ready;
    });
  });
  window.AstraLauncher = {
    status(text) { if (engineStarted && !clientReady && !startupFailed && text) message(text); },
    phase(name, milliseconds) {
      if (!performanceEnabled) return;
      if (!telemetry.stages) telemetry.stages = {};
      telemetry.stages[name] = Math.round(milliseconds * 100) / 100;
      report();
    },
    failed(text) {
      if (startupFailed) return;
      startupFailed = true; mode('error');
      if (cancelSplashFade) cancelSplashFade();
      if (viewportController) viewportController.deactivate();
      current = 'error'; message(text, true);
      if (releasePreload) releasePreload();
      disposeSprPager();
      clearEngineCallbacks();
      closeStore();
      update();
      // A partially initialized engine must not be instantiated twice.
      el('launcher-reload').hidden = false;
      el('astra-launcher').hidden = false;
      if (finishStartup) { finishStartup(); finishStartup = null; }
    },
    ready() {
      if (clientReady || startupFailed) return;
      clientReady = true;
      telemetry.startupMs = Math.round(performance.now() - telemetry.engineClockMs);
      telemetry.clientInitMs = telemetry.startupMs - telemetry.wasmReadyMs;
      telemetry.firstFrameMs = Math.round(performance.now() - started);
      telemetry.playToFirstFrameMs = telemetry.firstFrameMs - telemetry.playClickedAtMs;
      delete telemetry.engineClockMs;
      if (releasePreload) releasePreload();
      clearEngineCallbacks();
      dismissSplash();
      closeStore();
      if (finishStartup) { finishStartup(); finishStartup = null; }
      report();
    },
    runtimeInitialized() {
      if (startupFailed || clientReady) return;
      telemetry.wasmReadyMs = Math.round(performance.now() - telemetry.engineClockMs);
      message('Loading client resources…');
      report();
    },
    frameStats(stats) { telemetry.render = stats; report(); },
    getProfile() { return activeProfile; },
    getTelemetry() { return telemetry; },
    switchProfile(choice) {
      if (!platformApi) return;
      const target = choice === 'desktop' || choice === 'mobile' || choice === 'auto' ? choice : 'auto';
      platformApi.writeSavedPreference(safeLocalStorage(), location.pathname, target);
      window.location.reload();
    },
    toggleDiagnostics() {
      const toggle = el('launcher-performance-toggle');
      if (!toggle) return;
      toggle.checked = !toggle.checked;
      toggle.dispatchEvent(new Event('change'));
    },
    requestFullscreen() {
      if (viewportController) viewportController.requestFullscreenAndLandscape();
    }
  };
  el('launcher-reload').addEventListener('click', () => {
    try { sessionStorage.setItem(repairKey, 'on'); } catch (_) {}
    window.location.reload();
  });
  window.addEventListener('pagehide', () => {
    closeStore();
    disposeSprPager();
    if (viewportController) viewportController.dispose();
    if (cancelSplashFade) cancelSplashFade();
    if (clientReady && !startupFailed) el('astra-launcher').hidden = true;
  });
  window.addEventListener('pageshow', event => {
    // bfcache restores this JS state, but pagehide already closed its cache handle.
    // Start a fresh launcher instead of reusing closed storage or a suspended engine.
    if (event.persisted) window.location.reload();
  });
  (async () => {
    try {
      await resolveDeploymentProfile();
      await loadManifest();
      try {
        store = await api.openStore(window.indexedDB, location.pathname, manifest.packageName);
        current = await api.state(store, manifest);
        message(current === 'installed' ? 'Game data installed successfully.' : 'Install once. Return to your world in a click.');
      } catch (_) {
        current = 'unavailable';
        message('Browser storage is unavailable. Play can load game data for this session.');
      }
    } catch (error) { current = 'error'; message(error.message || String(error), true); }
    telemetry.launcherMs = Math.round(performance.now() - started);
    update(); report();
  })();
})();
