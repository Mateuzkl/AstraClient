'use strict';
// Integracao real, opcional localmente: ASTRA_NGINX=nginx ASTRA_WEB_DIST=/path/dist node --test ...
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const http = require('node:http');
const https = require('node:https');
const { createHash } = require('node:crypto');
const { spawnSync } = require('node:child_process');
const { test } = require('node:test');
test('nginx TLS, exact Origin, binary WSS routing and production headers',
  { skip: !process.env.ASTRA_NGINX }, async t => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'astra-nginx-'));
  const root = process.env.ASTRA_WEB_DIST || directory;
  const cert = path.join(directory, 'cert.pem'), key = path.join(directory, 'key.pem');
  let result = spawnSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
    '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1', '-keyout', key, '-out', cert]);
  assert.equal(result.status, 0);
  const upstreams = [];
  for (const name of ['login', 'game']) {
    const service = http.createServer();
    service.on('upgrade', (req, socket) => {
      const accept = createHash('sha1').update(req.headers['sec-websocket-key'] +
        '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64');
      socket.end(Buffer.concat([Buffer.from('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n' +
        'Sec-WebSocket-Accept: ' + accept + '\r\nX-Test-Route: ' + name + '\r\n\r\n'), Buffer.from([0x82, 3, 97, 98, 99])]));
    });
    await new Promise(resolve => service.listen(0, '127.0.0.1', resolve));
    upstreams.push(service);
  }
  let config = fs.readFileSync(path.join(__dirname, '../nginx.conf.example'), 'utf8')
    .replaceAll('play.example.com', 'localhost')
    .replace('"https://localhost" 1', '"https://localhost:18443" 1')
    .replace('listen 80;', 'listen 127.0.0.1:18080;')
    .replace('listen 443 ssl;', 'listen 127.0.0.1:18443 ssl;')
    .replace('https://localhost$request_uri', 'https://localhost:18443$request_uri')
    .replace('root /srv/astraclient;', 'root ' + root + ';')
    .replace('/etc/letsencrypt/live/localhost/fullchain.pem', cert)
    .replace('/etc/letsencrypt/live/localhost/privkey.pem', key)
    .replace('/var/log/nginx/astra-error.log', path.join(directory, 'error.log'))
    .replace('127.0.0.1:7174', '127.0.0.1:' + upstreams[0].address().port)
    .replace('127.0.0.1:7173', '127.0.0.1:' + upstreams[1].address().port);
  fs.writeFileSync(path.join(directory, 'nginx.conf'), 'pid ' + path.join(directory, 'nginx.pid') + ';\n' +
    'error_log ' + path.join(directory, 'main-error.log') + ';\nevents {}\nhttp { access_log off; include /etc/nginx/mime.types;\n' + config + '\n}');
  const args = ['-p', directory + '/', '-c', 'nginx.conf'];
  t.after(() => {
    spawnSync(process.env.ASTRA_NGINX, [...args, '-s', 'quit']);
    for (const server of upstreams) { server.closeAllConnections(); server.close(); }
    // Diretorio temporario nao e publicado e sera removido pelo runner/OS.
  });
  result = spawnSync(process.env.ASTRA_NGINX, [...args, '-t']);
  assert.equal(result.status, 0, result.stderr.toString());
  result = spawnSync(process.env.ASTRA_NGINX, args);
  assert.equal(result.status, 0, result.stderr.toString());
  const options = { hostname: '127.0.0.1', port: 18443, ca: fs.readFileSync(cert) };
  function request(route, origin, upgrade = false) {
    return new Promise((resolve, reject) => {
      const req = https.get({ ...options, path: route, headers: {
        ...(origin == null ? {} : { Origin: origin }), ...(upgrade ? { Upgrade: 'websocket', Connection: 'Upgrade',
          'Sec-WebSocket-Version': '13', 'Sec-WebSocket-Key': Buffer.alloc(16, 1).toString('base64') } : {}) } });
      req.on('response', res => { res.resume(); res.on('end', () => resolve({ status: res.statusCode, headers: res.headers })); });
      req.on('upgrade', (res, socket, head) => {
        let bytes = head;
        socket.on('data', data => { bytes = Buffer.concat([bytes, data]); });
        socket.on('end', () => { socket.destroy(); resolve({ status: res.statusCode, headers: res.headers, bytes }); });
      });
      req.on('error', reject); req.setTimeout(3000, () => req.destroy(new Error('timeout')));
    });
  }
  for (const route of ['/login', '/game']) {
    for (const origin of [undefined, 'https://evil.example', 'https://localhost:18443.evil.example'])
      assert.equal((await request(route, origin, true)).status, 403);
    const good = await request(route, 'https://localhost:18443', true);
    assert.equal(good.status, 101); assert.equal(good.headers['x-test-route'], route.slice(1));
    assert.equal(good.bytes.toString('hex'), '8203616263');
  }
  const page = await request('/astraclient.html');
  assert.equal(page.headers['cross-origin-opener-policy'], 'same-origin');
  assert.equal(page.headers['cross-origin-embedder-policy'], 'require-corp');
  assert.equal(page.headers['referrer-policy'], 'no-referrer');
  assert.match(page.headers['content-security-policy'], /wasm-unsafe-eval/);
  assert.doesNotMatch(page.headers['content-security-policy'], /script-src[^;]*'unsafe-(?:eval|inline)'/);
  if (process.env.ASTRA_WEB_DIST) assert.equal((await request('/astraclient.wasm')).headers['content-type'], 'application/wasm');
  assert.equal((await request('/.env')).status, 404);
  assert.notEqual((await request('/game/extra', 'https://localhost:18443', true)).status, 101);
  await new Promise((resolve, reject) => http.get('http://127.0.0.1:18080/astraclient.html', res => {
    assert.equal(res.statusCode, 308); assert.equal(res.headers.location, 'https://localhost:18443/astraclient.html'); res.resume(); resolve();
  }).on('error', reject));
});
