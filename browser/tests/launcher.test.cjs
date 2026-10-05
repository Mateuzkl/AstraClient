const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { test } = require('node:test');
const source = fs.readFileSync(require.resolve('../launcher.js'), 'utf8');
const tick = () => new Promise(resolve => setImmediate(resolve));

function launcher({ saved = null, initial = false, denied = false, engineError = false, delayedReady = false, delayedRead = false, reducedMotion = false, repair = false, sessionDenied = false, missingEngine = false, locks } = {}) {
  const elements = new Map();
  function element(id) {
    if (!elements.has(id)) elements.set(id, { hidden: true, disabled: true, checked: false,
      textContent: '', listeners: {}, attributes: {}, classList: { toggle() {} },
      setAttribute(key, value) { this.attributes[key] = value; },
      removeAttribute(key) { delete this.attributes[key]; },
      addEventListener(type, callback) { this.listeners[type] = callback; },
      removeEventListener(type, callback) { if (this.listeners[type] === callback) delete this.listeners[type]; },
      dispatchEvent(event) { this.listeners[event.type]?.({ target: this, ...event }); },
      content: { querySelector: () => missingEngine ? null : ({ src: 'http://localhost/client/astraclient.js' }) },
      focusCount: 0, focus() { this.focusCount++; } });
    return elements.get(id);
  }
  const storage = new Map(saved === null ? [] : [['astra-performance:/client/astraclient.html', saved]]);
  const session = new Map(repair ? [['astra-full-verify:/client/astraclient.html', 'on']] : []);
  const hostListeners = {};
  const data = new Uint8Array([1, 2, 3]).buffer;
  const manifest = { version: '8.60', packageName: 'dist/astraclient.data', file: 'astraclient.data', size: 3 };
  let closes = 0, reloads = 0, lastRead, engine, suppliedPackage;
  const store = { close() { closes++; }, remove: async () => {} };
  const timers = new Map();
  let timerId = 0;
  let releaseRead, scripts = 0;
  const context = { console, URL, Event, performance: { now: () => 100 },
    location: new URL('http://localhost/client/astraclient.html'),
    ASTRA_CONFIG: { performance: initial }, navigator: { locks }, crossOriginIsolated: true,
    matchMedia: query => { assert.equal(query, '(prefers-reduced-motion: reduce)'); return { matches: reducedMotion }; },
    setTimeout(callback, milliseconds) { const id = ++timerId; timers.set(id, { callback, milliseconds }); return id; },
    clearTimeout(id) { timers.delete(id); },
    sessionStorage: {
      getItem(key) { if (sessionDenied) throw new Error('denied'); return session.get(key); },
      setItem(key, value) { if (sessionDenied) throw new Error('denied'); session.set(key, value); },
      removeItem(key) { if (sessionDenied) throw new Error('denied'); session.delete(key); }
    },
    localStorage: { getItem(key) { if (denied) throw new Error('denied'); return storage.get(key) ?? null; },
      setItem(key, value) { if (denied) throw new Error('denied'); storage.set(key, value); } },
    document: { getElementById: element, createElement: () => ({ getContext: () => true }), body: {
      appendChild(script) {
        engine = script;
        suppliedPackage = context.Module.getPreloadedPackage;
        scripts++;
        if (engineError) { context.AstraLauncher.failed('engine failed'); return; }
        const supplied = context.Module.getPreloadedPackage('http://localhost/client/astraclient.data', 3);
        assert.equal(supplied, data);
        assert.throws(() => context.Module.getPreloadedPackage('wrong.data', 3), /mismatch/);
        context.AstraLauncher.runtimeInitialized();
        if (!delayedReady) context.AstraLauncher.ready();
      }
    } },
    addEventListener(name, fn) { hostListeners[name] = fn; }, fetch: async () => ({ ok: true, json: async () => manifest }),
    Module: {}, AstraAssetCache: { validateManifest: m => m, openStore: async () => store,
      state: async () => 'installed', readPackage: async (_, __, ___, options) => {
        lastRead = options;
        if (delayedRead) await new Promise(resolve => { releaseRead = resolve; });
        return data;
      } }
  };
  context.location.reload = () => { reloads++; };
  context.window = context; context.self = context;
  element('astra-launcher').hidden = false; // Visible in the production HTML.
  vm.runInNewContext(source, context);
  return { context, element, storage, timers, session, hostListeners, closes: () => closes,
    readOptions: () => lastRead, reloads: () => reloads, engine: () => engine, suppliedPackage: () => suppliedPackage,
    releaseRead: () => releaseRead(), scripts: () => scripts };
}

