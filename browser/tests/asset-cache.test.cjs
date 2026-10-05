const assert = require('node:assert/strict');
const { test } = require('node:test');
globalThis.crypto ||= require('node:crypto').webcrypto;
const api = require('../asset-cache.js');

const digest = async bytes => Buffer.from(await crypto.subtle.digest('SHA-256', bytes)).toString('hex');
async function fixture(text = 'Astra game data') {
  const bytes = new TextEncoder().encode(text);
  const sha256 = await digest(bytes);
  const manifest = api.validateManifest({ schema: 1, version: '8.60', packageName: 'dist/astraclient.data',
    file: 'astraclient.data', uuid: 'sha256-' + sha256, size: bytes.length, chunks: [{ size: bytes.length, sha256 }] });
  const store = { meta: null, chunks: new Map(),
    async getMeta() { return this.meta; }, async putMeta(value) { this.meta = value; },
    async getChunk(i) { return this.chunks.get(i); }, async putChunk(i, value) { this.chunks.set(i, value); },
    async remove() { this.meta = null; this.chunks.clear(); }
  };
  const fetchData = () => Promise.resolve(new Response(bytes));
  return { bytes, manifest, store, fetchData };
}

test('install writes SDK-compatible chunks and commits metadata after verified writes', async () => {
  const { bytes, manifest, store, fetchData } = await fixture();
  const events = [];
  const putChunk = store.putChunk.bind(store);
  store.putChunk = async (i, value) => { assert.equal(store.meta, null); events.push('chunk'); await putChunk(i, value); };
  const putMeta = store.putMeta.bind(store);
  store.putMeta = async value => { events.push('meta'); await putMeta(value); };
  assert.equal(await api.state(store, manifest), 'missing');
  await api.install(store, manifest, fetchData);
  assert.deepEqual(events, ['chunk', 'meta']);
  assert.equal(await api.state(store, manifest), 'installed');
  assert.equal(await api.verify(store, manifest), true);
  assert.deepEqual(new Uint8Array(await store.getChunk(0)), bytes);
  // Existing SDK metadata has only uuid and chunkCount; migration is supported.
  delete store.meta.size;
  assert.equal(await api.verify(store, manifest), true);
});

test('corrupt, partial, evicted and outdated cache entries cannot pass Play verification', async () => {
  const { manifest, store, fetchData } = await fixture();
  await api.install(store, manifest, fetchData);
  const original = store.chunks.get(0);
  store.chunks.set(0, new ArrayBuffer(original.byteLength));
  assert.equal(await api.verify(store, manifest), false);
  assert.equal(store.meta, null, 'failed verification invalidates trusted installation');
  await api.install(store, manifest, fetchData);
  store.chunks.delete(0);
  assert.equal(await api.verify(store, manifest), false);
  await api.install(store, manifest, fetchData);
  store.meta.uuid = 'sha256-' + 'a'.repeat(64);
  assert.equal(await api.state(store, manifest), 'outdated');
  assert.equal(await api.verify(store, manifest), false);
  await store.remove();
  assert.equal(await api.state(store, manifest), 'missing');
});

test('truncated downloads, hash mismatches and extra bytes never commit installed metadata', async () => {
  for (const text of ['', 'Astra game datX', 'Astra game data EXTRA']) {
    const { manifest, store } = await fixture();
    await assert.rejects(api.install(store, manifest, async () => new Response(text)), /incomplete|integrity|length/);
    assert.equal(store.meta, null);
  }
});

test('quota failures and unavailable storage have recoverable errors', async () => {
  const { manifest, store, fetchData } = await fixture();
  store.putChunk = async () => { throw new Error('Quota exceeded'); };
  await assert.rejects(api.install(store, manifest, fetchData), /Quota/);
  assert.equal(store.meta, null);
  await assert.rejects(api.openStore(null, '/client/astraclient.html', manifest.packageName), /unavailable/);
});

test('network errors do not erase an existing installation', async () => {
  const { manifest, store, fetchData } = await fixture();
  await api.install(store, manifest, fetchData);
  await assert.rejects(api.install(store, manifest, async () => new Response('', { status: 503 })), /503/);
  assert.equal(await api.verify(store, manifest), true);
});

test('manifest rejects unsafe URLs, malformed identity and inconsistent chunk lengths', async () => {
  const { manifest } = await fixture();
  for (const changes of [{ file: 'https://evil.example/data' }, { size: 0 }, { uuid: 'old' },
    { chunks: [] }, { chunks: [{ size: 1, sha256: 'a'.repeat(64) }] }, { version: '9.0' }])
    assert.throws(() => api.validateManifest({ ...manifest, ...changes }), /Invalid/);
});

test('stream boundaries do not matter and all progress is based on actual received bytes', async () => {
  const { bytes, manifest, store } = await fixture();
  const parts = [bytes.subarray(0, 2), bytes.subarray(2, 5), bytes.subarray(5)];
  const stream = new ReadableStream({ pull(controller) {
    if (parts.length) controller.enqueue(parts.shift()); else controller.close();
  } });
  const progress = [];
  await api.install(store, manifest, async () => new Response(stream), n => progress.push(n));
  assert.deepEqual(progress, [2, 5, bytes.length]);
  assert.equal(await api.verify(store, manifest), true);
});

