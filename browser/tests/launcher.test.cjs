const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { test } = require('node:test');
const source = fs.readFileSync(require.resolve('../launcher.js'), 'utf8');
const tick = () => new Promise(resolve => setImmediate(resolve));

function launcher({ saved = null, initial = false, denied = false, engineError = false } = {}) {
  const elements = new Map();
  function element(id) {
    if (!elements.has(id)) elements.set(id, { hidden: true, disabled: true, checked: false,
      textContent: '', listeners: {}, classList: { toggle() {} }, setAttribute() {},
      addEventListener(type, callback) { this.listeners[type] = callback; },
      dispatchEvent(event) { this.listeners[event.type]?.({ target: this }); },
      content: { querySelector: () => ({ src: 'http://localhost/client/astraclient.js' }) }, focus() {} });
    return elements.get(id);
  }
  const storage = new Map(saved === null ? [] : [['astra-performance:/client/astraclient.html', saved]]);
  const data = new Uint8Array([1, 2, 3]).buffer;
  const manifest = { version: '8.60', packageName: 'dist/astraclient.data', file: 'astraclient.data', size: 3 };
  const store = { close() {}, remove: async () => {} };
  const context = { console, URL, Event, performance: { now: () => 100 },
    location: new URL('http://localhost/client/astraclient.html'),
    ASTRA_CONFIG: { performance: initial }, navigator: {}, crossOriginIsolated: true,
    localStorage: { getItem(key) { if (denied) throw new Error('denied'); return storage.get(key) ?? null; },
      setItem(key, value) { if (denied) throw new Error('denied'); storage.set(key, value); } },
    document: { getElementById: element, createElement: () => ({ getContext: () => true }), body: {
      appendChild() {
        if (engineError) { context.AstraLauncher.failed('engine failed'); return; }
        const supplied = context.Module.getPreloadedPackage('http://localhost/client/astraclient.data', 3);
        assert.equal(supplied, data);
        assert.throws(() => context.Module.getPreloadedPackage('wrong.data', 3), /mismatch/);
        context.AstraLauncher.runtimeInitialized(); context.AstraLauncher.ready();
      }
    } },
    addEventListener() {}, fetch: async () => ({ ok: true, json: async () => manifest }),
    Module: {}, AstraAssetCache: { validateManifest: m => m, openStore: async () => store,
      state: async () => 'installed', readPackage: async () => data }
  };
  context.window = context; context.self = context;
  vm.runInNewContext(source, context);
  return { context, element, storage };
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
