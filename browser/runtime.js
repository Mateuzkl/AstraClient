/* Browser-only endpoint, cursor and persistence helpers, shared with regression tests. */
(() => {
  'use strict';
  const supplied = window.ASTRA_CONFIG || {};
  const config = {
    title: 'Astra Web',
    loginUrl: '',
    ...supplied,
    game: { scheme: 'auto', host: '', port: null, path: '', ...(supplied.game || {}) },
    httpOverrides: { ...(supplied.httpOverrides || {}) },
    websocketOverrides: { ...(supplied.websocketOverrides || {}) }
  };
  window.ASTRA_CONFIG = config;
  document.title = config.title;

  // Opening a crafted link must not change where passwords are sent.
  const query = new URLSearchParams(location.search);
  if (['gameHost', 'gamePort', 'gamePath', 'gameScheme', 'loginUrl'].some(key => query.has(key)))
    console.warn('AstraClient ignores endpoint query parameters. Configure trusted destinations in config.js.');

  const websocketBase = () => {
    const url = new URL(document.baseURI);
    url.protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
    return url;
  };
  const validate = (value, websocket) => {
    const url = new URL(value, websocket ? websocketBase() : document.baseURI);
    const protocols = websocket ? ['ws:', 'wss:'] : ['http:', 'https:'];
    if (!protocols.includes(url.protocol) || url.username || url.password || url.hash)
      throw new Error('Invalid AstraClient endpoint (scheme, credentials or fragment).');
    if (location.protocol === 'https:' && (url.protocol === 'http:' || url.protocol === 'ws:'))
      throw new Error('Mixed content blocked: HTTPS pages require HTTPS/WSS endpoints.');
    return url;
  };
  const setPort = (url, value) => {
    if (value == null || value === '') return;
    const port = Number(value);
    if (!Number.isInteger(port) || port < 1 || port > 65535)
      throw new Error('Invalid AstraClient endpoint port.');
    url.port = String(port);
  };
  const hostUrl = (host, port, scheme) => {
    const value = String(host);
    if (/^wss?:\/\//i.test(value)) return validate(value, true);
    // Reject user-info, paths and malformed schemes in a bare hostname.
    if (!value || /[\s\/@?#]/.test(value) || value.includes('://'))
      throw new Error('Invalid AstraClient endpoint hostname.');
    const authority = value.includes(':') && !value.startsWith('[') ? `[${value}]` : value;
    const url = validate(`${scheme}://${authority}/`, true);
    setPort(url, port);
    return url;
  };

  window.AstraBrowser = {
    createCursorManager() {
      const cursors = new Map();
      let active = null;
      const apply = cursor => {
        const canvas = document.getElementById('canvas');
        if (!canvas) return;
        // Clear a stale/hidden cursor even when the replacement is rejected.
        canvas.style.cursor = 'auto';
        if (cursor && cursor !== 'none') canvas.style.cursor = cursor;
      };
      const aliases = {
        arrow: 'default', native: 'default', hand: 'pointer', link: 'pointer',
        cross: 'crosshair', target: 'crosshair', precision: 'crosshair',
        horizontal: 'ew-resize', sizewe: 'ew-resize', vertical: 'ns-resize', sizens: 'ns-resize',
        diagonal1: 'nwse-resize', sizenwse: 'nwse-resize', diagonal2: 'nesw-resize', sizenesw: 'nesw-resize',
        sizeall: 'move', ibeam: 'text', hourglass: 'wait', no: 'not-allowed', forbidden: 'not-allowed',
        appstarting: 'progress', uparrow: 'default'
      };
      const keywords = new Set(('auto default pointer text crosshair ew-resize ns-resize nwse-resize nesw-resize ' +
        'n-resize s-resize e-resize w-resize ne-resize nw-resize se-resize sw-resize col-resize row-resize ' +
        'move wait help progress not-allowed context-menu cell vertical-text alias copy no-drop ' +
        'all-scroll zoom-in zoom-out grab grabbing').split(' '));
      return {
        setSystemCursor(name) {
          active = null; // A late image load must not replace a widget's newer cursor.
          const requested = String(name || '').trim().toLowerCase();
          const cursor = aliases[requested] || requested;
          apply(keywords.has(cursor) ? cursor : 'auto');
        },
        createCursor(id, pixels, width, height, hotX, hotY) {
          const previous = cursors.get(id);
          cursors.delete(id);
          if (previous && active === previous) { active = null; apply('auto'); }
          if (!Number.isInteger(id) || id < 0 || !Number.isInteger(width) || !Number.isInteger(height) ||
              width < 1 || height < 1 || width > 128 || height > 128 ||
              !Number.isInteger(hotX) || !Number.isInteger(hotY) || hotX < 0 || hotY < 0 ||
              hotX >= width || hotY >= height || !pixels || pixels.length !== width * height * 4)
            return false;
          let visible = false;
          for (let i = 3; i < pixels.length; i += 4) {
            if (pixels[i] !== 0) { visible = true; break; }
          }
          if (!visible) return false;
          try {
            const surface = document.createElement('canvas');
            surface.width = width;
            surface.height = height;
            const context = surface.getContext('2d');
            if (!context) return false;
            // Copy out of WASM's shared heap; ImageData requires a normal buffer.
            context.putImageData(new ImageData(new Uint8ClampedArray(pixels), width, height), 0, 0);
            const url = surface.toDataURL('image/png');
            if (!url.startsWith('data:image/png;base64,') || url.length <= 22) return false;
            const image = new Image();
            const entry = { css: `url("${url}") ${hotX} ${hotY}, auto`, ready: false, image };
            cursors.set(id, entry);
            image.onload = () => {
              if (cursors.get(id) !== entry) return;
              entry.ready = true;
              if (active === entry) apply(entry.css);
            };
            image.onerror = () => {
              if (cursors.get(id) === entry) cursors.delete(id);
              if (active === entry) { active = null; apply('auto'); }
            };
            image.src = url;
            return true;
          } catch (_) {
            cursors.delete(id);
            return false;
          }
        },
        useCursor(id) {
          active = cursors.get(id) || null;
          apply(active && active.ready ? active.css : 'auto');
        },
        dispose() {
          for (const entry of cursors.values()) {
            entry.image.onload = null;
            entry.image.onerror = null;
          }
          cursors.clear();
          active = null;
          apply('auto');
        }
      };
    },

    installTextBridge(module) {
      let active = true;
      const listeners = [];
      const listen = (target, type, callback) => {
        target.addEventListener(type, callback);
        listeners.push([target, type, callback]);
      };
      listen(document, 'paste', event => {
        if (!active) return;
        const text = event.clipboardData ? event.clipboardData.getData('text/plain') : '';
        if (text) {
          module.ccall('astra_browser_paste', null, ['string'], [text]);
          event.preventDefault();
        }
      });
      const editor = document.getElementById('astra-virtual-keyboard');
      if (editor) {
        listen(editor, 'beforeinput', event => {
          if (active && event.inputType === 'deleteContentBackward') {
            module.ccall('astra_browser_virtual_key', null, ['number'], [8]);
            event.preventDefault();
          }
        });
        listen(editor, 'input', event => {
          if (!active) return;
          if (event.data) module.ccall('astra_browser_text_input', null, ['string'], [event.data]);
          editor.value = '';
        });
        listen(editor, 'keydown', event => {
          if (active && event.key === 'Enter') {
            module.ccall('astra_browser_virtual_key', null, ['number'], [13]);
            event.preventDefault();
          }
        });
      }
      return () => {
        active = false;
        for (const [target, type, callback] of listeners) target.removeEventListener(type, callback);
        listeners.length = 0;
      };
    },

    resolveWebSocketUrl(originalHost, originalPort) {
      const explicit = /^wss?:\/\//i.test(String(originalHost));
      if (originalPort != null) {
        const port = Number(originalPort);
        if (originalPort === '' || !Number.isInteger(port) || port < 1 || port > 65535)
          throw new Error('Invalid AstraClient endpoint port.');
      } else if (!explicit) {
        throw new Error('A bare AstraClient hostname requires a port.');
      }
      const source = hostUrl(originalHost, originalPort, location.protocol === 'https:' ? 'wss' : 'ws');
      const port = originalPort ?? (source.port || (source.protocol === 'wss:' ? 443 : 80));
      const key = `${source.hostname.toLowerCase()}:${port}`;
      if (Object.prototype.hasOwnProperty.call(config.websocketOverrides, key))
        return validate(config.websocketOverrides[key], true).href;

      const game = config.game;
      const scheme = game.scheme === 'auto'
        ? (location.protocol === 'https:' ? 'wss' : 'ws') : String(game.scheme).replace(/:$/, '');
      if (scheme !== 'ws' && scheme !== 'wss')
        throw new Error('Invalid AstraClient WebSocket scheme.');
      const url = game.host ? hostUrl(game.host, originalPort, scheme) : source;
      if (!/^wss?:\/\//i.test(game.host || originalHost)) url.protocol = `${scheme}:`;
      setPort(url, game.port);
      if (game.path) url.pathname = game.path.startsWith('/') ? game.path : `/${game.path}`;
      return validate(url.href, true).href;
    },

    resolveHttpUrl(original) {
      const source = new URL(original, document.baseURI);
      if (config.loginUrl && /(^|\/)login(?:\.[a-z0-9]+)?\/?$/i.test(source.pathname))
        return validate(config.loginUrl, false).href;
      // Keys match the exact URL supplied by the client, not the resolved URL:
      // relative requests need relative keys. Keep longest-prefix matching.
      const prefix = Object.keys(config.httpOverrides)
        .filter(key => original.startsWith(key)).sort((a, b) => b.length - a.length)[0];
      return validate(prefix ? `${config.httpOverrides[prefix]}${original.slice(prefix.length)}` : original, false).href;
    },

    resolveGenericWebSocketUrl(original) { return validate(original, true).href; },

    createPersistence(fs, reload) {
      let running = false;
      let pending = false;
      let reloadRequested = false;
      const sync = () => {
        if (running) {
          // A reload requested during a periodic flush must include newer writes.
          pending = true;
          return;
        }
        running = true;
        let completed = false;
        const finish = error => {
          if (completed) return;
          completed = true;
          running = false;
          if (error) console.error('Unable to persist AstraClient data:', error);
          if (pending) {
            pending = false;
            sync();
          } else if (reloadRequested) {
            reloadRequested = false;
            reload();
          }
        };
        try { fs.syncfs(false, finish); }
        catch (error) { finish(error); }
      };
      return {
        sync,
        reload() {
          if (reloadRequested) return;
          reloadRequested = true;
          sync();
        }
      };
    },

    restorePersistence(fs, ready) {
      let completed = false;
      const finish = error => {
        if (completed) return;
        completed = true;
        if (error) console.error('Unable to restore AstraClient data:', error);
        ready();
      };
      try { fs.syncfs(true, finish); }
      catch (error) { finish(error); }
    },

    installPersistenceHooks(sync) {
      let active = true;
      const flush = () => { if (active) sync(); };
      const visibility = () => { if (document.visibilityState === 'hidden') flush(); };
      const interval = window.setInterval(flush, 15000);
      window.addEventListener('pagehide', flush);
      document.addEventListener('visibilitychange', visibility);
      return () => {
        active = false;
        window.clearInterval(interval);
        window.removeEventListener('pagehide', flush);
        document.removeEventListener('visibilitychange', visibility);
      };
    }
  };
})();
