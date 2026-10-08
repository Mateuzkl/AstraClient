'use strict';

// Loopback-only services for the production C++ transport. No npm packages,
// Python, public endpoints, or changes to the operating system trust store.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const https = require('node:https');
const os = require('node:os');
const path = require('node:path');
const { createHash } = require('node:crypto');
const { spawn, spawnSync } = require('node:child_process');

function run(executable, args) {
  return new Promise((resolve, reject) => {
    const child = spawn(executable, args, { stdio: 'inherit', windowsHide: true });
    const timer = setTimeout(() => { child.kill(); reject(new Error(`Timed out: ${args.join(' ')}`)); },
      args[0] === 'lifecycle' ? 60000 : 20000);
    child.once('error', error => { clearTimeout(timer); reject(error); });
    child.once('exit', (code, signal) => {
      clearTimeout(timer);
      if (code === 0) resolve();
      else reject(new Error(`Failed (${code ?? signal}): ${args.join(' ')}`));
    });
  });
}

function frame(opcode, payload, final = true) {
  const size = payload.length;
  const header = Buffer.alloc(size < 126 ? 2 : size < 65536 ? 4 : 10);
  header[0] = opcode | (final ? 128 : 0);
  header[1] = size < 126 ? size : size < 65536 ? 126 : 127;
  if (size >= 65536) header.writeBigUInt64BE(BigInt(size), 2);
  else if (size >= 126) header.writeUInt16BE(size, 2);
  return Buffer.concat([header, payload]);
}

function upgrade(request, socket, head) {
  const accept = createHash('sha1').update(request.headers['sec-websocket-key'] +
    '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64');
  socket.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n' +
    `Connection: Upgrade\r\nSec-WebSocket-Accept: ${accept}\r\n\r\n`);
  if (request.url === '/drop') { socket.destroy(); return; }
  if (request.url === '/backpressure') {
    socket.pause(); // Real kernel backpressure, not a mocked curl_ws_send.
    const resume = setTimeout(() => socket.resume(), 250);
    socket.once('close', () => clearTimeout(resume));
  }
  let buffered = Buffer.alloc(0);
  const consume = data => {
    buffered = Buffer.concat([buffered, data]);
    while (buffered.length >= 2) {
      const opcode = buffered[0], lengthCode = buffered[1] & 127;
      const headerSize = lengthCode === 127 ? 10 : lengthCode === 126 ? 4 : 2;
      if (buffered.length < headerSize + 4) return;
      const size = lengthCode === 127 ? Number(buffered.readBigUInt64BE(2)) :
        lengthCode === 126 ? buffered.readUInt16BE(2) : lengthCode;
      if (!Number.isSafeInteger(size) || size > 16 * 1024 * 1024 || !(buffered[1] & 128)) {
        socket.destroy(new Error('Invalid client WebSocket frame'));
        return;
      }
      if (buffered.length < headerSize + 4 + size) return;
      const mask = buffered.subarray(headerSize, headerSize + 4);
      const payload = Buffer.from(buffered.subarray(headerSize + 4, headerSize + 4 + size));
      for (let i = 0; i < size; ++i) payload[i] ^= mask[i % 4];
      buffered = buffered.subarray(headerSize + 4 + size);
      if ((opcode & 15) === 8) { socket.end(frame(8, Buffer.from([3, 232]))); return; }
      if ((opcode & 15) === 10) continue; // Reply to the test ping.
      assert.equal(opcode, 0x81);
      if (request.url === '/oversized') {
        socket.write(frame(2, Buffer.alloc(16 * 1024 * 1024 + 1, 'x')));
      } else if (request.url === '/multiple') {
        socket.write(Buffer.concat([frame(2, Buffer.alloc(0)), frame(2, payload), frame(2, payload)]));
      } else if (request.url === '/fragmented') {
        const half = Math.floor(size / 2);
        socket.write(frame(1, payload.subarray(0, half), false));
        socket.write(frame(9, Buffer.from('ping')));
        socket.write(frame(0, payload.subarray(half)));
      } else {
        socket.write(frame(2, payload)); // Binary payload remains byte-transparent.
      }
    }
  };
  socket.on('data', consume);
  if (head.length) consume(head);
}

