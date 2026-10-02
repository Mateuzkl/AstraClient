// Node-only fixture for the actual Emscripten Fetch library.
globalThis.XMLHttpRequest = class {
  constructor() { this.readyState = 0; this.status = 0; this.responseURL = ''; }
  open(method, url) { this.url = url; this.readyState = 1; }
  setRequestHeader() {}
  getAllResponseHeaders() { return ''; }
  send() {
    if (this.url.includes('/sync-error')) throw new Error('Synchronous XHR.send failure');
  }
  abort() { this.readyState = 4; }
};