test('Web options disables/enables the overlay and persists the choice', async () => {
  const { element, context, storage } = launcher();
  await tick();
  assert.equal(element('astra-performance').hidden, true);
  element('astra-web-options-button').listeners.click();
  assert.equal(element('astra-web-options-panel').hidden, false);
  const toggle = element('launcher-performance-toggle');
  toggle.checked = true; toggle.dispatchEvent(new Event('change'));
  assert.equal(element('astra-performance').hidden, false);
  assert.equal(context.ASTRA_CONFIG.performance, true);
  assert.equal(storage.get('astra-performance:/client/astraclient.html'), 'on');
  element('astra-performance-close').listeners.click();
  assert.equal(element('astra-performance').hidden, true);
  assert.equal(context.ASTRA_CONFIG.performance, false);
  assert.equal(storage.get('astra-performance:/client/astraclient.html'), 'off');
});

test('saved Off overrides a deployment default and denied storage is harmless', async () => {
  const off = launcher({ saved: 'off', initial: true });
  const unavailable = launcher({ initial: false, denied: true });
  await tick();
  assert.equal(off.element('astra-performance').hidden, true);
  assert.equal(off.element('launcher-performance-toggle').checked, false);
  const toggle = unavailable.element('launcher-performance-toggle');
  toggle.checked = true;
  assert.doesNotThrow(() => toggle.dispatchEvent(new Event('change')));
});

test('Play hands verified data to the SDK exactly once and waits for a real client frame', async () => {
  const { element, context } = launcher();
  await tick();
  assert.equal(element('launcher-play').disabled, false);
  await element('launcher-play').listeners.click();
  assert.equal(element('astra-launcher').hidden, false);
  element('astra-launcher').dispatchEvent({ type: 'transitionend', propertyName: 'opacity' });
  assert.equal(element('astra-launcher').hidden, true);
  assert.equal(context.Module.getPreloadedPackage, null);
});

test('engine failure releases the preload handoff and requires an explicit reload', async () => {
  const { element, context } = launcher({ engineError: true });
  await tick();
  await element('launcher-play').listeners.click();
  assert.equal(context.Module.getPreloadedPackage, null);
  assert.equal(element('launcher-reload').hidden, false);
  assert.equal(element('launcher-state').textContent, 'Repair required');
  assert.equal(element('launcher-play').disabled, true);
  assert.equal(element('launcher-message').textContent, 'engine failed');
});