function handler(request, response) {
  const reply = (status, body = 'Astra HTTP test', headers = {}) => {
    response.writeHead(status, { 'Content-Length': Buffer.byteLength(body), ...headers });
    response.end(body);
  };
  if (request.method === 'POST') {
    const chunks = [];
    request.on('data', chunk => chunks.push(chunk));
    request.on('end', () => {
      const redirect = /^\/post-cross-(301|302|303|307|308)$/.exec(request.url);
      if (redirect) reply(Number(redirect[1]), '', { Location: request.socket.server.postRedirectTarget });
      else if (request.url === '/post-redirect') reply(307, '', { Location: '/echo' });
      else reply(200, Buffer.concat(chunks));
    });
  } else if (request.url === '/test.crl') {
    reply(200, request.socket.server.crlData, { 'Content-Type': 'application/pkix-crl' });
  } else if (request.url === '/redirect') {
    reply(302, 'discard this redirect body', { Location: '/ok' });
  } else if (request.url === '/upgrade') {
    reply(302, '', { Location: request.socket.server.upgradeTarget });
  } else if (request.url === '/downgrade') {
    reply(302, '', { Location: request.socket.server.postRedirectTarget });
  } else if (request.url === '/loop') {
    reply(302, '', { Location: '/loop' });
  } else if (request.url === '/missing') {
    reply(404);
  } else if (request.url === '/empty') {
    reply(204, '');
  } else if (request.url === '/chunked') {
    response.writeHead(200, { 'Transfer-Encoding': 'chunked' });
    response.write('Astra '); response.write('HTTP '); response.end('test');
  } else if (request.url === '/slow') {
    response.writeHead(200, { 'Content-Length': 65536 });
    let remaining = 16;
    const timer = setInterval(() => {
      response.write(Buffer.alloc(4096, 'x'));
      if (--remaining === 0) { clearInterval(timer); response.end(); }
    }, 20);
    response.once('close', () => clearInterval(timer));
  } else {
    reply(200);
  }
}

async function listen(server, host = '127.0.0.1') {
  const sockets = new Set();
  server.on('connection', socket => {
    sockets.add(socket);
    socket.once('close', () => sockets.delete(socket));
    socket.on('error', () => {}); // Cancellation is intentional.
  });
  server.on('upgrade', upgrade);
  server.on('tlsClientError', () => {}); // Untrusted/expired certificates are intentional.
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, host, resolve);
  });
  return { port: server.address().port, close: () => {
    for (const socket of sockets) socket.destroy();
    return new Promise(resolve => server.close(resolve));
  } };
}

async function tlsCases(executable, directory, publisher, port) {
  const openssl = process.env.OPENSSL_BIN || (process.platform === 'win32' ?
    'C:/Program Files/Git/usr/bin/openssl.exe' : 'openssl');
  const opensslRun = args => {
    const result = spawnSync(openssl, args, { cwd: directory, encoding: 'utf8', windowsHide: true });
    assert.equal(result.status, 0, result.error?.message || result.stderr);
  };
  fs.mkdirSync(path.join(directory, 'certs'));
  fs.writeFileSync(path.join(directory, 'index'), '');
  fs.writeFileSync(path.join(directory, 'serial'), '1000\n');
  fs.writeFileSync(path.join(directory, 'crlnumber'), '1000\n');
  fs.writeFileSync(path.join(directory, 'ca.cnf'), `[ca]
default_ca = test
[test]
database = index
new_certs_dir = certs
certificate = ca.pem
private_key = ca.key
serial = serial
crlnumber = crlnumber
default_md = sha256
default_days = 2
default_crl_days = 2
policy = policy
unique_subject = no
[policy]
commonName = supplied
[server]
basicConstraints = critical,CA:FALSE
extendedKeyUsage = serverAuth
authorityKeyIdentifier = keyid,issuer
subjectAltName = DNS:localhost
crlDistributionPoints = URI:http://127.0.0.1:${port}/test.crl
[wronghost]
basicConstraints = critical,CA:FALSE
extendedKeyUsage = serverAuth
authorityKeyIdentifier = keyid,issuer
subjectAltName = DNS:other.invalid
crlDistributionPoints = URI:http://127.0.0.1:${port}/test.crl
`);
  opensslRun(['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '2', '-sha256',
    '-subj', '/CN=Astra regression CA', '-addext', 'basicConstraints=critical,CA:TRUE',
    '-addext', 'keyUsage=critical,keyCertSign,cRLSign', '-keyout', 'ca.key', '-out', 'ca.pem']);
  opensslRun(['ca', '-batch', '-config', 'ca.cnf', '-gencrl', '-out', 'test.crl.pem']);
  opensslRun(['crl', '-in', 'test.crl.pem', '-outform', 'DER', '-out', 'test.crl']);
  publisher.crlData = fs.readFileSync(path.join(directory, 'test.crl'));
  for (const kind of ['server', 'wronghost', 'expired']) {
    opensslRun(['req', '-new', '-newkey', 'rsa:2048', '-nodes', '-subj', '/CN=localhost',
      '-keyout', `${kind}.key`, '-out', `${kind}.csr`]);
    const dates = kind === 'expired' ? ['-startdate', '20000101000000Z', '-enddate', '20000102000000Z'] : [];
    opensslRun(['ca', '-batch', '-notext', '-config', 'ca.cnf', '-extensions',
      kind === 'wronghost' ? 'wronghost' : 'server', '-in', `${kind}.csr`, '-out', `${kind}.pem`, ...dates]);
    const secure = https.createServer({ key: fs.readFileSync(path.join(directory, `${kind}.key`)),
      cert: fs.readFileSync(path.join(directory, `${kind}.pem`)), minVersion: 'TLSv1.2' }, handler);
    const service = await listen(secure);
    secure.postRedirectTarget = publisher.postRedirectTarget;
    publisher.upgradeTarget = `https://localhost:${service.port}/ok`;
    try {
      const url = `https://localhost:${service.port}/ok`;
      await run(executable, ['tls', url, kind === 'server' ? 'success' : 'failure', path.join(directory, 'ca.pem')]);
      if (kind === 'server') await run(executable, ['tls', url, 'failure']);
      if (kind === 'server') {
        const ca = path.join(directory, 'ca.pem');
        await run(executable, ['tls-get', `http://127.0.0.1:${port}/upgrade`, 'success', ca]);
        await run(executable, ['tls-get', `https://localhost:${service.port}/redirect`, 'success', ca]);
        await run(executable, ['tls-get', `https://localhost:${service.port}/downgrade`, 'failure', ca]);
        await run(executable, ['tls-post', `https://localhost:${service.port}/post-cross-307`, 'failure', ca]);
        await run(executable, ['tls-ws', `wss://localhost:${service.port}/idle`, 'success', ca]);
        await run(executable, ['ws', `wss://localhost:${service.port}/idle`, 'failure']);
      }
    } finally { await service.close(); }
  }
}

