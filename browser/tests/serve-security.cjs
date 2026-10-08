'use strict';
// Servidor SOMENTE loopback para testar CSP/COOP/COEP no browser real, sem TLS falso.
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const root = fs.realpathSync(process.argv[2]);
const port = Number(process.argv[3] || 18085);
const source = fs.readFileSync(path.join(__dirname, '../nginx.conf.example'), 'utf8');
const csp = source.match(/add_header Content-Security-Policy "([^"]+)"/)[1];
const mime = { '.html': 'text/html', '.js': 'application/javascript', '.json': 'application/json',
  '.css': 'text/css', '.wasm': 'application/wasm', '.png': 'image/png' };
let redirected = 0;
const server = http.createServer((req, res) => {
  res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
  res.setHeader('Cross-Origin-Embedder-Policy', 'require-corp');
  res.setHeader('Cross-Origin-Resource-Policy', 'same-origin');
  res.setHeader('Content-Security-Policy', csp);
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Referrer-Policy', 'no-referrer');
  const name = new URL(req.url, 'http://localhost').pathname;
  if (req.method === 'POST' && ['/ok', '/307', '/308', '/target'].includes(name)) {
    let size = 0;
    req.on('data', bytes => { size += bytes.length; if (size > 1024) req.destroy(); });
    req.on('end', () => {
      if (name === '/target') redirected++;
      if (name === '/307' || name === '/308') { res.writeHead(Number(name.slice(1)), { Location: '/target' }); res.end(); }
      else { res.setHeader('Content-Type', 'application/json'); res.end(JSON.stringify({ ok: true, redirected })); }
    }); return;
  }
  if (name === '/security-test.html') {
    res.setHeader('Content-Type', 'text/html');
    res.end('<!doctype html><title>Astra browser security fixture</title><pre id="result">Running</pre>' +
      '<script src="security.js"></script><script src="security-test.js"></script>'); return;
  }
  if (name === '/security-test.js') {
    res.setHeader('Content-Type', 'application/javascript');
    res.end(`(async () => {
      const posts = AstraSecurity.createPosts(fetch.bind(window));
      const send = code => new Promise(resolve => posts.start(code, '/' + code, 'fictitious-test-only', {}, 2000,
        (status, bytes, headers, error) => resolve({status, bytes, error})));
      const results = [];
      for (const code of [307, 308]) { const r = await send(code); results.push(code + ': ' + (r.status === 0 ? 'PASS' : 'FAIL')); }
      const r = await new Promise(resolve => posts.start(1, '/ok', 'fictitious-test-only', {}, 2000,
        (status, bytes) => resolve({status, data: JSON.parse(new TextDecoder().decode(bytes))})));
      results.push('no redirected bodies: ' + (r.data.redirected === 0 ? 'PASS' : 'FAIL'));
      results.push('legitimate POST: ' + (r.status === 200 ? 'PASS' : 'FAIL'));
      results.push('pending requests: ' + posts.pendingCount());
      document.getElementById('result').textContent = results.join('\\n');
    })().catch(() => { document.getElementById('result').textContent = 'FAIL'; });`); return;
  }
  if (name === '/config.js') {
    res.setHeader('Content-Type', 'application/javascript');
    res.end('window.ASTRA_CONFIG = {performance: true};'); return;
  }
  let file;
  try { file = fs.realpathSync(path.join(root, decodeURIComponent(name === '/' ? '/astraclient.html' : name))); }
  catch (_) { res.writeHead(404); res.end(); return; }
  if (!file.startsWith(root + path.sep) || !fs.statSync(file).isFile()) { res.writeHead(404); res.end(); return; }
  res.setHeader('Content-Type', mime[path.extname(file)] || 'application/octet-stream');
  res.setHeader('Content-Length', fs.statSync(file).size);
  fs.createReadStream(file).pipe(res);
});
server.listen(port, '127.0.0.1', () => console.log('CSP test: http://localhost:' + port + '/astraclient.html'));