test('Play immediately shows the emblem splash, blocks duplicate actions and waits for first frame', async () => {
  const run = launcher({ delayedRead: true, delayedReady: true });
  await tick();
  const first = run.element('launcher-play').listeners.click();
  assert.equal(run.element('astra-launcher').attributes['data-mode'], 'loading');
  assert.equal(run.element('launcher-splash').hidden, false);
  run.element('launcher-play').listeners.click();
  run.element('launcher-uninstall').listeners.click();
  assert.equal(run.element('launcher-confirm').hidden, true);
  assert.ok(run.element('launcher-update').disabled);
  run.releaseRead(); await tick();
  assert.equal(run.scripts(), 1);
  assert.equal(run.element('astra-launcher').hidden, false, 'runtime initialization is not a rendered frame');
  assert.equal(run.element('astra-launcher').attributes['data-fading'], undefined);
  assert.equal(run.timers.size, 0, 'no startup synchronization timer');
  run.context.AstraLauncher.ready(); await first;
  const overlay = run.element('astra-launcher');
  assert.equal(overlay.attributes['data-fading'], '');
  assert.equal(overlay.hidden, false, 'first frame starts the fade, not immediate hiding');
  assert.equal(run.element('canvas').focusCount, 0);
  const onEnd = overlay.listeners.transitionend;
  const fallback = [...run.timers.values()][0];
  run.context.AstraLauncher.ready();
  assert.equal(overlay.listeners.transitionend, onEnd, 'duplicate ready does not restart the fade');
  assert.equal(run.timers.size, 1);
  assert.equal([...run.timers.values()][0], fallback);
  overlay.dispatchEvent({ type: 'transitionend', propertyName: 'opacity', target: run.element('launcher-play') });
  overlay.dispatchEvent({ type: 'transitionend', propertyName: 'background' });
  overlay.dispatchEvent({ type: 'transitionend', propertyName: 'opacity', pseudoElement: '::before' });
  assert.equal(overlay.hidden, false, 'only the overlay opacity transition completes the fade');
  overlay.dispatchEvent({ type: 'transitionend', propertyName: 'opacity' });
  assert.equal(run.element('astra-launcher').hidden, true);
  assert.equal(run.element('canvas').focusCount, 1);
  assert.equal(run.timers.size, 0);
  assert.equal(overlay.listeners.transitionend, undefined);
  run.context.AstraLauncher.ready();
  onEnd({ target: overlay, propertyName: 'opacity' });
  fallback.callback();
  assert.equal(run.element('canvas').focusCount, 1, 'late completion and duplicate ready are harmless');
  assert.equal(run.scripts(), 1);
});

test('a failed splash cannot be hidden by a late first-frame callback', async () => {
  const run = launcher({ engineError: true });
  await tick(); await run.element('launcher-play').listeners.click();
  run.context.AstraLauncher.ready();
  assert.equal(run.element('astra-launcher').attributes['data-mode'], 'error');
  assert.equal(run.element('astra-launcher').hidden, false);
  assert.equal(run.element('splash-progress').hidden, true);
  assert.equal(run.element('astra-launcher').attributes['data-fading'], undefined);
  assert.equal(run.timers.size, 0);
  assert.equal(run.element('canvas').focusCount, 0);
});

test('a failure during fade restores the error splash and cancels all completion paths', async () => {
  const run = launcher();
  await tick(); await run.element('launcher-play').listeners.click();
  const overlay = run.element('astra-launcher');
  const onEnd = overlay.listeners.transitionend;
  const fallback = [...run.timers.values()][0];
  run.context.AstraLauncher.failed('render failed');
  assert.equal(overlay.attributes['data-mode'], 'error');
  assert.equal(overlay.attributes['data-fading'], undefined);
  assert.equal(overlay.hidden, false);
  assert.equal(overlay.listeners.transitionend, undefined);
  assert.equal(run.timers.size, 0);
  run.context.AstraLauncher.ready();
  onEnd({ target: overlay, propertyName: 'opacity' });
  fallback.callback();
  assert.equal(overlay.hidden, false);
  assert.equal(run.element('canvas').focusCount, 0);
});

test('reduced motion hides immediately on the first frame and focuses the canvas', async () => {
  const run = launcher({ reducedMotion: true, delayedReady: true });
  await tick();
  const play = run.element('launcher-play').listeners.click(); await tick();
  assert.equal(run.element('astra-launcher').hidden, false);
  assert.equal(run.element('canvas').focusCount, 0);
  run.context.AstraLauncher.ready(); await play;
  assert.equal(run.element('astra-launcher').hidden, true);
  assert.equal(run.element('canvas').focusCount, 1);
  assert.equal(run.element('astra-launcher').attributes['data-fading'], undefined);
  assert.equal(run.timers.size, 0);
  run.context.AstraLauncher.ready();
  assert.equal(run.element('canvas').focusCount, 1);
});

