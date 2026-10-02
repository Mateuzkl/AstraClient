/* Browser-only endpoint and persistence helpers, shared with regression tests. */
(() => {
  'use strict';
  const supplied = window.ASTRA_CONFIG || {};
  const config = {
    title: 'AstraClient',
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
    resolveWebSocketUrl(originalHost, originalPort) {
      const source = hostUrl(originalHost, originalPort, location.protocol === 'https:' ? 'wss' : 'ws');
      const key = `${source.hostname.toLowerCase()}:${originalPort}`;
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
        fs.syncfs(false, error => {
          running = false;
          if (error) console.error('Unable to persist AstraClient data:', error);
          if (pending) {
            pending = false;
            sync();
          } else if (reloadRequested) {
            reloadRequested = false;
            reload();
          }
        });
      };
      return {
        sync,
        reload() {
          if (reloadRequested) return;
          reloadRequested = true;
          sync();
        }
      };
    }
  };
})();
