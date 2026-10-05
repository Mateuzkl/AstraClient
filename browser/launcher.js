/* First screen only. Does not change game input, DPI, credentials or packets. */
(() => {
  'use strict';
  const el = id => document.getElementById(id);
  const api = AstraAssetCache;
  let manifest, store, current = 'checking', running = false, engineStarted = false;
  let finishStartup, clientReady = false, startupFailed = false;
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
  function update() {
    const labels = { checking: 'Checking game data', missing: 'Not installed', installed: 'Ready to Play',
      outdated: 'Update available', unavailable: 'Storage unavailable', error: 'Repair required', starting: 'Opening client' };
    el('launcher-state').textContent = labels[current];
    if (manifest) el('launcher-size').textContent = `${(manifest.size / 1048576).toFixed(1)} MiB · ${current === 'installed' ? 'cached in your browser' : 'game data package'}`;
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
  async function loadManifest() {
    const response = await fetch('asset-manifest.json', { cache: 'no-store', credentials: 'same-origin' });
    if (!response.ok) throw new Error('Game data manifest is missing. Rebuild the browser bundle.');
    manifest = api.validateManifest(await response.json());
    el('launcher-version').textContent = manifest.version;
  }
  async function download() {
    if (!store) throw new Error('Persistent storage is unavailable. Use Play to load without installation.');
    running = 'install'; update();
    await api.install(store, manifest, () => fetch(manifest.file, { cache: 'no-cache', credentials: 'same-origin' }),
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
      store.close(); store = await api.openStore(window.indexedDB, location.pathname, manifest.packageName);
    }
    await download();
  }));
  el('launcher-uninstall').addEventListener('click', () => {
    if (!running && !engineStarted) el('launcher-confirm').hidden = false;
  });
  el('launcher-cancel-remove').addEventListener('click', () => { el('launcher-confirm').hidden = true; });
  el('launcher-confirm-remove').addEventListener('click', () => task(async () => {
    await store.remove(); current = 'missing'; message('Game data removed. Your saved settings were kept.');
  }));
  el('launcher-play').addEventListener('click', () => {
    if (running || engineStarted) return;
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
        telemetry.cacheVerifiedBytes = bytes;
        const bar = el('splash-progress'); bar.max = total; bar.value = bytes;
        message(`Preparing game data · ${(bytes / 1048576).toFixed(1)} / ${(total / 1048576).toFixed(1)} MiB`);
      }, { diagnostics: performanceEnabled ? telemetry : null }); } catch (_) { store.close(); store = null; }
    }
    telemetry.cacheReadMs = Math.round(performance.now() - readStarted);
    telemetry.cacheHit = !!data;
    if (!data) {
      running = 'install'; update();
      telemetry.cacheIntegrityMode = 'download';
      const downloadStarted = performance.now();
      data = await api.fetchPackage(store, manifest,
        () => fetch(manifest.file, { cache: 'no-cache', credentials: 'same-origin' }),
        (bytes, total) => {
          telemetry.downloadBytes = bytes;
          const bar = el('splash-progress'); bar.max = total; bar.value = bytes;
          message(`Downloading game data · ${(bytes / 1048576).toFixed(1)} / ${(total / 1048576).toFixed(1)} MiB`);
        },
        () => { telemetry.persistentCacheUnavailable = true; });
      telemetry.downloadMs = Math.round(performance.now() - downloadStarted);
    }
    telemetry.preloadedPackageMiB = data.byteLength / 1048576;
    Module.getPreloadedPackage = (url, size) => {
      const expected = new URL(manifest.file, location.href).href;
      if (!data || new URL(url, location.href).href !== expected || size !== data.byteLength)
        throw new Error('Browser engine/package mismatch. Refresh the deployment.');
      const result = data;
      data = null; // FS owns views into this buffer after the SDK consumes it.
      return result;
    };
    // Keep the canvas full-size underneath the launcher. Hiding/resizing it
    // during initialization would regress the known-good DPI and mouse path.
    running = true; current = 'starting'; update();
    el('launcher-progress').hidden = true;
    el('splash-progress').removeAttribute('value');
    message(store ? 'Opening Astra Web…' : 'Loading without persistent storage. Game data will be downloaded for this session.');
    const source = el('astra-engine').content.querySelector('script[src]');
    if (!source) throw new Error('Browser engine script is missing. Rebuild the bundle.');
    const script = document.createElement('script');
    script.src = source.src;
    script.onload = () => window.AstraLauncher.phase('engineScriptFetchLoad', performance.now() - engineStart);
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
      current = 'error'; message(text, true);
      Module.getPreloadedPackage = null;
      if (store) { store.close(); store = null; }
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
      Module.getPreloadedPackage = null;
      el('astra-launcher').hidden = true;
      el('canvas').focus();
      if (store) { store.close(); store = null; }
      if (finishStartup) { finishStartup(); finishStartup = null; }
      report();
    },
    runtimeInitialized() {
      telemetry.wasmReadyMs = Math.round(performance.now() - telemetry.engineClockMs);
      message('Loading client resources…');
      report();
    },
    frameStats(stats) { telemetry.render = stats; report(); }
  };
  el('launcher-reload').addEventListener('click', () => window.location.reload());
  window.addEventListener('pagehide', () => { if (store) store.close(); });
  (async () => {
    try {
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
