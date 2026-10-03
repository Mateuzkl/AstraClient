/* Same-origin launcher adapter for Emscripten 6.0.8's existing preload cache. */
(function(root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.AstraAssetCache = api;
})(globalThis, () => {
  'use strict';
  const CHUNK_SIZE = 64 * 1024 * 1024;
  const hex = buffer => Array.from(new Uint8Array(buffer), n => n.toString(16).padStart(2, '0')).join('');
  const hash = async buffer => hex(await crypto.subtle.digest('SHA-256', buffer));
  function validateManifest(m) {
    if (!m || m.schema !== 1 || m.version !== '8.60' || m.file !== 'astraclient.data' ||
        typeof m.packageName !== 'string' || !m.packageName.endsWith('/astraclient.data') ||
        !/^sha256-[a-f0-9]{64}$/.test(m.uuid) || !Number.isSafeInteger(m.size) || m.size <= 0 ||
        m.size > 2147483648 || !Array.isArray(m.chunks) || m.chunks.length !== Math.ceil(m.size / CHUNK_SIZE))
      throw new Error('Invalid game data manifest. Rebuild or refresh the deployment.');
    let total = 0;
    for (let i = 0; i < m.chunks.length; ++i) {
      const c = m.chunks[i];
      if (!c || !/^[a-f0-9]{64}$/.test(c.sha256) ||
          c.size !== Math.min(CHUNK_SIZE, m.size - i * CHUNK_SIZE))
        throw new Error('Invalid game data chunk manifest.');
      total += c.size;
    }
    if (total !== m.size) throw new Error('Invalid game data length.');
    return m;
  }

  function openStore(indexedDB, pathname, packageName) {
    if (!indexedDB) return Promise.reject(new Error('Browser storage is unavailable.'));
    const name = encodeURIComponent(pathname.slice(0, pathname.lastIndexOf('/')) + '/') + packageName;
    return new Promise((resolve, reject) => {
      const request = indexedDB.open('EM_PRELOAD_CACHE', 1);
      let expired = false;
      const timer = setTimeout(() => { expired = true; reject(new Error('Browser storage is blocked. Close other launcher tabs and retry.')); }, 5000);
      request.onupgradeneeded = () => {
        const db = request.result;
        for (const store of ['METADATA', 'PACKAGES'])
          if (!db.objectStoreNames.contains(store)) db.createObjectStore(store);
      };
      request.onerror = () => { clearTimeout(timer); reject(request.error || new Error('Unable to open browser storage.')); };
      request.onsuccess = () => {
        clearTimeout(timer);
        const db = request.result;
        if (expired) { db.close(); return; }
        if (!['METADATA', 'PACKAGES'].every(s => db.objectStoreNames.contains(s))) {
          db.close(); reject(new Error('Incompatible browser asset cache.')); return;
        }
        db.onversionchange = () => db.close();
        const transaction = (store, mode, operation) => new Promise((ok, fail) => {
          const tx = db.transaction(store, mode);
          const req = operation(tx.objectStore(store));
          tx.oncomplete = () => ok(req.result);
          tx.onabort = () => fail(tx.error || req.error || new Error('Browser storage write failed.'));
          tx.onerror = () => {}; // Abort is the single completion path.
        });
        resolve({
          getMeta: () => transaction('METADATA', 'readonly', s => s.get('metadata/' + name)),
          putMeta: value => transaction('METADATA', 'readwrite', s => s.put(value, 'metadata/' + name)),
          getChunk: i => transaction('PACKAGES', 'readonly', s => s.get(`package/${name}/${i}`)),
          putChunk: (i, value) => transaction('PACKAGES', 'readwrite', s => s.put(value, `package/${name}/${i}`)),
          async remove() {
            // Remove the metadata first: interrupted writes are never "installed".
            await transaction('METADATA', 'readwrite', s => s.delete('metadata/' + name));
            const prefix = `package/${name}/`;
            await new Promise((ok, fail) => {
              const tx = db.transaction('PACKAGES', 'readwrite');
              const req = tx.objectStore('PACKAGES').openCursor(IDBKeyRange.bound(prefix, prefix + '\uffff'));
              req.onsuccess = () => { const cursor = req.result; if (cursor) { cursor.delete(); cursor.continue(); } };
              tx.oncomplete = ok;
              tx.onabort = () => fail(tx.error || new Error('Unable to remove game data.'));
              tx.onerror = () => {};
            });
          },
          close: () => db.close()
        });
      };
    });
  }

  // A cheap initial status check; Play verifies each chunk before using it.
  async function state(store, manifest) {
    const meta = await store.getMeta();
    return !meta ? 'missing' : meta.uuid === manifest.uuid && meta.chunkCount === manifest.chunks.length ? 'installed' : 'outdated';
  }
  async function verify(store, manifest, progress = () => {}) {
    if (await state(store, manifest) !== 'installed') return false;
    let bytes = 0;
    for (let i = 0; i < manifest.chunks.length; i++) {
      const chunk = await store.getChunk(i);
      if (!(chunk instanceof ArrayBuffer) || chunk.byteLength !== manifest.chunks[i].size ||
          await hash(chunk) !== manifest.chunks[i].sha256) return false;
      bytes += chunk.byteLength;
      progress(bytes, manifest.size);
    }
    return true;
  }
  async function readPackage(store, manifest, progress = () => {}) {
    if (await state(store, manifest) !== 'installed') return null;
    // One final buffer plus one IDB chunk, rather than the SDK's all-chunks
    // array + concatenated package after a separate verification pass.
    const data = new Uint8Array(manifest.size);
    let offset = 0;
    for (let i = 0; i < manifest.chunks.length; i++) {
      const chunk = await store.getChunk(i);
      if (!(chunk instanceof ArrayBuffer) || chunk.byteLength !== manifest.chunks[i].size ||
          await hash(chunk) !== manifest.chunks[i].sha256) return null;
      data.set(new Uint8Array(chunk), offset);
      offset += chunk.byteLength;
      progress(offset, manifest.size);
    }
    return data.buffer;
  }
  async function fetchPackage(store, manifest, fetchData, progress = () => {}, storageFailure = () => {}) {
    const data = new Uint8Array(manifest.size);
    const response = await fetchData();
    if (!response.ok || !response.body) throw new Error(`Game data download failed (${response.status}).`);
    const reader = response.body.getReader();
    let cache = store, received = 0, index = 0, verified = 0;
    const persist = async operation => {
      if (!cache) return;
      try { await operation(cache); }
      catch (error) { cache = null; storageFailure(error); }
    };
    try {
      await persist(s => s.remove());
      while (true) {
        const { value, done } = await reader.read();
        if (done) break;
        if (!value || received + value.length > manifest.size) throw new Error('Game data download has an unexpected length.');
        data.set(value, received); received += value.length;
        while (index < manifest.chunks.length && received >= verified + manifest.chunks[index].size) {
          const next = verified + manifest.chunks[index].size;
          const chunk = data.subarray(verified, next);
          if (await hash(chunk) !== manifest.chunks[index].sha256)
            throw new Error('Game data integrity check failed. Please retry Update.');
          // IDB needs a standalone chunk, not the complete package's backing
          // buffer. The copy is transient and bounded to the existing 64 MiB.
          await persist(s => s.putChunk(index, chunk.slice().buffer));
          verified = next; index++;
        }
        progress(received, manifest.size);
      }
      if (received !== manifest.size || index !== manifest.chunks.length) throw new Error('Game data download was incomplete.');
      await persist(s => s.putMeta({ uuid: manifest.uuid, chunkCount: index, size: received }));
      return data.buffer;
    } catch (error) {
      try { await reader.cancel(); } catch (_) {}
      throw error;
    } finally { reader.releaseLock(); }
  }
  async function install(store, manifest, fetchData, progress = () => {}) {
    // SDK chunk format is kept unchanged. Only one 64 MiB assembly buffer is
    // retained at a time, not a second complete DAT/SPR package in the launcher.
    const response = await fetchData();
    if (!response.ok || !response.body) throw new Error(`Game data download failed (${response.status}).`);
    const reader = response.body.getReader();
    let received = 0, index = 0, offset = 0;
    let buffer = new Uint8Array(manifest.chunks[0].size);
    try {
      await store.remove();
      while (true) {
        const { value, done } = await reader.read();
        if (done) break;
        if (!value || received + value.length > manifest.size) throw new Error('Game data download has an unexpected length.');
        let start = 0;
        while (start < value.length) {
          const count = Math.min(buffer.length - offset, value.length - start);
          buffer.set(value.subarray(start, start + count), offset);
          offset += count; start += count; received += count;
          if (offset === buffer.length) {
            if (await hash(buffer.buffer) !== manifest.chunks[index].sha256)
              throw new Error('Game data integrity check failed. Please retry Update.');
            await store.putChunk(index++, buffer.buffer);
            buffer = index < manifest.chunks.length ? new Uint8Array(manifest.chunks[index].size) : null;
            offset = 0;
          }
          progress(received, manifest.size);
        }
      }
      if (received !== manifest.size || index !== manifest.chunks.length) throw new Error('Game data download was incomplete.');
      // Commit "installed" only after every hash check and IDB write completes.
      await store.putMeta({ uuid: manifest.uuid, chunkCount: index, size: received });
    } catch (error) {
      try { await reader.cancel(); } catch (_) {}
      throw error;
    } finally { reader.releaseLock(); }
  }
  return { validateManifest, openStore, state, verify, readPackage, fetchPackage, install, CHUNK_SIZE };
});