test('a missing transitionend uses visual cleanup only after the first frame', async () => {
  const run = launcher({ delayedReady: true });
  await tick();
  const play = run.element('launcher-play').listeners.click(); await tick();
  assert.equal(run.timers.size, 0);
  assert.equal(run.element('astra-launcher').hidden, false);
  run.context.AstraLauncher.ready(); await play;
  const fallback = [...run.timers.values()][0];
  assert.equal(fallback.milliseconds, 500);
  assert.equal(run.element('astra-launcher').hidden, false);
  fallback.callback();
  assert.equal(run.element('astra-launcher').hidden, true);
  assert.equal(run.element('canvas').focusCount, 1);
  assert.equal(run.timers.size, 0);
});

test('cross-tab lock contention shows a status and never boots before ownership', async () => {
  let grant, released = false;
  const locks = { request(name, options, callback) {
    if (callback) return callback(null);
    return new Promise(resolve => { grant = async () => {
      await options({ name }); released = true; resolve();
    }; });
  } };
  const run = launcher({ delayedReady: true, locks });
  await tick();
  const play = run.element('launcher-play').listeners.click();
  await tick();
  assert.match(run.element('splash-message').textContent, /Waiting for another Astra tab/);
  assert.equal(run.scripts(), 0);
  const ownership = grant(); await tick();
  assert.equal(run.scripts(), 1);
  assert.equal(released, false, 'ownership lasts until the first rendered frame');
  run.context.AstraLauncher.ready(); await ownership; await play;
  assert.equal(released, true);
});

test('Repair requests full verification on the next Play while normal cached Play remains trusted', async () => {
  const normal = launcher();
  await tick(); await normal.element('launcher-play').listeners.click();
  assert.equal(normal.readOptions().fullVerify, false);
  normal.element('launcher-reload').listeners.click();
  assert.equal(normal.session.get('astra-full-verify:/client/astraclient.html'), 'on');
  assert.equal(normal.reloads(), 1);
  const repair = launcher({ repair: true });
  await tick(); await repair.element('launcher-play').listeners.click();
  assert.equal(repair.readOptions().fullVerify, true);
  assert.equal(repair.session.has('astra-full-verify:/client/astraclient.html'), false);
  const denied = launcher({ sessionDenied: true });
  await tick(); await denied.element('launcher-play').listeners.click();
  assert.equal(denied.readOptions().fullVerify, true, 'denied sessionStorage must not bypass Repair');
});

test('failure clears script callbacks and stale preload buffers and ignores late runtime callbacks', async () => {
  const run = launcher({ engineError: true });
  await tick(); await run.element('launcher-play').listeners.click();
  assert.equal(run.engine().onload, null);
  assert.equal(run.engine().onerror, null);
  assert.throws(() => run.suppliedPackage()('http://localhost/client/astraclient.data', 3), /mismatch/);
  run.context.AstraLauncher.failed('duplicate failure');
  run.context.AstraLauncher.runtimeInitialized();
  run.context.AstraLauncher.ready();
  run.hostListeners.pagehide();
  assert.equal(run.closes(), 1);
  assert.equal(run.element('launcher-message').textContent, 'engine failed');
  assert.equal(run.element('astra-launcher').hidden, false);
});

test('pagehide cancels fade listeners/timers and cannot close the completed store twice', async () => {
  const run = launcher();
  await tick(); await run.element('launcher-play').listeners.click();
  const late = [...run.timers.values()][0].callback;
  run.hostListeners.pagehide(); run.hostListeners.pagehide();
  assert.equal(run.timers.size, 0);
  assert.equal(run.element('astra-launcher').listeners.transitionend, undefined);
  assert.equal(run.closes(), 1);
  late();
  assert.equal(run.element('canvas').focusCount, 0);
});

test('a missing engine template releases the prepared package before retry', async () => {
  const run = launcher({ missingEngine: true });
  await tick(); await run.element('launcher-play').listeners.click();
  assert.equal(run.context.Module.getPreloadedPackage, null);
  assert.equal(run.scripts(), 0);
  assert.match(run.element('launcher-message').textContent, /script is missing/);
});
