const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');

const source = fs.readFileSync(path.join(__dirname, '..', 'runtime.js'), 'utf8');
function runtime(config = {}, href = 'http://localhost:8000/client/astraclient.html') {
  const location = new URL(href);
  const context = {
    ASTRA_CONFIG: config, URL, URLSearchParams, location,
    document: { baseURI: href },
    console: { warn() {}, error() {} }
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
