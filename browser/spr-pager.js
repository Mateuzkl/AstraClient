/* True on-demand 256 KiB page loader for Tibia.spr on Web Mobile Lite.
 * Fetches only requested byte ranges via HTTP 206 Partial Content, verifies
 * per-page SHA-256 against spr-manifest.json, and caches pages in IndexedDB. */
(function(root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.AstraSprPager = api;
})(globalThis, () => {
  'use strict';

  const DEFAULT_PAGE_SIZE = 256 * 1024;
  const MAX_CONCURRENT = 6;
  const DEFAULT_TIMEOUT_MS = 15000;
  const DB_NAME = 'ASTRA_SPR_PAGE_CACHE';
  const DB_VERSION = 1;

  const hex = buffer => Array.from(new Uint8Array(buffer), n => n.toString(16).padStart(2, '0')).join('');
  const sha256Hex = async buffer => hex(await crypto.subtle.digest('SHA-256', buffer));

  function validateSprManifest(m) {
    if (!m || m.schema !== 1 || m.version !== '8.60' ||
        typeof m.file !== 'string' || !m.file || /^https?:|^\//i.test(m.file) || m.file.includes('..') ||
        !/^sha256-[a-f0-9]{64}$/.test(m.uuid) ||
        !Number.isSafeInteger(m.size) || m.size <= 0 || m.size > 2147483648 ||
        m.pageSize !== DEFAULT_PAGE_SIZE ||
        !Number.isSafeInteger(m.spriteCount) || m.spriteCount <= 0 ||
        !Number.isSafeInteger(m.indexBytes) || m.indexBytes < 8 || m.indexBytes > m.size ||
        !Array.isArray(m.hashes)) {
      throw new Error('Invalid on-demand sprite manifest.');
    }
    const expectedPages = Math.ceil(m.size / m.pageSize);
    if (m.hashes.length !== expectedPages) {
      throw new Error('Invalid on-demand sprite page count.');
    }
    for (let i = 0; i < m.hashes.length; ++i) {
      if (typeof m.hashes[i] !== 'string' || !/^[a-f0-9]{64}$/.test(m.hashes[i])) {
        throw new Error('Invalid on-demand sprite page hash.');
      }
    }
    return m;
  }

  function pageByteRange(manifest, pageIndex) {
    if (!Number.isInteger(pageIndex) || pageIndex < 0 || pageIndex >= manifest.hashes.length) {
      throw new Error('Sprite page index out of range.');
    }
    const start = pageIndex * manifest.pageSize;
    const size = Math.min(manifest.pageSize, manifest.size - start);
    return { start, end: start + size - 1, size };
  }

  function openPageStore(indexedDB, namespace) {
    if (!indexedDB) return Promise.resolve(null);
    const ns = String(namespace || 'mobile');
    return new Promise((resolve) => {
      let request;
      try { request = indexedDB.open(DB_NAME, DB_VERSION); }
      catch (_) { resolve(null); return; }
      let settled = false;
      const done = value => { if (!settled) { settled = true; resolve(value); } };
      const timer = setTimeout(() => done(null), 4000);
      request.onupgradeneeded = () => {
        const db = request.result;
        for (const name of ['METADATA', 'PAGES']) {
          if (!db.objectStoreNames.contains(name)) db.createObjectStore(name);
        }
      };
      request.onerror = () => { clearTimeout(timer); done(null); };
      request.onsuccess = () => {
        clearTimeout(timer);
        const db = request.result;
        let closed = false;
        const close = () => { if (!closed) { closed = true; db.close(); } };
        if (!['METADATA', 'PAGES'].every(s => db.objectStoreNames.contains(s))) {
          close(); done(null); return;
        }
        db.onversionchange = close;
        const txOp = (storeName, mode, fn) => new Promise((ok, fail) => {
          if (closed) { ok(undefined); return; }
          try {
            const tx = db.transaction(storeName, mode);
            const req = fn(tx.objectStore(storeName));
            tx.oncomplete = () => ok(req ? req.result : undefined);
            tx.onabort = () => fail(tx.error || (req && req.error) || new Error('IDB transaction aborted'));
            tx.onerror = () => {};
          } catch (err) { fail(err); }
        });
        const metaKey = `spr-meta/${ns}`;
        const pagePrefix = `spr-page/${ns}/`;
        done({
          getMeta: () => txOp('METADATA', 'readonly', s => s.get(metaKey)),
          putMeta: value => txOp('METADATA', 'readwrite', s => s.put(value, metaKey)),
          getPage: idx => txOp('PAGES', 'readonly', s => s.get(`${pagePrefix}${idx}`)),
          putPage: (idx, buffer) => txOp('PAGES', 'readwrite', s => s.put(buffer, `${pagePrefix}${idx}`)),
          async clearPages() {
            await txOp('METADATA', 'readwrite', s => s.delete(metaKey)).catch(() => {});
            await new Promise(ok => {
              if (closed) { ok(); return; }
              try {
                const tx = db.transaction('PAGES', 'readwrite');
                const req = tx.objectStore('PAGES').openCursor(IDBKeyRange.bound(pagePrefix, pagePrefix + '\uffff'));
                req.onsuccess = () => {
                  const cursor = req.result;
                  if (cursor) { cursor.delete(); cursor.continue(); }
                };
                tx.oncomplete = ok;
                tx.onabort = ok;
                tx.onerror = () => {};
              } catch (_) { ok(); }
            });
          },
          close
        });
      };
    });
  }

  async function clearProfilePages(indexedDB, namespace) {
    const store = await openPageStore(indexedDB, namespace);
    if (!store) return;
    try { await store.clearPages(); } finally { store.close(); }
  }

  function createPager({ manifest, baseUrl, store = null, fetcher = globalThis.fetch, onDeliver = () => {}, maxConcurrent = MAX_CONCURRENT, timeoutMs = DEFAULT_TIMEOUT_MS } = {}) {
    const valid = validateSprManifest(manifest);
    const sprUrl = new URL(valid.file, baseUrl || 'http://localhost/').href;
    const inFlight = new Set();
    const activeControllers = new Set();
    const queue = [];
    let activeFetches = 0;
    let disposed = false;
    let storeReadyPromise = null;

    const stats = {
      totalPages: valid.hashes.length,
      pageSize: valid.pageSize,
      idbHits: 0,
      networkFetches: 0,
      bytesTransferred: 0,
      errors: 0,
      inFlight: 0
    };

    async function ensureStoreVersion() {
      if (!store) return null;
      if (!storeReadyPromise) {
        storeReadyPromise = (async () => {
          try {
            const meta = await store.getMeta();
            if (!meta || meta.uuid !== valid.uuid || meta.pageSize !== valid.pageSize || meta.size !== valid.size) {
              await store.clearPages();
              await store.putMeta({ uuid: valid.uuid, pageSize: valid.pageSize, size: valid.size, version: valid.version });
            }
            return store;
          } catch (_) {
            return null;
          }
        })();
      }
      return storeReadyPromise;
    }

    async function fetchAndVerifyPage(pageIndex) {
      const range = pageByteRange(valid, pageIndex);
      const expectedHash = valid.hashes[pageIndex];
      const activeStore = await ensureStoreVersion();

      if (activeStore) {
        try {
          const cached = await activeStore.getPage(pageIndex);
          if (cached instanceof ArrayBuffer && cached.byteLength === range.size) {
            const cachedHash = await sha256Hex(cached);
            if (cachedHash === expectedHash) {
              stats.idbHits++;
              return new Uint8Array(cached);
            }
          }
        } catch (_) {}
      }

      const controller = typeof AbortController === 'function' ? new AbortController() : null;
      if (controller) activeControllers.add(controller);
      let timeoutId = null;
      const deadlinePromise = timeoutMs > 0
        ? new Promise((_, reject) => {
            timeoutId = setTimeout(() => {
              if (controller) { try { controller.abort(); } catch (_) {} }
              reject(new Error(`Sprite page ${pageIndex} download timed out`));
            }, timeoutMs);
          })
        : null;

      try {
        const doFetch = async () => {
          const init = {
            method: 'GET',
            headers: { Range: `bytes=${range.start}-${range.end}` },
            credentials: 'same-origin',
            cache: 'force-cache'
          };
          if (controller) init.signal = controller.signal;
          const response = await fetcher(sprUrl, init);
          if (response.status !== 206) {
            throw new Error(`Expected HTTP 206 for sprite page ${pageIndex}, got ${response.status}`);
          }
          const buffer = await response.arrayBuffer();
          if (buffer.byteLength !== range.size) {
            throw new Error(`Sprite page ${pageIndex} length mismatch (${buffer.byteLength} != ${range.size})`);
          }
          const actualHash = await sha256Hex(buffer);
          if (actualHash !== expectedHash) {
            throw new Error(`Sprite page ${pageIndex} SHA-256 verification failed`);
          }
          return buffer;
        };

        const buffer = deadlinePromise ? await Promise.race([doFetch(), deadlinePromise]) : await doFetch();
        stats.networkFetches++;
        stats.bytesTransferred += buffer.byteLength;

        if (activeStore && !disposed) {
          // Persist asynchronously; quota failures never fail gameplay.
          activeStore.putPage(pageIndex, buffer.slice(0)).catch(() => {});
        }
        return new Uint8Array(buffer);
      } finally {
        if (timeoutId !== null) clearTimeout(timeoutId);
        if (controller) activeControllers.delete(controller);
      }
    }

    function pump() {
      while (!disposed && activeFetches < maxConcurrent && queue.length > 0) {
        const pageIndex = queue.shift();
        activeFetches++;
        stats.inFlight = activeFetches;
        fetchAndVerifyPage(pageIndex)
          .then(bytes => {
            if (!disposed) onDeliver(pageIndex, bytes, true);
          })
          .catch(() => {
            stats.errors++;
            if (!disposed) onDeliver(pageIndex, null, false);
          })
          .finally(() => {
            inFlight.delete(pageIndex);
            activeFetches--;
            stats.inFlight = activeFetches;
            pump();
          });
      }
    }

    function requestPage(pageIndex) {
      if (disposed) return false;
      if (!Number.isInteger(pageIndex) || pageIndex < 0 || pageIndex >= valid.hashes.length) return false;
      if (inFlight.has(pageIndex)) return false;
      inFlight.add(pageIndex);
      queue.push(pageIndex);
      pump();
      return true;
    }

    return {
      requestPage,
      getStats: () => ({ ...stats, queued: queue.length }),
      dispose() {
        disposed = true;
        queue.length = 0;
        inFlight.clear();
        for (const controller of activeControllers) {
          try { controller.abort(); } catch (_) {}
        }
        activeControllers.clear();
        if (store && typeof store.close === 'function') store.close();
      }
    };
  }

  return {
    DEFAULT_PAGE_SIZE,
    MAX_CONCURRENT,
    DB_NAME,
    validateSprManifest,
    pageByteRange,
    openPageStore,
    clearProfilePages,
    createPager
  };
});
