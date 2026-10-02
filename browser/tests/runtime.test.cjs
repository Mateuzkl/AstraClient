const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');

const source = fs.readFileSync(path.join(__dirname, '..', 'runtime.js'), 'utf8');
function runtime(config = {}, href = 'http://localhost:8000/client/astraclient.html', environment = {}) {
  const location = new URL(href);
  const context = {
    ASTRA_CONFIG: config, URL, URLSearchParams, location,
    document: { baseURI: href },
    console: { warn() {}, error() {} },
    ...environment
  };
  context.window = context;
  vm.runInNewContext(source, context);
  return context.AstraBrowser;
}

test('crafted query parameters cannot redirect either login transport', () => {
  const api = runtime({}, 'https://play.example/client.html?loginUrl=https://evil.example/login&gameHost=evil.example&gamePort=443&gameScheme=wss&gamePath=/steal');
  assert.equal(api.resolveWebSocketUrl('trusted.example', 7171), 'wss://trusted.example:7171/');
  assert.equal(api.resolveHttpUrl('https://trusted.example/login.php'), 'https://trusted.example/login.php');
});

test('login and game ports can use different deployment-owned bridges', () => {
  const api = runtime({ websocketOverrides: {
    '127.0.0.1:7171': '/login', '127.0.0.1:7172': '/game'
  } }, 'https://play.example/client/astraclient.html');
  assert.equal(api.resolveWebSocketUrl('127.0.0.1', 7171), 'wss://play.example/login');
  assert.equal(api.resolveWebSocketUrl('127.0.0.1', 7172), 'wss://play.example/game');
  assert.equal(api.resolveWebSocketUrl('other.example', 7172), 'wss://other.example:7172/');
});

test('explicit WebSocket URLs preserve their port, path and query', () => {
  const api = runtime();
  assert.equal(api.resolveWebSocketUrl('ws://localhost:7173/game?route=test', 7172), 'ws://localhost:7173/game?route=test');
  assert.equal(api.resolveWebSocketUrl('::1', 7171), 'ws://[::1]:7171/');
  assert.equal(api.resolveWebSocketUrl('[::1]', 7171), 'ws://[::1]:7171/');
  assert.equal(runtime({ game: { host: 'ws://localhost:7173/game' } }).resolveWebSocketUrl('server', 7172), 'ws://localhost:7173/game');
});

test('trusted legacy host, port and path configuration remains supported', () => {
  const api = runtime({ game: { host: 'bridge.example', port: 443, path: 'game', scheme: 'wss' } });
  assert.equal(api.resolveWebSocketUrl('tcp.example', 7172), 'wss://bridge.example/game');
});

test('HTTP login override and longest-prefix API rewrites are retained', () => {
  const api = runtime({ loginUrl: '/api/login', httpOverrides: {
    'http://old.example/': 'https://api.example/',
    'http://old.example/assets/': 'https://cdn.example/'
  } });
  assert.equal(api.resolveHttpUrl('http://old.example/login.php'), 'http://localhost:8000/api/login');
  assert.equal(api.resolveHttpUrl('http://old.example/assets/map.otmm'), 'https://cdn.example/map.otmm');
});

test('mixed content, non-network schemes and embedded credentials are rejected', () => {
  const api = runtime({}, 'https://play.example/client.html');
  assert.throws(() => api.resolveWebSocketUrl('ws://server.example/game', 7172), /Mixed content/);
  assert.throws(() => api.resolveGenericWebSocketUrl('https://server.example/'), /Invalid/);
  assert.throws(() => api.resolveHttpUrl('http://server.example/login'), /Mixed content/);
  for (const value of ['file:///secret', 'javascript:alert(1)', 'https://user:pass@server.example/login', 'https://server.example/login#fragment'])
    assert.throws(() => api.resolveHttpUrl(value), /Invalid/);
  assert.throws(() => api.resolveWebSocketUrl('user@server.example', 7171), /Invalid/);
  assert.throws(() => runtime({ game: { port: 70000 } }).resolveWebSocketUrl('server', 7171), /port/);
});

test('reload waits for an async flush, including failure', () => {
  for (const error of [null, new Error('storage unavailable')]) {
    const callbacks = [];
    let reloads = 0;
    const persistence = runtime().createPersistence({ syncfs(populate, callback) {
      assert.equal(populate, false);
      callbacks.push(callback);
    } }, () => { reloads++; });
    persistence.reload();
    persistence.reload();
    assert.equal(reloads, 0);
    assert.equal(callbacks.length, 1);
    callbacks.shift()(error);
    assert.equal(reloads, 1);
  }
});

