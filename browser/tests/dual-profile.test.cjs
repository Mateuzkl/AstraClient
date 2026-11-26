const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');
const { test } = require('node:test');

const launcherSource = fs.readFileSync(require.resolve('../launcher.js'), 'utf8');
const AstraPlatform = require('../platform.js');
const AstraSprPager = require('../spr-pager.js');
const bundle = require('../../tools/browser_bundle.cjs');
const tick = () => new Promise(resolve => setImmediate(resolve));

function createFakeSpr(spriteCount = 4, bodyBytes = 64) {
  const headerAndTable = 8 + spriteCount * 4;
  const buf = Buffer.alloc(headerAndTable + bodyBytes, 0xab);
  buf.writeUInt32LE(0x12345678, 0);
  buf.writeUInt32LE(spriteCount, 4);
  for (let i = 0; i < spriteCount; ++i) {
    buf.writeUInt32LE(headerAndTable + i * 8, 8 + i * 4);
  }
  return buf;
}

function runDualProfileLauncher({ userAgent, maxTouchPoints = 0, coarse = false, fine = true, hover = true, width = 1280, height = 720, savedPref = null, orientationLockFails = false }) {
  const elements = new Map();
  function element(id) {
    if (!elements.has(id)) {
      elements.set(id, {
        id, hidden: true, disabled: true, checked: false, value: 'auto',
        textContent: '', listeners: {}, attributes: {}, classList: { toggle() {} },
        setAttribute(k, v) { this.attributes[k] = v; },
        removeAttribute(k) { delete this.attributes[k]; },
        addEventListener(type, cb) { this.listeners[type] = cb; },
        removeEventListener(type, cb) { if (this.listeners[type] === cb) delete this.listeners[type]; },
        dispatchEvent(ev) { this.listeners[ev.type]?.({ target: this, ...ev }); },
        content: { querySelector: () => null },
        focusCount: 0, focus() { this.focusCount++; }
      });
    }
    return elements.get(id);
  }

  const fetchedUrls = [];
  const storageMap = new Map(savedPref ? [[AstraPlatform.profileStorageKey('/astraclient.html'), savedPref]] : []);
  const sessionMap = new Map();
  const storePackages = new Map();
  let reloads = 0;
  let appendedScript = null;
  let fullscreenCalls = 0;
  let lockCalls = 0;
  let deliveredPages = [];

  const sprBuf = createFakeSpr(2, 32);
  const sprHash = crypto.createHash('sha256').update(sprBuf).digest('hex');
  const sprManifest = {
    schema: 1, version: '8.60', file: 'Tibia.spr', size: sprBuf.length, pageSize: 262144,
    spriteCount: 2, indexBytes: 16, uuid: 'sha256-' + sprHash, hashes: [sprHash]
  };

  const profilesJson = {
    schema: 1,
    defaultProfile: 'desktop',
    profiles: {
      desktop: { profile: 'desktop', base: 'desktop/', manifest: 'asset-manifest.json', script: 'astraclient.js', sprMode: 'bundled' },
      mobile: { profile: 'mobile', base: 'mobile/', manifest: 'asset-manifest.json', script: 'astraclient.js', sprMode: 'paged', sprManifest: 'spr-manifest.json' }
    }
  };
  const desktopManifest = { version: '8.60', packageName: 'desktop/astraclient.data', file: 'astraclient.data', size: 10, sprMode: 'bundled' };
  const mobileManifest = { version: '8.60', packageName: 'mobile/astraclient.data', file: 'astraclient.data', size: 4, sprMode: 'paged', sprManifest: 'spr-manifest.json' };
  const desktopData = new Uint8Array(10).fill(1).buffer;
  const mobileData = new Uint8Array(4).fill(2).buffer;

  const wasmBuffer = new ArrayBuffer(65536);
  const Module = {
    arguments: [],
    wasmMemory: { buffer: wasmBuffer },
    _malloc: () => 1024,
    _free: () => {},
    _astra_spr_page_loaded(pageIdx, ptr, size, ok) {
      deliveredPages.push({ pageIdx, size, ok, firstByte: ok ? new Uint8Array(wasmBuffer, ptr, size)[0] : null });
    }
  };

  const winListeners = {};
  const context = {
    console, URL, Event, Uint8Array, ArrayBuffer, crypto,
    performance: { now: () => 50 },
    location: new URL('https://play.example.com/astraclient.html'),
    ASTRA_CONFIG: { performance: true },
    innerWidth: width, innerHeight: height,
    screen: {
      width, height,
      orientation: {
        type: height > width ? 'portrait-primary' : 'landscape-primary',
        lock: async () => {
          lockCalls++;
          if (orientationLockFails) throw new Error('NotSupportedError');
        },
        addEventListener() {}, removeEventListener() {}
      }
    },
    navigator: { userAgent, maxTouchPoints, platform: /iPhone|iPad/.test(userAgent) ? 'iPhone' : 'Linux' },
    crossOriginIsolated: true,
    matchMedia: (q) => ({
      matches:
        (q === '(pointer: coarse)' && coarse) ||
        (q === '(pointer: fine)' && fine) ||
        (q === '(any-pointer: coarse)' && coarse) ||
        (q === '(any-pointer: fine)' && fine) ||
        (q === '(hover: hover)' && hover) ||
        (q === '(hover: none)' && !hover) ||
        (q === '(orientation: portrait)' && height > width) ||
        (q === '(orientation: landscape)' && width >= height)
    }),
    setTimeout, clearTimeout,
    localStorage: {
      getItem: k => storageMap.get(k) ?? null,
      setItem: (k, v) => storageMap.set(k, v),
      removeItem: k => storageMap.delete(k)
    },
    sessionStorage: {
      getItem: k => sessionMap.get(k) ?? null,
      setItem: (k, v) => sessionMap.set(k, v),
      removeItem: k => sessionMap.delete(k)
    },
    document: {
      documentElement: {
        requestFullscreen: async () => { fullscreenCalls++; }
      },
      getElementById: element,
      createElement: () => ({ getContext: () => true }),
      addEventListener() {}, removeEventListener() {},
      body: {
        attributes: {},
        setAttribute(k, v) { this.attributes[k] = v; },
        appendChild(script) {
          appendedScript = script;
          const expectedUrl = new URL(
            context.AstraLauncher.getProfile() === 'mobile' ? 'mobile/astraclient.data' : 'desktop/astraclient.data',
            context.location.href
          ).href;
          const expectedSize = context.AstraLauncher.getProfile() === 'mobile' ? 4 : 10;
          const pkg = Module.getPreloadedPackage(expectedUrl, expectedSize);
          assert.equal(pkg.byteLength, expectedSize);
          context.AstraLauncher.runtimeInitialized();
          context.AstraLauncher.ready();
        }
      }
    },
    addEventListener(name, fn) { winListeners[name] = fn; },
    removeEventListener(name, fn) { if (winListeners[name] === fn) delete winListeners[name]; },
    fetch: async (url, init) => {
      const urlStr = String(url);
      fetchedUrls.push(urlStr);
      if (urlStr.endsWith('profiles.json')) return { ok: true, status: 200, json: async () => profilesJson };
      if (urlStr.endsWith('/desktop/asset-manifest.json')) return { ok: true, status: 200, json: async () => desktopManifest };
      if (urlStr.endsWith('/mobile/asset-manifest.json')) return { ok: true, status: 200, json: async () => mobileManifest };
      if (urlStr.endsWith('/mobile/spr-manifest.json')) return { ok: true, status: 200, json: async () => sprManifest };
      if (urlStr.endsWith('/mobile/Tibia.spr')) {
        assert.match(init.headers.Range, /^bytes=0-\d+$/);
        return { ok: true, status: 206, arrayBuffer: async () => sprBuf.buffer.slice(sprBuf.byteOffset, sprBuf.byteOffset + sprBuf.byteLength) };
      }
      throw new Error('Unexpected fetch: ' + urlStr);
    },
    Module,
    AstraPlatform,
    AstraSprPager,
    AstraAssetCache: {
      validateManifest: m => m,
      openStore: async (_idb, _path, pkgName) => {
        storePackages.set(pkgName, true);
        return { close() {}, remove: async () => {} };
      },
      state: async () => 'installed',
      readPackage: async (_store, m) => (m.packageName.startsWith('mobile/') ? mobileData : desktopData)
    }
  };
  context.location.reload = () => { reloads++; };
  context.window = context;
  context.self = context;
  element('astra-launcher').hidden = false;
  vm.runInNewContext(launcherSource, context);

  return {
    context, element, fetchedUrls, storePackages, storageMap, deliveredPages,
    getAppendedScript: () => appendedScript,
    getReloads: () => reloads,
    getFullscreenCalls: () => fullscreenCalls,
    getLockCalls: () => lockCalls,
    winListeners
  };
}