async function main() {
  assert(process.argv[2], 'Usage: node native_network_fixture.cjs network.exe [temporary-root]');
  const executable = path.resolve(process.argv[2]);
  const directory = fs.mkdtempSync(path.join(path.resolve(process.argv[3] || os.tmpdir()), 'astra-network-'));
  const server = http.createServer(handler);
  const service = await listen(server);
  let foreignRequests = 0;
  const sink = await listen(http.createServer((request, response) => {
    ++foreignRequests;
    request.resume();
    response.end('Astra HTTP test');
  }));
  server.postRedirectTarget = `http://127.0.0.1:${sink.port}/echo`;
  const base = `127.0.0.1:${service.port}`;
  try {
    for (const endpoint of ['ok', 'redirect', 'chunked', 'empty'])
      await run(executable, ['get', `http://${base}/${endpoint}`, 'success']);
    for (const endpoint of ['missing', 'loop'])
      await run(executable, ['get', `http://${base}/${endpoint}`, 'failure']);
    await run(executable, ['post', `http://${base}/echo`, 'success']);
    await run(executable, ['post', `http://${base}/post-redirect`, 'failure']);
    for (const status of [301, 302, 303, 307, 308])
      await run(executable, ['post', `http://${base}/post-cross-${status}`, 'failure']);
    assert.equal(foreignRequests, 0, 'POST redirect forwarded a request to a different origin');
    for (const mode of ['cancel', 'cancel-progress', 'bad-header'])
      await run(executable, [mode, `http://${base}/slow`, 'failure']);
    for (const [mode, endpoint] of [['ws', 'echo'], ['ws', 'fragmented'], ['ws-large', 'echo'],
      ['ws-late', 'echo'], ['ws-idle', 'idle'], ['ws-close-open', 'idle'],
      ['ws-cancel-handshake', 'idle'], ['ws-multiple', 'multiple'], ['ws-reconnect', 'echo'],
      ['ws-backpressure', 'backpressure']])
      await run(executable, [mode, `ws://${base}/${endpoint}`, 'success']);
    for (const [mode, endpoint] of [['ws-send-limit', 'idle'], ['ws-recv-limit', 'oversized'],
      ['ws-close-error', 'drop'], ['ws-drop', 'drop']])
      await run(executable, [mode, `ws://${base}/${endpoint}`, 'failure']);
    await run(executable, ['ws-timeout', `ws://${base}/idle`, 'failure']);
    await run(executable, ['ws', `http://${base}/ok`, 'failure']);
    await run(executable, ['lifecycle', `http://${base}`, 'success', process.env.ASTRA_NETWORK_CYCLES || '200']);
    await run(executable, ['cancel-batch', `http://${base}`, 'success']);
    let ipv6;
    try { ipv6 = await listen(http.createServer(handler), '::1'); }
    catch (error) {
      if (!['EADDRNOTAVAIL', 'EAFNOSUPPORT'].includes(error.code)) throw error;
      console.log(`IPv6 loopback unavailable: ${error.code} (SKIP)`);
    }
    if (ipv6) {
      try {
        await run(executable, ['get', `http://[::1]:${ipv6.port}/redirect`, 'success']);
        await run(executable, ['ws', `ws://[::1]:${ipv6.port}/fragmented`, 'success']);
      } finally { await ipv6.close(); }
    }
    await tlsCases(executable, directory, server, service.port);
    assert.equal(foreignRequests, 0, 'A forbidden POST redirect or HTTPS downgrade reached the destination');
    console.log('Native HTTP/TLS/WebSocket/cancellation regressions: PASS');
  } finally {
    await service.close();
    await sink.close();
    fs.rmSync(directory, { recursive: true, force: true }); // Only our fresh temporary directory.
  }
}

main().catch(error => { console.error(error); process.exitCode = 1; });
