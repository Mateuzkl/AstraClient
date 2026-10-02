const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');

const source = fs.readFileSync(path.join(__dirname, '..', 'runtime.js'), 'utf8');
function fixture(options = {}) {
  const canvas = { style: { cursor: 'none' } };
  const images = [];
  const context = {
    URL, URLSearchParams, Uint8ClampedArray,
    location: new URL('http://localhost:8080/astraclient.html'),
    console: { warn() {}, error() {} },
    document: {
      baseURI: 'http://localhost:8080/astraclient.html',
      getElementById: () => canvas,
      createElement: () => ({
        getContext: () => options.noContext ? null : { putImageData() {} },
        toDataURL() {
          if (options.encodeError) throw new Error('Unable to encode cursor');
          return options.url ?? 'data:image/png;base64,fixture';
        }
      })
    },
    ImageData: class { constructor(pixels, width, height) { this.data = pixels; } },
    Image: class { constructor() { images.push(this); } }
  };
  context.window = context;
  vm.runInNewContext(source, context);
  return { api: context.AstraBrowser.createCursorManager(), canvas, images };
}
const pixels = () => new Uint8Array([255, 255, 255, 255, 0, 0, 0, 0]);

test('hidden, invalid and missing cursors fall back to a visible system cursor', () => {
  const { api, canvas } = fixture();
  for (const name of ['none', '', 'unknown', 'url(transparent.png)', 'inherit']) {
    canvas.style.cursor = 'none';
    api.setSystemCursor(name);
    assert.equal(canvas.style.cursor, 'auto');
  }
  canvas.style.cursor = 'none';
  api.useCursor(999);
  assert.equal(canvas.style.cursor, 'auto');
});

test('widget system cursors retain text, button and resize states', () => {
  const { api, canvas } = fixture();
  for (const [name, expected] of Object.entries({
    native: 'default', hand: 'pointer', cross: 'crosshair', ibeam: 'text',
    horizontal: 'ew-resize', vertical: 'ns-resize', diagonal1: 'nwse-resize',
    diagonal2: 'nesw-resize', text: 'text', auto: 'auto'
  })) {
    api.setSystemCursor(name);
    assert.equal(canvas.style.cursor, expected);
  }
});

test('custom cursor is visible only after its PNG has decoded and always has a fallback', () => {
  const { api, canvas, images } = fixture();
  assert.equal(api.createCursor(0, pixels(), 2, 1, 1, 0), true);
  api.useCursor(0);
  assert.equal(canvas.style.cursor, 'auto');
  images[0].onload();
  assert.equal(canvas.style.cursor, 'url("data:image/png;base64,fixture") 1 0, auto');
  api.setSystemCursor('auto');
  assert.equal(canvas.style.cursor, 'auto');
  api.useCursor(0);
  assert.match(canvas.style.cursor, /^url\(.*\) 1 0, auto$/);
});

test('transparent or malformed custom images are rejected', () => {
  const { api, canvas } = fixture();
  for (const args of [
    [0, new Uint8Array(8), 2, 1, 0, 0],
    [0, pixels(), 1, 1, 0, 0],
    [0, pixels(), 2, 1, -1, 0],
    [0, pixels(), 2, 1, 2, 0],
    [0, pixels(), 129, 1, 0, 0]
  ]) {
    assert.equal(api.createCursor(...args), false);
    api.useCursor(0);
    assert.equal(canvas.style.cursor, 'auto');
  }
  for (const options of [{ noContext: true }, { encodeError: true }, { url: 'data:,' }]) {
    const f = fixture(options);
    assert.equal(f.api.createCursor(0, pixels(), 2, 1, 0, 0), false);
    f.api.useCursor(0);
    assert.equal(f.canvas.style.cursor, 'auto');
  }
});

test('decode failure restores the cursor and cannot erase a newer widget state', () => {
  const { api, canvas, images } = fixture();
  api.createCursor(0, pixels(), 2, 1, 0, 0);
  api.useCursor(0);
  images[0].onerror();
  assert.equal(canvas.style.cursor, 'auto');
  api.useCursor(0);
  assert.equal(canvas.style.cursor, 'auto');
  api.createCursor(1, pixels(), 2, 1, 0, 0);
  api.useCursor(1);
  api.setSystemCursor('text');
  images[1].onerror();
  assert.equal(canvas.style.cursor, 'text');
});

test('late loads cannot override system cursors, another custom cursor or a reused ID', () => {
  const { api, canvas, images } = fixture();
  api.createCursor(0, pixels(), 2, 1, 0, 0);
  api.useCursor(0);
  api.setSystemCursor('hand');
  images[0].onload();
  assert.equal(canvas.style.cursor, 'pointer');
  api.createCursor(1, pixels(), 2, 1, 1, 0);
  api.useCursor(1);
  images[0].onload();
  assert.equal(canvas.style.cursor, 'auto');
  images[1].onload();
  assert.match(canvas.style.cursor, / 1 0, auto$/);
  api.createCursor(1, pixels(), 2, 1, 0, 0);
  assert.equal(canvas.style.cursor, 'auto');
  api.useCursor(1);
  images[1].onload();
  images[1].onerror();
  assert.equal(canvas.style.cursor, 'auto');
  images[2].onload();
  assert.match(canvas.style.cursor, / 0 0, auto$/);
});

test('cursor teardown releases images and late callbacks cannot hide a newer cursor', () => {
  const { api, canvas, images } = fixture();
  api.createCursor(0, pixels(), 2, 1, 0, 0);
  api.useCursor(0);
  const lateLoad = images[0].onload;
  const lateError = images[0].onerror;
  api.dispose();
  assert.equal(images[0].onload, null);
  assert.equal(images[0].onerror, null);
  assert.equal(canvas.style.cursor, 'auto');
  api.setSystemCursor('text');
  lateLoad();
  lateError();
  assert.equal(canvas.style.cursor, 'text');
  api.useCursor(0);
  assert.equal(canvas.style.cursor, 'auto');
});
