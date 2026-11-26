'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const os = require('node:os');
const path = require('node:path');
const { spawn } = require('node:child_process');
const { test } = require('node:test');

function fetchRaw(port, urlPath, headers = {}) {
  return new Promise((resolve, reject) => {
    const req = http.get({ hostname: '127.0.0.1', port, path: urlPath, headers }, res => {
      const chunks = [];
      res.on('data', c => chunks.push(c));
      res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, body: Buffer.concat(chunks) }));
    });
    req.on('error', reject);
  });
}

test('serve.py supports HTTP 206 Range requests for demand-paged SPR with COOP/COEP headers', async t => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'astra-serve-range-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  fs.writeFileSync(path.join(dir, 'astraclient.html'), '<!doctype html><title>Astra</title>');
  const payload = Buffer.from('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ');
  fs.writeFileSync(path.join(dir, 'Tibia.spr'), payload);

  const port = 18910 + Math.floor(Math.random() * 500);
  const python = process.platform === 'win32' ? 'python' : 'python3';
  const child = spawn(python, ['-u', path.join(__dirname, '../serve.py'), dir, '--bind', '127.0.0.1', '--port', String(port)], {
    stdio: ['ignore', 'pipe', 'pipe']
  });
  t.after(() => child.kill());

  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('serve.py startup timeout')), 5000);
    child.stdout.on('data', chunk => {
      if (String(chunk).includes('Serving')) { clearTimeout(timer); resolve(); }
    });
    child.on('exit', code => { clearTimeout(timer); reject(new Error(`serve.py exited ${code}`)); });
  });

  const partial = await fetchRaw(port, '/Tibia.spr', { Range: 'bytes=10-19' });
  assert.equal(partial.status, 206);
  assert.equal(partial.headers['cross-origin-opener-policy'], 'same-origin');
  assert.equal(partial.headers['cross-origin-embedder-policy'], 'require-corp');
  assert.equal(partial.headers['accept-ranges'], 'bytes');
  assert.equal(partial.headers['content-range'], `bytes 10-19/${payload.length}`);
  assert.equal(partial.body.toString('ascii'), 'ABCDEFGHIJ');

  const oob = await fetchRaw(port, '/Tibia.spr', { Range: 'bytes=999-1000' });
  assert.equal(oob.status, 416);
});
