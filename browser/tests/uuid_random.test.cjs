const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { webcrypto } = require('node:crypto');
const { test } = require('node:test');
// Exercita o corpo EM_JS da producao, nao uma segunda implementacao do gerador.
const source = fs.readFileSync(path.join(__dirname, '../../src/framework/util/crypt.cpp'), 'utf8');
const body = source.match(/EM_JS\(int, astraRandomUuid, \(unsigned char\* bytes\), \{([\s\S]*?)\n\}\);/);
assert.ok(body, 'production UUID entropy provider must be found');
function provider(crypto) {
  const heap = new Uint8Array(new SharedArrayBuffer(64));
  const random = vm.runInNewContext('(function(bytes) {' + body[1] + '})',
    { crypto, HEAPU8: heap, Uint8Array });
  return { heap, random };
}
test('production UUID randomness copies secure entropy into the shared WASM heap', () => {
  let calls = 0;
  const p = provider({ getRandomValues(bytes) {
    assert.equal(bytes.buffer instanceof SharedArrayBuffer, false, 'Web Crypto rejects shared views');
    assert.equal(bytes.length, 16); calls++;
    return webcrypto.getRandomValues(bytes);
  } });
  assert.equal(p.random(16), 1); assert.equal(calls, 1);
  assert.equal(p.heap.slice(16, 32).some(x => x !== 0), true);
  assert.equal(p.heap.slice(0, 16).some(x => x !== 0), false);
  assert.equal(p.heap.slice(32).some(x => x !== 0), false);
});
test('unavailable secure entropy fails closed without a weak fallback or partial heap write', () => {
  for (const crypto of [undefined, { getRandomValues() { throw new Error('unavailable'); } }]) {
    const p = provider(crypto);
    assert.equal(p.random(16), 0);
    assert.equal(p.heap.some(x => x !== 0), false);
  }
});
