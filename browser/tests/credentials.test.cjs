const assert = require('node:assert/strict');
const { test } = require('node:test');
const { webcrypto } = require('node:crypto');
const { create } = require('../credentials.js');
const fixture = require('./idb-fixture.cjs');
const location = new URL('https://play.example/client/astraclient.html');
const scope = 'https://login.example/login';
const secret = 'fictitious-password';
function vault(indexedDB, options = {}) { return create({ indexedDB, crypto: webcrypto, location, ...options }); }

test('password storage is opt-in, encrypted, non-extractable and survives a new vault', async () => {
  const idb = fixture(), first = vault(idb);
  await first.restore();
  assert.equal(first.available(), true); assert.equal(first.get(scope), '');
  assert.equal(idb.databases.get('ASTRA_CREDENTIAL_VAULT').get('vault').size, 0);
  assert.equal(first.save(scope, 'player', secret), true); await first.idle();
  const record = [...idb.databases.get('ASTRA_CREDENTIAL_VAULT').get('vault').values()][0];
  assert.equal(record.key.extractable, false);
  await assert.rejects(webcrypto.subtle.exportKey('raw', record.key));
  assert.equal(JSON.stringify(record).includes(secret), false);
  assert.equal(Buffer.from(record.payload).includes(Buffer.from(secret)), false);
  const second = vault(idb); await second.restore();
  assert.deepEqual(JSON.parse(second.get(scope)), { account: 'player', password: secret });
  assert.equal(second.get('https://other.example/login'), '');
  assert.ok(idb.handles.every(db => db.closed));
});

test('tampering, changed scope and wrong deployment never reveal saved credentials', async () => {
  for (const change of ['payload', 'scope', 'deployment']) {
    const idb = fixture(), first = vault(idb);
    await first.restore(); first.save(scope, 'player', secret); await first.idle();
    const entries = idb.databases.get('ASTRA_CREDENTIAL_VAULT').get('vault');
    const [key, record] = [...entries][0];
    if (change === 'payload') new Uint8Array(record.payload)[0] ^= 1;
    if (change === 'scope') record.scope = 'https://other.example/login';
    if (change === 'deployment') { entries.delete(key); entries.set('https://play.example/other/login', record); }
    const next = vault(idb, change === 'deployment' ? { location: new URL('https://play.example/other/client.html') } : {});
    await next.restore(); assert.equal(next.get(record.scope), '');
  }
});

test('legacy HOST:PORT:VERSION identities restore passwords for the existing WSS login path', async () => {
  const idb = fixture(), first = vault(idb), legacy = '127.0.0.1:7171:860';
  await first.restore(); assert.equal(first.save(legacy, 'player', secret), true); await first.idle();
  const next = vault(idb); await next.restore();
  assert.equal(JSON.parse(next.get(legacy)).password, secret);
  assert.equal(next.get('127.0.0.1:7172:860'), '');
});

test('Forget wins over pending encryption, is durable and does not erase other deployments', async () => {
  const idb = fixture(), first = vault(idb), other = vault(idb, { location: new URL('https://play.example/other/index.html') });
  await first.restore(); await other.restore();
  other.save(scope, 'other', secret); await other.idle();
  first.save(scope, 'player', secret); await first.forget(); await first.idle();
  assert.equal(first.get(scope), '');
  assert.equal(first.save(scope, 'player', secret), false, 'a stale checked Lua control cannot undo Forget');
  first.allowSaving(); assert.equal(first.save(scope, 'player', secret), true);
  await first.idle(); await first.forget();
  const next = vault(idb); await next.restore(); assert.equal(next.get(scope), '');
  const otherNext = vault(idb, { location: new URL('https://play.example/other/index.html') });
  await otherNext.restore(); assert.equal(JSON.parse(otherNext.get(scope)).account, 'other');
});

test('unsupported storage, rejected writes and invalid inputs do not persist plaintext or block play', async () => {
  for (const options of [{ secure: false }, { indexedDB: null }, { crypto: null }]) {
    const first = vault(fixture(), options); await first.restore();
    assert.equal(first.available(), false); assert.equal(first.save(scope, 'player', secret), false);
    await first.forget();
  }
  const idb = fixture(), notices = [], first = vault(idb, { notify: (...args) => notices.push(args) });
  await first.restore();
  for (const invalid of ['http://login.example', 'https://user:password@host/', 'https://host/#x'])
    assert.equal(first.save(invalid, 'player', secret), false);
  assert.equal(first.save(scope, 'player', 'x'.repeat(1025)), false);
  idb.failWrites = true;
  first.save(scope, 'player', secret); await first.idle();
  assert.equal(first.get(scope), ''); assert.equal(notices[0][1], true);
  assert.equal(JSON.stringify(notices).includes(secret), false);
});
