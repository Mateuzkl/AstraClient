const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const http = require('node:http');
const { test } = require('node:test');
const securitySource = fs.readFileSync(path.join(__dirname, '../security.js'), 'utf8');
const runtimeSource = fs.readFileSync(path.join(__dirname, '../runtime.js'), 'utf8');
function environment(href = 'https://play.example/astraclient.html') {
  const context = { URL, URLSearchParams, location: new URL(href), document: { baseURI: href },
    console: { warn() {}, error() {} }, AbortController, setTimeout, clearTimeout };
  context.window = context;
  vm.runInNewContext(securitySource + '\n' + runtimeSource, context);
  return context;
}

test('legacy credentials are removed recursively without erasing player preferences', () => {
  const api = environment().AstraSecurity;
  const old = 'account: remembered\npassword: fictitious\n"sessionKey": fake\nAuto_Login: true\n' +
    'nested:\n  access_token:\n    secret: fake\n  hotkeys:\n    F1: exura\nminimap: custom\nquickloot: true\n';
  const clean = api.scrubSettings(old);
  assert.equal(clean, 'account: remembered\nnested:\n  hotkeys:\n    F1: exura\nminimap: custom\nquickloot: true\n');
  assert.equal(api.scrubSettings(clean), clean);
});

test('IDBFS migration is durably flushed before startup and completes exactly once', () => {
  const env = environment();
  const callbacks = [];
  let text = 'password: fake\naccount: remembered\n', ready = 0;
  const fs = { analyzePath: () => ({ exists: true }), readFile: () => text,
    writeFile: (_, value) => { text = value; }, syncfs: (populate, cb) => { callbacks.push([populate, cb]); } };
  env.AstraBrowser.restorePersistence(fs, error => { assert.equal(error, null); ready++; });
  assert.equal(callbacks[0][0], true);
  callbacks[0][1](null); callbacks[0][1](null);
  assert.equal(ready, 0); assert.equal(callbacks.length, 2);
  assert.equal(callbacks[1][0], false);
  assert.equal(text, 'account: remembered\n');
  callbacks[1][1](null); callbacks[1][1](null);
  assert.equal(ready, 1);
  text += 'gtoken: fake\n';
  env.AstraBrowser.createPersistence(fs, () => {}).sync();
  assert.equal(text, 'account: remembered\n');
  callbacks[2][1](null);
});

test('migration errors stop startup rather than loading legacy secrets', () => {
  const env = environment();
  let seen, calls = 0;
  env.AstraBrowser.restorePersistence({ syncfs: (_, cb) => cb(null),
    analyzePath: () => ({ exists: true }), readFile: () => 'password: fake',
    writeFile: () => { throw new Error('storage'); } }, err => { seen = err; calls++; });
  assert.equal(calls, 1); assert.match(seen.message, /storage/);
});

test('production requires HTTPS and rejects remote plaintext even on a local page', () => {
  const remote = environment('http://play.example/client.html').AstraBrowser;
  assert.throws(() => remote.assertSecurePage(), /requires HTTPS/);
  assert.throws(() => remote.resolveHttpUrl('https://api.example/login'), /requires HTTPS/);
  const local = environment('http://localhost:8080/client.html').AstraBrowser;
  for (const url of ['http://evil.example/login', 'http://localhost.evil.example/login'])
    assert.throws(() => local.resolveHttpUrl(url), /Mixed content/);
  assert.throws(() => local.resolveGenericWebSocketUrl('ws://evil.example/game'), /Mixed content/);
  assert.equal(local.resolveHttpUrl('http://127.0.0.1:9000/login'), 'http://127.0.0.1:9000/login');
});

test('real 307/308 redirects never receive the POST body at the redirect target', async t => {
  let redirected = 0, originals = 0;
  const server = http.createServer((req, res) => {
    if (req.url === '/target') { redirected++; res.end('wrong'); return; }
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      assert.equal(body, 'fictitious-test-credential'); originals++;
      if (req.url === '/ok') { res.end('ok'); return; }
      res.writeHead(Number(req.url.slice(1)), { location: '/target' }); res.end();
    });
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => { server.closeAllConnections(); server.close(); });
  const posts = environment().AstraSecurity.createPosts(fetch);
  const send = code => new Promise(resolve => posts.start(code, `http://127.0.0.1:${server.address().port}/${code}`,
    'fictitious-test-credential', {}, 2000, (status, bytes, headers, error) => resolve({ status, bytes, error })));
  for (const code of [307, 308]) { const result = await send(code); assert.equal(result.status, 0); assert.match(result.error, /redirects/); }
  assert.equal(redirected, 0); assert.equal(originals, 2); assert.equal(posts.pendingCount(), 0);
  const result = await new Promise(resolve => posts.start(9, `http://127.0.0.1:${server.address().port}/ok`,
    'fictitious-test-credential', {}, 2000, (status, bytes, _, error) => resolve({ status, bytes, error })));
  assert.equal(result.status, 200); assert.equal(Buffer.from(result.bytes).toString(), 'ok');
});

test('POST cancellation, replacement, timeout and late callbacks release ownership', async () => {
  const resolvers = [];
  const posts = environment().AstraSecurity.createPosts((_, options) => new Promise(resolve => resolvers.push({ resolve, options })));
  let called = 0;
  posts.start(1, '/login', new Uint8Array(), {}, 1000, () => called++);
  const first = resolvers[0];
  assert.equal(first.options.redirect, 'error'); assert.equal(first.options.credentials, 'omit');
  assert.equal(first.options.referrerPolicy, 'no-referrer');
  posts.start(1, '/login', new Uint8Array(), {}, 1000, () => called++);
  assert.equal(first.options.signal.aborted, true);
  posts.cancel(1); posts.cancel(1);
  for (const item of resolvers) item.resolve(new Response('late'));
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(called, 0); assert.equal(posts.pendingCount(), 0);
  await new Promise(resolve => posts.start(3, '/login', '', {}, 10, (_, __, ___, err) => {
    called++; assert.match(err, /timed out/); resolve();
  }));
  resolvers[2].resolve(new Response('late'));
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(called, 1); assert.equal(posts.pendingCount(), 0);
});

test('oversized and failing streams return generic errors without response secrets', async () => {
  for (const response of [new Response('12345'), new Response('x', { headers: { 'content-length': '50' } }),
    new Response(new ReadableStream({ start(c) { c.error(new Error('secret-body-do-not-print')); } }))]) {
    const posts = environment().AstraSecurity.createPosts(async () => response, 4);
    await new Promise(resolve => posts.start(1, '/login', '', {}, 1000, (status, bytes, _, error) => {
      assert.equal(status, 0); assert.equal(bytes.length, 0); assert.doesNotMatch(error, /secret-body/); resolve();
    }));
    assert.equal(posts.pendingCount(), 0);
  }
});

test('the production POST budget rejects declared responses larger than 16 MiB', async () => {
  const posts = environment().AstraSecurity.createPosts(async () =>
    new Response('not consumed', { headers: { 'content-length': String(16 * 1024 * 1024 + 1) } }));
  await new Promise(resolve => posts.start(1, '/login', '', {}, 1000, (status, bytes, _, error) => {
    assert.equal(status, 0); assert.equal(bytes.length, 0); assert.match(error, /failed/); resolve();
  }));
  assert.equal(posts.pendingCount(), 0);
});
