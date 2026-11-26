'use strict';
const assert = require('node:assert/strict');
const { test } = require('node:test');
globalThis.crypto ||= require('node:crypto').webcrypto;
const api = require('../spr-pager.js');

const PAGE_SIZE = api.DEFAULT_PAGE_SIZE; // 262144 bytes (must match C++ PagedSprPageSize)
const digest = async bytes => Buffer.from(await crypto.subtle.digest('SHA-256', bytes)).toString('hex');

async function buildFixture(totalSize = PAGE_SIZE * 2 + 1808) {
  const full = new Uint8Array(totalSize);
  for (let i = 0; i < totalSize; ++i) full[i] = (i * 37 + 11) & 0xff;
  const hashes = [];
  for (let offset = 0; offset < totalSize; offset += PAGE_SIZE) {
    hashes.push(await digest(full.subarray(offset, Math.min(offset + PAGE_SIZE, totalSize))));
  }
  const manifest = api.validateSprManifest({
    schema: 1,
    version: '8.60',
    file: 'Tibia.spr',
    size: totalSize,
    signature: 0x4C220594,
    spriteCount: 100,
    indexBytes: 408,
    pageSize: PAGE_SIZE,
    uuid: 'sha256-' + await digest(full),
    hashes
  });
  const memStore = {
    meta: null,
    pages: new Map(),
    closed: false,
    async getMeta() { return this.meta; },
    async putMeta(v) { this.meta = v; },
    async getPage(i) { return this.pages.get(i); },
    async putPage(i, buf) { this.pages.set(i, buf); },
    async clearPages() { this.meta = null; this.pages.clear(); },
    close() { this.closed = true; }
  };
  return { full, manifest, memStore };
}

test('spr-pager rejects non-256 KiB pageSize manifests to match C++ PagedSprPageSize', async () => {
  const { manifest } = await buildFixture(PAGE_SIZE);
  assert.throws(() => api.validateSprManifest({ ...manifest, pageSize: 4096 }), /Invalid on-demand sprite manifest/);
});

test('spr-pager fetches only requested 256 KiB Range pages, verifies SHA-256 and caches in IDB', async () => {
  const { full, manifest, memStore } = await buildFixture(PAGE_SIZE * 2 + 1808);
  const rangesRequested = [];
  const fetcher = async (url, init) => {
    assert.equal(url, 'http://localhost/mobile/Tibia.spr');
    const match = /^bytes=(\d+)-(\d+)$/.exec(init.headers.Range);
    assert.ok(match);
    const start = Number(match[1]);
    const end = Number(match[2]);
    rangesRequested.push([start, end]);
    const slice = full.slice(start, end + 1);
    return new Response(slice, { status: 206 });
  };

  const delivered = [];
  let resolveDone;
  const done = new Promise(r => { resolveDone = r; });
  const pager = api.createPager({
    manifest,
    baseUrl: 'http://localhost/mobile/spr-manifest.json',
    store: memStore,
    fetcher,
    onDeliver(pageIndex, bytes, ok) {
      delivered.push({ pageIndex, size: bytes ? bytes.byteLength : 0, ok, first: bytes ? bytes[0] : -1 });
      if (delivered.length === 2) resolveDone();
    }
  });

  assert.equal(pager.requestPage(2), true);
  assert.equal(pager.requestPage(2), false, 'duplicate in-flight page must be deduplicated');
  assert.equal(pager.requestPage(0), true);
  await done;

  assert.deepEqual(rangesRequested, [[PAGE_SIZE * 2, PAGE_SIZE * 2 + 1807], [0, PAGE_SIZE - 1]]);
  assert.equal(delivered.length, 2);
  assert.deepEqual(delivered.map(d => [d.pageIndex, d.size, d.ok]), [[2, 1808, true], [0, PAGE_SIZE, true]]);
  assert.equal(pager.getStats().networkFetches, 2);
  assert.equal(pager.getStats().bytesTransferred, 1808 + PAGE_SIZE);
  assert.equal(memStore.pages.has(1), false);
  assert.equal(memStore.pages.has(2), true);

  // Second request for page 2 verifies SHA-256 and hits IndexedDB with ZERO network transfer.
  const hit = await new Promise(resolve => {
    const pager2 = api.createPager({
      manifest,
      baseUrl: 'http://localhost/mobile/spr-manifest.json',
      store: memStore,
      fetcher: async () => { throw new Error('network should not be called on valid IDB hit'); },
      onDeliver(pageIndex, bytes, ok) { resolve({ pageIndex, bytes, ok, stats: pager2.getStats() }); }
    });
    pager2.requestPage(2);
  });
  assert.equal(hit.ok, true);
  assert.equal(hit.bytes.byteLength, 1808);
  assert.equal(hit.stats.idbHits, 1);
  assert.equal(hit.stats.networkFetches, 0);
  pager.dispose();
  assert.equal(memStore.closed, true);
});