test('Mobile device selects Mobile Lite before downloading assets, never fetches desktop bundle, and pages Tibia.spr', async () => {
  const run = runDualProfileLauncher({
    userAgent: 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 Chrome/126.0.0.0 Mobile Safari/537.36',
    maxTouchPoints: 5, coarse: true, fine: false, hover: false, width: 390, height: 844,
    orientationLockFails: true
  });
  await tick(); await tick();

  assert.equal(run.context.AstraLauncher.getProfile(), 'mobile');
  assert.ok(run.fetchedUrls.some(u => u.endsWith('/mobile/asset-manifest.json')));
  assert.equal(run.fetchedUrls.some(u => u.includes('/desktop/')), false, 'Mobile must NEVER fetch desktop bundle');
  assert.deepEqual(Array.from(run.context.Module.arguments), ['-mobile-lite']);
  assert.equal(run.context.Module.locateFile('astraclient.wasm'), 'https://play.example.com/mobile/astraclient.wasm');
  assert.ok(run.storePackages.has('mobile/astraclient.data'));
  assert.equal(run.element('launcher-profile-row').hidden, false);

  await run.element('launcher-play').listeners.click();
  await tick();
  assert.equal(run.getFullscreenCalls(), 1);
  assert.equal(run.getLockCalls(), 1);
  assert.equal(run.element('astra-rotate-overlay').hidden, false, 'Portrait fallback prompt shown when orientation lock fails');
  assert.equal(run.getAppendedScript().src, 'https://play.example.com/mobile/astraclient.js');

  // Verify on-demand SPR page request fetches 206 Partial Content and delivers into WASM memory!
  assert.equal(typeof run.context.Module.astraRequestSprPage, 'function');
  run.context.Module.astraRequestSprPage(0);
  const deadline = Date.now() + 2000;
  while (run.deliveredPages.length === 0 && Date.now() < deadline) {
    await new Promise(r => setTimeout(r, 15));
  }
  assert.equal(run.deliveredPages.length, 1);
  assert.equal(run.deliveredPages[0].ok, 1);
  assert.equal(run.deliveredPages[0].firstByte, 0x78);

  // Resizing window mid-session MUST NEVER switch profile!
  run.context.innerWidth = 1440;
  run.context.innerHeight = 900;
  if (run.winListeners.resize) run.winListeners.resize();
  assert.equal(run.context.AstraLauncher.getProfile(), 'mobile');
});

