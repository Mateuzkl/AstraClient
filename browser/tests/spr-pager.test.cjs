'use strict';
const assert = require('node:assert/strict');
const { test } = require('node:test');
globalThis.crypto ||= require('node:crypto').webcrypto;
const api = require('../spr-pager.js');

const digest = async bytes => Buffer.from(await crypto.subtle.digest('SHA-256', bytes)).toString('hex');

async function buildFixture(pageSize = 4096, totalSize = 10000) {
  const full = new Uint8Array(totalSize);
  for (let i = 0; i < totalSize; ++i) full[i] = (i * 37 + 11) & 0xff;
  const hashes = [];
  for (let offset = 0; offset < totalSize; offset += pageSize) {
    hashes.push(await digest(full.subarray(offset, Math.min(offset + pageSize, totalSize))));
  }
  const manifest = api.validateSprManifest({
    schema: 1,
    version: '8.60',
    file: 'Tibia.spr',
    size: totalSize,
    signature: 0x4C220594,
    spriteCount: 100,
    indexBytes: 408,
    pageSize,
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

test('spr-pager fetches only requested 256 KiB Range pages, verifies SHA-256 and caches in IDB', async () => {
  const { full, manifest, memStore } = await buildFixture(4096, 10000);
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

  // Request page 2 (partial last page) and duplicate page 2 + page 0
  assert.equal(pager.requestPage(2), true);
  assert.equal(pager.requestPage(2), false, 'duplicate in-flight page must be deduplicated');
  assert.equal(pager.requestPage(0), true);
  await done;

  assert.deepEqual(rangesRequested, [[8192, 9999], [0, 4095]]);
  assert.equal(delivered.length, 2);
  assert.deepEqual(delivered.map(d => [d.pageIndex, d.size, d.ok]), [[2, 1808, true], [0, 4096, true]]);
  assert.equal(pager.getStats().networkFetches, 2);
  assert.equal(pager.getStats().bytesTransferred, 1808 + 4096);
  // Page 1 was NEVER downloaded!
  assert.equal(memStore.pages.has(1), false);
  assert.equal(memStore.pages.has(2), true);

  // Second request for page 2 hits IndexedDB with ZERO network transfer.
  const hitPromise = new Promise(resolve => {
    const pager2 = api.createPager({
      manifest,
      baseUrl: 'http://localhost/mobile/spr-manifest.json',
      store: memStore,
      fetcher: async () => { throw new Error('network should not be called on IDB hit'); },
      onDeliver(pageIndex, bytes, ok) { resolve({ pageIndex, bytes, ok, stats: pager2.getStats() }); }
    });
    pager2.requestPage(2);
  });
  const hit = await hitPromise;
  assert.equal(hit.ok, true);
  assert.equal(hit.bytes.byteLength, 1808);
  assert.equal(hit.stats.idbHits, 1);
  assert.equal(hit.stats.networkFetches, 0);
  pager.dispose();
  assert.equal(memStore.closed, true);
});

test('spr-pager rejects tampered Range payloads and non-206 responses', async () => {
  const { full, manifest } = await buildFixture(4096, 8192);
  for (const mode of ['corrupt', 'status200']) {
    const result = await new Promise(resolve => {
      const pager = api.createPager({
        manifest,
        baseUrl: 'http://localhost/mobile/spr-manifest.json',
        fetcher: async () => {
          const payload = full.slice(0, 4096);
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
});

test('spr-pager invalidates old cached pages automatically when manifest UUID changes', async () => {
  const { full, manifest, memStore } = await buildFixture(4096, 8192);
  memStore.meta = { uuid: 'sha256-' + '0'.repeat(64), pageSize: 4096, size: 8192, version: '8.60' };
  memStore.pages.set(0, new ArrayBuffer(4096));
  let fetched = 0;
  const res = await new Promise(resolve => {
    const pager = api.createPager({
      manifest,
      baseUrl: 'http://localhost/mobile/spr-manifest.json',
      store: memStore,
      fetcher: async () => { fetched++; return new Response(full.slice(0, 4096), { status: 206 }); },
      onDeliver(pageIndex, bytes, ok) { resolve({ pageIndex, bytes, ok }); }
    });
    pager.requestPage(0);
  });
  assert.equal(res.ok, true);
  assert.equal(fetched, 1, 'stale UUID cache must be cleared before serving pages');
  assert.equal(memStore.meta.uuid, manifest.uuid);
});