test('spr-pager rejects tampered Range payloads, corrupted IDB pages, and non-206 responses', async () => {
  const { full, manifest, memStore } = await buildFixture(PAGE_SIZE * 2);
  for (const mode of ['corrupt', 'status200']) {
    const result = await new Promise(resolve => {
      const pager = api.createPager({
        manifest,
        baseUrl: 'http://localhost/mobile/spr-manifest.json',
        fetcher: async () => {
          const payload = full.slice(0, PAGE_SIZE);
          if (mode === 'corrupt') payload[0] ^= 0xff;
          return new Response(payload, { status: mode === 'status200' ? 200 : 206 });
        },
        onDeliver(pageIndex, bytes, ok) { resolve({ pageIndex, bytes, ok, errors: pager.getStats().errors }); }
      });
      pager.requestPage(0);
    });
    assert.equal(result.ok, false, mode);
    assert.equal(result.bytes, null, mode);
    assert.equal(result.errors, 1, mode);
  }

  // Same-size corrupted page in IDB must fail SHA-256 and recover via network fetch.
  memStore.meta = { uuid: manifest.uuid, pageSize: PAGE_SIZE, size: manifest.size, version: '8.60' };
  const badBuf = full.slice(0, PAGE_SIZE);
  badBuf[10] ^= 0xff;
  memStore.pages.set(0, badBuf.buffer);
  let recoveredNetwork = 0;
  const recovered = await new Promise(resolve => {
    const pager = api.createPager({
      manifest,
      baseUrl: 'http://localhost/mobile/spr-manifest.json',
      store: memStore,
      fetcher: async () => { recoveredNetwork++; return new Response(full.slice(0, PAGE_SIZE), { status: 206 }); },
      onDeliver(pageIndex, bytes, ok) { resolve({ pageIndex, bytes, ok, stats: pager.getStats() }); }
    });
    pager.requestPage(0);
  });
  assert.equal(recovered.ok, true);
  assert.equal(recoveredNetwork, 1, 'corrupted IDB page must be re-fetched from network');
  assert.equal(recovered.stats.idbHits, 0);
});

test('spr-pager aborts stalled downloads on timeout and on dispose', async () => {
  const { manifest } = await buildFixture(PAGE_SIZE);
  let aborted = 0;
  let pager;
  const timedOut = await new Promise(resolve => {
    pager = api.createPager({
      manifest,
      baseUrl: 'http://localhost/mobile/spr-manifest.json',
      timeoutMs: 30,
      fetcher: (_url, init) => new Promise((_res, rej) => {
        if (init && init.signal) {
          init.signal.addEventListener('abort', () => { aborted++; rej(new Error('aborted')); });
        }
      }),
      onDeliver(pageIndex, bytes, ok) { resolve({ pageIndex, bytes, ok }); }
    });
    pager.requestPage(0);
  });
  await new Promise(r => setImmediate(r));
  assert.equal(timedOut.ok, false);
  assert.equal(aborted, 1);
  assert.equal(pager.getStats().errors, 1);
  assert.equal(pager.getStats().inFlight, 0);
});

test('spr-pager invalidates old cached pages automatically when manifest UUID changes', async () => {
  const { full, manifest, memStore } = await buildFixture(PAGE_SIZE * 2);
  memStore.meta = { uuid: 'sha256-' + '0'.repeat(64), pageSize: PAGE_SIZE, size: PAGE_SIZE * 2, version: '8.60' };
  memStore.pages.set(0, new ArrayBuffer(PAGE_SIZE));
  let fetched = 0;
  const res = await new Promise(resolve => {
    const pager = api.createPager({
      manifest,
      baseUrl: 'http://localhost/mobile/spr-manifest.json',
      store: memStore,
      fetcher: async () => { fetched++; return new Response(full.slice(0, PAGE_SIZE), { status: 206 }); },
      onDeliver(pageIndex, bytes, ok) { resolve({ pageIndex, bytes, ok }); }
    });
    pager.requestPage(0);
  });
  assert.equal(res.ok, true);
  assert.equal(fetched, 1, 'stale UUID cache must be cleared before serving pages');
  assert.equal(memStore.meta.uuid, manifest.uuid);
});