test('reload during a periodic flush resyncs newer writes before reloading', () => {
  const callbacks = [];
  let reloads = 0;
  const persistence = runtime().createPersistence({ syncfs(_, callback) { callbacks.push(callback); } }, () => { reloads++; });
  persistence.sync();
  persistence.reload();
  callbacks.shift()(null);
  assert.equal(reloads, 0);
  assert.equal(callbacks.length, 1);
  callbacks.shift()(null);
  assert.equal(reloads, 1);
});

test('synchronous storage failures do not pin synchronization or block reload', () => {
  let calls = 0;
  let reloads = 0;
  const persistence = runtime().createPersistence({ syncfs() {
    calls++;
    throw new Error('IDBFS unavailable');
  } }, () => { reloads++; });
  persistence.sync();
  persistence.reload();
  assert.equal(calls, 2);
  assert.equal(reloads, 1);
});

test('a duplicate storage completion cannot unlock a newer flush', () => {
  const callbacks = [];
  const persistence = runtime().createPersistence({ syncfs(_, callback) { callbacks.push(callback); } }, () => {});
  persistence.sync();
  persistence.sync();
  callbacks[0](null);
  callbacks[0](null);
  persistence.sync();
  assert.equal(callbacks.length, 2);
  callbacks[1](null);
  assert.equal(callbacks.length, 3);
  callbacks[2](null);
});

test('storage restore completes exactly once, including synchronous failure', () => {
  const api = runtime();
  let completions = 0;
  api.restorePersistence({ syncfs(populate) {
    assert.equal(populate, true);
    throw new Error('IDBFS unavailable');
  } }, () => { completions++; });
  assert.equal(completions, 1);
  api.restorePersistence({ syncfs(_, callback) { callback(null); callback(null); } }, () => { completions++; });
  assert.equal(completions, 2);
});

function eventTarget() {
  const listeners = new Map();
  return {
    listeners,
    addEventListener(type, callback) {
      if (!listeners.has(type)) listeners.set(type, new Set());
      listeners.get(type).add(callback);
    },
    removeEventListener(type, callback) { listeners.get(type)?.delete(callback); },
    dispatch(type, event = {}) { for (const callback of listeners.get(type) || []) callback(event); },
    count() { return [...listeners.values()].reduce((sum, entries) => sum + entries.size, 0); }
  };
}

test('text bridge removes every listener, ignores late events and can be reinstalled', () => {
  const document = eventTarget();
  const editor = eventTarget();
  document.getElementById = () => editor;
  const calls = [];
  const api = runtime({}, undefined, { document });
  const module = { ccall(name, _, types, values) { calls.push([name, ...values]); } };
  const stop = api.installTextBridge(module);
  const lateInput = [...editor.listeners.get('input')][0];
  const event = { data: 'a', key: 'Enter', inputType: 'deleteContentBackward', preventDefault() {},
    clipboardData: { getData: () => 'copied' } };
  document.dispatch('paste', event);
  editor.dispatch('beforeinput', event);
  editor.dispatch('input', event);
  editor.dispatch('keydown', event);
  assert.deepEqual(calls, [['astra_browser_paste', 'copied'], ['astra_browser_virtual_key', 8],
    ['astra_browser_text_input', 'a'], ['astra_browser_virtual_key', 13]]);
  stop();
  stop();
  assert.equal(document.count() + editor.count(), 0);
  lateInput(event);
  assert.equal(calls.length, 4);
  const stopAgain = api.installTextBridge(module);
  editor.dispatch('input', event);
  assert.equal(calls.length, 5);
  stopAgain();
  assert.equal(document.count() + editor.count(), 0);
});

test('persistence hooks release timers and listeners and ignore late ticks', () => {
  const host = eventTarget();
  const document = eventTarget();
  document.visibilityState = 'hidden';
  let tick;
  let clears = 0;
  let flushes = 0;
  const api = runtime({}, undefined, { document,
    addEventListener: host.addEventListener, removeEventListener: host.removeEventListener,
    setInterval(callback, milliseconds) { assert.equal(milliseconds, 15000); tick = callback; return 42; },
    clearInterval(id) { assert.equal(id, 42); clears++; }
  });
  const stop = api.installPersistenceHooks(() => { flushes++; });
  tick();
  host.dispatch('pagehide');
  document.dispatch('visibilitychange');
  assert.equal(flushes, 3);
  stop();
  assert.equal(clears, 1);
  assert.equal(host.count() + document.count(), 0);
  tick();
  assert.equal(flushes, 3);
});
