'use strict';
const assert = require('node:assert/strict');
const { test } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const { validateDefaultOptions } = require('../../tools/check_default_options.cjs');
const source = fs.readFileSync(path.join(__dirname, '../../data/json/default-options.json'));
test('the production defaults have all required fields', () => {
  assert.ok(validateDefaultOptions(source).bytes > 100 * 1024);
});
test('reject incomplete downloads', () => {
  assert.throws(() => validateDefaultOptions(source.subarray(0, 6400)), /small|Invalid/);
});
test('reject valid JSON missing critical sections', () => {
  const remove = [
    d => { delete d.hotkeyOptions; }, d => { delete d.options; },
    d => { delete d.controlButtonsOptions; }, d => { delete d.DummyProfile; },
    d => { delete d.hotkeyOptions.hotkeySets.Knight.chatOn; },
    d => { delete d.chatOptions.openChannels; }
  ];
  for (const mutation of remove) {
    const damaged = JSON.parse(source.toString('utf8'));
    mutation(damaged);
    assert.throws(() => validateDefaultOptions(JSON.stringify(damaged)), /Missing|Invalid/);
  }
});