test('verified package handoff reads each cached chunk once and returns the SDK buffer', async () => {
  const { bytes, manifest, store, fetchData } = await fixture();
  await api.install(store, manifest, fetchData);
  let reads = 0;
  const get = store.getChunk.bind(store);
  store.getChunk = async i => { reads++; return get(i); };
  const data = await api.readPackage(store, manifest);
  assert.ok(data instanceof ArrayBuffer);
  assert.deepEqual(new Uint8Array(data), bytes);
  assert.equal(reads, manifest.chunks.length);
  store.chunks.set(0, new ArrayBuffer(bytes.length));
  assert.equal(await api.readPackage(store, manifest, undefined, { fullVerify: true }), null);
});

test('trusted installs skip repeat hashes, but legacy metadata and Repair fully verify', async () => {
  const { manifest, store, fetchData } = await fixture();
  await api.install(store, manifest, fetchData);
  const stats = {};
  assert.ok(await api.readPackage(store, manifest, undefined, { diagnostics: stats }));
  assert.equal(stats.cacheIntegrityMode, 'trusted-installed');
  assert.equal(stats.assetCacheHashMs, 0);
  delete store.meta.astraVerifiedSchema;
  assert.ok(await api.readPackage(store, manifest, undefined, { diagnostics: stats }));
  assert.equal(stats.cacheIntegrityMode, 'full-verify');
  assert.equal(store.meta.astraVerifiedSchema, 1);
  assert.ok(await api.readPackage(store, manifest, undefined, { fullVerify: true, diagnostics: stats }));
  assert.equal(stats.cacheIntegrityMode, 'full-verify');
});

test('trusted cache still rejects missing, wrong-sized or non-buffer chunks', async () => {
  for (const chunk of [undefined, new ArrayBuffer(1), new Uint8Array(14)]) {
    const { manifest, store, fetchData } = await fixture();
    await api.install(store, manifest, fetchData);
    store.chunks.set(0, chunk);
    assert.equal(await api.readPackage(store, manifest), null);
    assert.equal(store.meta, null);
  }
});

test('a changed manifest or trust schema cannot inherit verification from an old install', async () => {
  for (const change of ['manifest', 'schema', 'size']) {
    const { manifest, store, fetchData } = await fixture();
    await api.install(store, manifest, fetchData);
    if (change === 'manifest') store.meta.astraManifest = 'old manifest';
    if (change === 'schema') store.meta.astraVerifiedSchema = 2;
    if (change === 'size') store.meta.size++;
    store.chunks.set(0, new ArrayBuffer(manifest.size));
    assert.equal(await api.readPackage(store, manifest), null);
  }
});

test('session fallback validates bytes even with quota failure or no IndexedDB', async () => {
  for (const unavailable of [true, false]) {
    const { bytes, manifest, store, fetchData } = await fixture();
    let failures = 0;
    store.putChunk = async () => { throw new Error('quota'); };
    const data = await api.fetchPackage(unavailable ? null : store, manifest, fetchData,
      () => {}, () => failures++);
    assert.deepEqual(new Uint8Array(data), bytes);
    assert.equal(failures, unavailable ? 0 : 1);
    assert.equal(store.meta, null);
    await assert.rejects(api.fetchPackage(null, manifest, async () => new Response('wrong')), /incomplete|integrity/);
  }
});

test('cold Play populates the existing persistent cache without a second package download', async () => {
  const { bytes, manifest, store, fetchData } = await fixture();
  let downloads = 0;
  const data = await api.fetchPackage(store, manifest, () => { downloads++; return fetchData(); });
  assert.deepEqual(new Uint8Array(data), bytes);
  assert.equal(downloads, 1);
  assert.equal(await api.state(store, manifest), 'installed');
  assert.equal(await api.verify(store, manifest), true);
});

test('hash verification and cache handoff cross the pinned SDK 64 MiB boundary', async () => {
  const bytes = new Uint8Array(api.CHUNK_SIZE + 7);
  bytes[api.CHUNK_SIZE - 1] = 42; bytes[api.CHUNK_SIZE] = 99;
  const { manifest, store } = await fixture();
  manifest.size = bytes.length;
  manifest.uuid = 'sha256-' + await digest(bytes);
  manifest.chunks = [{ size: api.CHUNK_SIZE, sha256: await digest(bytes.subarray(0, api.CHUNK_SIZE)) },
    { size: 7, sha256: await digest(bytes.subarray(api.CHUNK_SIZE)) }];
  api.validateManifest(manifest);
  const data = await api.fetchPackage(store, manifest, async () => new Response(bytes));
  assert.equal(new Uint8Array(data)[api.CHUNK_SIZE], 99);
  const cached = await api.readPackage(store, manifest);
  assert.equal(new Uint8Array(cached)[api.CHUNK_SIZE - 1], 42);
  assert.equal((await store.getChunk(1)).byteLength, 7);
});
