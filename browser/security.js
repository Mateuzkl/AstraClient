/* Seguranca do navegador: nenhuma credencial reutilizavel vai para armazenamento. */
(() => {
  'use strict';
  const credentialKeys = new Set(['password', 'accountpassword', 'gtoken', 'ptoken', 'token',
    'authenticatortoken', 'sessionkey', 'accesstoken', 'refreshtoken', 'googlesession', 'autologin']);
  const isCredentialKey = key => credentialKeys.has(key.toLowerCase().replace(/[_-]/g, ''));
  window.AstraSecurity = {
    scrubSettings(text) {
      let skipIndent = null;
      const clean = text.split(/\r?\n/).filter(line => {
        if (!line.trim()) return skipIndent === null;
        const indent = line.match(/^\s*/)[0].length;
        if (skipIndent !== null && indent > skipIndent) return false;
        skipIndent = null;
        const entry = line.match(/^\s*([^:#]+):/);
        const key = entry && entry[1].trim().replace(/^(?:"(.*)"|'(.*)')$/, (_, a, b) => a ?? b);
        if (key && isCredentialKey(key)) { skipIndent = indent; return false; }
        return true;
      }).join('\n');
      return text.endsWith('\n') && clean && !clean.endsWith('\n') ? clean + '\n' : clean;
    },
    purgeSettings(fs) {
      if (!fs.analyzePath('/user/config.otml').exists) return false;
      const old = fs.readFile('/user/config.otml', { encoding: 'utf8' });
      const clean = this.scrubSettings(old);
      if (clean === old) return false;
      fs.writeFile('/user/config.otml', clean);
      return true;
    },
    createPosts(fetcher, maximum = 16 * 1024 * 1024) {
      const pending = new Map();
      const cancel = id => {
        const op = pending.get(id);
        if (!op) return;
        pending.delete(id);
        clearTimeout(op.timer);
        op.controller.abort();
      };
      return {
        cancel,
        pendingCount: () => pending.size,
        start(id, url, body, headers, timeout, callback) {
          cancel(id);
          const op = { controller: new AbortController() };
          pending.set(id, op);
          const finish = (status, bytes, responseHeaders, error) => {
            if (pending.get(id) !== op) return;
            pending.delete(id);
            clearTimeout(op.timer);
            callback(status, bytes, responseHeaders, error);
          };
          op.timer = setTimeout(() => {
            op.controller.abort();
            finish(0, new Uint8Array(), {}, 'Secure HTTP request timed out');
          }, timeout);
          (async () => {
            let reader;
            try {
              const response = await fetcher(url, { method: 'POST', body, headers,
                redirect: 'error', credentials: 'omit', cache: 'no-store', referrerPolicy: 'no-referrer',
                signal: op.controller.signal });
              if (pending.get(id) !== op) { await response.body?.cancel(); return; }
              const declared = Number(response.headers.get('content-length'));
              if (declared > maximum) throw new Error('limit');
              reader = response.body?.getReader();
              const chunks = [];
              let size = 0;
              if (reader) while (true) {
                const { done, value } = await reader.read();
                if (pending.get(id) !== op) { await reader.cancel(); return; }
                if (done) break;
                if (value.byteLength > maximum - size) throw new Error('limit');
                size += value.byteLength;
                chunks.push(value);
              }
              const bytes = new Uint8Array(size);
              let offset = 0;
              for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
              finish(response.status, bytes, Object.fromEntries(response.headers.entries()),
                response.ok ? '' : `HTTP error ${response.status}`);
            } catch (_) {
              op.controller.abort();
              if (reader) { try { await reader.cancel(); } catch (_) {} }
              // Nao inclui URL, payload, mensagem remota ou tokens em diagnosticos.
              finish(0, new Uint8Array(), {}, 'Secure HTTP request failed (redirects are not permitted)');
            }
          })();
        }
      };
    }
  };
})();
