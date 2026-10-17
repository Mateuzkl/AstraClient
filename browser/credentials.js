/* Optional, device-local password vault. Never writes credentials to IDBFS/OTML. */
(function(root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.AstraCredentials = api;
})(globalThis, () => {
  'use strict';
  function create({ indexedDB, crypto, location, secure = true, notify = () => {} }) {
    const deployment = new URL('.', location.href).href;
    const recordId = deployment + 'login';
    const encoder = new TextEncoder(), decoder = new TextDecoder('utf-8', { fatal: true });
    let cached = null, generation = 0, available = false, forgotten = false, queue = Promise.resolve();
    const scopeValid = scope => {
      if (typeof scope !== 'string' || scope.length > 2048) return false;
      // Legacy login uses a logical HOST:PORT:VERSION identity; the existing
      // browser transport separately enforces the deployment's WSS policy.
      const legacy = /^([a-z0-9._-]+|\[[a-f0-9:]+\]):([0-9]+)(?::[0-9]+)?$/i.exec(scope);
      if (legacy) return Number(legacy[2]) >= 1 && Number(legacy[2]) <= 65535;
      try { const u = new URL(scope); return scope.length <= 2048 && u.protocol === 'https:' &&
        !u.username && !u.password && !u.hash; } catch (_) { return false; }
    };
    const valid = value => value && scopeValid(value.scope) && typeof value.account === 'string' &&
      value.account.length > 0 && value.account.length <= 512 && typeof value.password === 'string' &&
      value.password.length > 0 && value.password.length <= 1024;
    const supported = () => secure && !!indexedDB && !!crypto?.subtle && !!crypto?.getRandomValues;
    async function access(mode, operation) {
      const db = await new Promise((resolve, reject) => {
        const request = indexedDB.open('ASTRA_CREDENTIAL_VAULT', 1);
        let expired = false;
        const timer = setTimeout(() => { expired = true; reject(new Error('Storage unavailable')); }, 5000);
        request.onupgradeneeded = () => {
          if (!request.result.objectStoreNames.contains('vault')) request.result.createObjectStore('vault');
        };
        request.onerror = () => { clearTimeout(timer); reject(new Error('Storage unavailable')); };
        request.onsuccess = () => {
          clearTimeout(timer);
          if (expired) { request.result.close(); return; }
          resolve(request.result);
        };
      });
      db.onversionchange = () => db.close();
      try {
        return await new Promise((resolve, reject) => {
          const tx = db.transaction('vault', mode);
          const request = operation(tx.objectStore('vault'));
          tx.oncomplete = () => resolve(request.result);
          tx.onabort = () => reject(new Error('Storage unavailable'));
          tx.onerror = () => {};
        });
      } finally { db.close(); }
    }
    const aad = scope => encoder.encode(JSON.stringify([1, deployment, scope]));
    const enqueue = operation => {
      queue = queue.then(operation).catch(() => {
        notify('Unable to save or remove the remembered login. Check this browser\'s site storage permissions.', true);
      });
      return queue;
    };
    return {
      async restore() {
        if (!supported()) return;
        const revision = generation;
        try {
          const record = await access('readonly', s => s.get(recordId));
          available = true;
          if (!record) return;
          if (record.schema !== 1 || !scopeValid(record.scope) || !record.key || record.key.extractable ||
              !(record.iv instanceof Uint8Array) || record.iv.length !== 12 ||
              !(record.payload instanceof ArrayBuffer) || record.payload.byteLength > 16384) throw new Error('Invalid vault');
          const plain = new Uint8Array(await crypto.subtle.decrypt({ name: 'AES-GCM', iv: record.iv,
            additionalData: aad(record.scope) }, record.key, record.payload));
          try {
            const value = JSON.parse(decoder.decode(plain));
            if (!valid(value) || value.scope !== record.scope) throw new Error('Invalid credentials');
            if (generation === revision) cached = value;
          } finally { plain.fill(0); }
        } catch (_) {
          // A damaged/unsupported vault cannot block the game or expose parser details.
          if (generation === revision) cached = null;
          notify('The remembered login could not be restored. Enter it again or use Forget saved login.', true);
        }
      },
      available: () => available,
      allowSaving() { forgotten = false; },
      get(scope) { return cached?.scope === scope ? JSON.stringify({ account: cached.account, password: cached.password }) : ''; },
      save(scope, account, password) {
        const value = { scope, account, password };
        if (!available || forgotten || !valid(value)) return false;
        const revision = ++generation;
        cached = value;
        enqueue(async () => {
          try {
            if (generation !== revision) return;
            const key = await crypto.subtle.generateKey({ name: 'AES-GCM', length: 256 }, false, ['encrypt', 'decrypt']);
            const iv = crypto.getRandomValues(new Uint8Array(12));
            const plain = encoder.encode(JSON.stringify(value));
            let payload;
            try { payload = await crypto.subtle.encrypt({ name: 'AES-GCM', iv, additionalData: aad(scope) }, key, plain); }
            finally { plain.fill(0); }
            if (generation !== revision) return;
            await access('readwrite', s => s.put({ schema: 1, scope, key, iv, payload }, recordId));
            if (generation === revision) notify('Login saved encrypted on this browser. Use Forget saved login to remove it.');
          } catch (error) {
            if (generation === revision) cached = null;
            throw error;
          }
        });
        return true;
      },
      forget() {
        ++generation; cached = null; forgotten = true;
        if (!supported()) return Promise.resolve();
        return enqueue(async () => {
          await access('readwrite', s => s.delete(recordId));
          notify('Saved login removed from this browser.');
        });
      },
      idle: () => queue
    };
  }
  return { create };
});
