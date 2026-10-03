// Node-only DOM fixture: the pinned SDK itself invokes the C++ callback and
// decides whether to cancel the synchronous DOM event.
globalThis.window = globalThis;
navigator.userActivation = { isActive: false };
globalThis.location = new URL('http://localhost/astraclient.html');
const astraKeyListeners = new Map();
globalThis.addEventListener = (type, callback) => {
  if (!astraKeyListeners.has(type)) astraKeyListeners.set(type, new Set());
  astraKeyListeners.get(type).add(callback);
};
globalThis.removeEventListener = (type, callback) => astraKeyListeners.get(type)?.delete(callback);
globalThis.astraKeyboardTest = {
  canvas: {}, editor: {}, control: {},
  emit(type, code, key = code, modifier = '') {
    const event = { code, key, timeStamp: 1, defaultPrevented: false,
      preventDefault() { this.defaultPrevented = true; }, [modifier]: true };
    for (const callback of astraKeyListeners.get(type) || []) callback(event);
    return event.defaultPrevented;
  },
  count() { return [...astraKeyListeners.values()].reduce((count, entries) => count + entries.size, 0); }
};
globalThis.document = {
  baseURI: location.href,
  activeElement: astraKeyboardTest.canvas,
  getElementById(id) { return id === 'canvas' ? astraKeyboardTest.canvas : astraKeyboardTest.editor; }
};