test('Desktop device selects Desktop Full, never fetches mobile bundle, and allows manual profile switch', async () => {
  const run = runDualProfileLauncher({
    userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/126.0.0.0 Safari/537.36',
    maxTouchPoints: 10, coarse: false, fine: true, hover: true, width: 1920, height: 1080
  });
  await tick(); await tick();

  assert.equal(run.context.AstraLauncher.getProfile(), 'desktop');
  assert.ok(run.fetchedUrls.some(u => u.endsWith('/desktop/asset-manifest.json')));
  assert.equal(run.fetchedUrls.some(u => u.includes('/mobile/')), false, 'Desktop must NEVER fetch mobile bundle');
  assert.deepEqual(Array.from(run.context.Module.arguments), []);
  assert.equal(run.context.Module.locateFile('astraclient.wasm'), 'https://play.example.com/desktop/astraclient.wasm');

  await run.element('launcher-play').listeners.click();
  assert.equal(run.getAppendedScript().src, 'https://play.example.com/desktop/astraclient.js');

  // Switching profile manually persists preference and reloads cleanly
  const select = run.element('web-profile-select');
  select.value = 'mobile';
  select.dispatchEvent(new Event('change'));
  assert.equal(run.storageMap.get(AstraPlatform.profileStorageKey('/astraclient.html')), 'mobile');
  assert.equal(run.getReloads(), 1);
});

test('browser_bundle paged SPR mode stages Tibia.spr.idx, writes valid spr-manifest.json, and audits cleanly', t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'astra-paged-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const source = path.join(root, 'source');
  const stageDir = path.join(root, 'stage');
  const dist = path.join(root, 'dist-mobile');
  fs.mkdirSync(source);
  fs.mkdirSync(dist);
  fs.writeFileSync(path.join(source, 'init.lua'), 'return true');
  fs.writeFileSync(path.join(source, 'Tibia.dat'), 'dat-payload');
  const sprBytes = createFakeSpr(6, 512);
  fs.writeFileSync(path.join(source, 'Tibia.spr'), sprBytes);

  const policy = { schema: 1, profile: 'mobile', sprMode: 'paged', files: ['init.lua'], things: ['Tibia.dat', 'Tibia.spr'] };
  const virtual = bundle.stage(source, policy, stageDir, source);
  assert.ok(virtual.includes('data/things/860/Tibia.spr.idx'));
  assert.equal(virtual.includes('data/things/860/Tibia.spr'), false, 'Full Tibia.spr must NOT be preloaded into mobile .data');

  const idxBytes = fs.readFileSync(path.join(stageDir, 'data/things/860/Tibia.spr.idx'));
  assert.equal(idxBytes.length, 8 + 6 * 4 + 4);
  assert.equal(idxBytes.readUInt32LE(idxBytes.length - 4), sprBytes.length);

  // Build synthetic mobile astraclient.data + astraclient.js + paged SPR artifacts
  const entries = [
    ['init.lua', Buffer.from('return true')],
    ['data/things/860/Tibia.dat', Buffer.from('dat-payload')],
    ['data/things/860/Tibia.spr.idx', idxBytes]
  ];
  let offset = 0;
  const files = entries.map(([filename, bytes]) => {
    const rec = { filename: '/' + filename, start: offset, end: offset + bytes.length };
    offset = rec.end;
    return rec;
  });
  fs.writeFileSync(path.join(dist, 'astraclient.js'), 'var PACKAGE_NAME="mobile/astraclient.data"; loadPackage(' + JSON.stringify({ files, remote_package_size: offset }) + ');');
  fs.writeFileSync(path.join(dist, 'astraclient.data'), Buffer.concat(entries.map(([, b]) => b)));

  const sprManifest = bundle.preparePagedSpr(source, dist);
  assert.doesNotThrow(() => AstraSprPager.validateSprManifest(sprManifest));

  const report = bundle.audit(dist, policy, source, source);
  assert.equal(report.sprMode, 'paged');
  assert.equal(report.fileCount, 3);
});
