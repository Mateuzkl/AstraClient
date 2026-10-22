// Minimal asynchronous IndexedDB transaction/cursor fixture; values use real
// structuredClone, including non-extractable WebCrypto CryptoKeys.
module.exports = function indexedDBFixture() {
  const databases = new Map(), handles = [];
  const fixture = { databases, handles, failWrites: false, denied: false,
    open(name) {
      const request = {};
      queueMicrotask(() => {
        if (fixture.denied) { request.error = new Error('denied'); request.onerror(); return; }
        const fresh = !databases.has(name);
        if (fresh) databases.set(name, new Map());
        const stores = databases.get(name);
        let closed = false;
        const db = { close() { closed = true; }, get closed() { return closed; },
          objectStoreNames: { contains: name => stores.has(name) },
          createObjectStore: name => stores.set(name, new Map()),
          transaction(name, mode) {
            if (closed) throw new Error('closed database');
            const tx = {}, values = stores.get(name);
            let pending = 0, aborted = false;
            const finish = () => setImmediate(() => { if (!pending && !aborted) tx.oncomplete?.(); });
            const operation = fn => {
              const req = {}; pending++;
              queueMicrotask(() => {
                try {
                  if (fixture.failWrites && mode === 'readwrite') throw new Error('quota');
                  req.result = fn(); req.onsuccess?.();
                } catch (error) { aborted = true; tx.error = req.error = error; tx.onabort?.(); }
                pending--; finish();
              });
              return req;
            };
            tx.objectStore = () => ({
              get: key => operation(() => structuredClone(values.get(key))),
              put: (value, key) => operation(() => { values.set(key, structuredClone(value)); return key; }),
              delete: key => operation(() => { values.delete(key); }),
              openKeyCursor(range) { return this.openCursor(range, true); },
              openCursor(range, keysOnly = false) {
                const req = {}, keys = [...values.keys()].sort().filter(k => !range || k >= range.lower && k <= range.upper);
                let index = 0; pending++;
                const next = () => queueMicrotask(() => {
                  const key = keys[index++];
                  req.result = key === undefined ? null : { key,
                    ...(keysOnly ? {} : { value: structuredClone(values.get(key)) }),
                    delete: () => operation(() => values.delete(key)), continue: next };
                  req.onsuccess?.();
                  if (key === undefined) { pending--; finish(); }
                });
                next(); return req;
              }
            });
            return tx;
          }
        };
        handles.push(db); request.result = db;
        if (fresh) request.onupgradeneeded?.();
        request.onsuccess();
      });
      return request;
    }
  };
  return fixture;
};
