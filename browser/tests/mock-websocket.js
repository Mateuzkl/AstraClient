// Node-only WebSocket fixture. The actual Emscripten library marshals events.
globalThis.astraTestSockets = [];
globalThis.WebSocket = class {
  constructor(url) {
    this.url = url;
    this.readyState = 0;
    globalThis.astraTestSockets.push(this);
  }
  close() { this.readyState = 3; }
  emitEvents() {
    this.onopen?.({});
    this.onerror?.({});
    this.onclose?.({ wasClean: true, code: 1000, reason: 'test close' });
    this.onmessage?.({ data: new Uint8Array([1, 2, 3]).buffer });
  }
};
