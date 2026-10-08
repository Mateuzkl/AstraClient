const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { test } = require('node:test');
const { audit, stage, secretFindings, stagingDirectory } = require('../../tools/browser_bundle.cjs');
function fixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'astra-bundle-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const dist = path.join(root, 'dist'); fs.mkdirSync(dist);
  const policy = { files: ['init.lua'], things: ['Tibia.dat', 'Tibia.spr'] };
  const pack = entries => {
    let offset = 0;
    const files = entries.map(([filename, bytes]) => {
      const record = { filename: '/' + filename, start: offset, end: offset + Buffer.byteLength(bytes) };
      offset = record.end; return record;
    });
    fs.writeFileSync(path.join(dist, 'astraclient.js'), 'loadPackage(' + JSON.stringify({ files, remote_package_size: offset }) + ');');
    fs.writeFileSync(path.join(dist, 'astraclient.data'), Buffer.concat(entries.map(([, bytes]) => Buffer.from(bytes))));
  };
  const entries = [['init.lua', 'return true'], ['data/things/860/Tibia.dat', 'dat'], ['data/things/860/Tibia.spr', 'spr']];
  pack(entries);
  return { root, dist, policy, entries, pack };
}
test('auditor reads actual preload bytes and rejects injected private/unlisted content', t => {
  const f = fixture(t);
  const good = audit(f.dist, f.policy);
  assert.equal(good.fileCount, 3); assert.equal(good.files[0].size, 11);
  assert.equal(good.files[0].sha256, require('node:crypto').createHash('sha256').update('return true').digest('hex'));
  f.pack([...f.entries, ['test-secret.invalid', 'FAKE-NOT-A-REAL-SECRET']]);
  assert.throws(() => audit(f.dist, f.policy), /inesperado|proibido/);
  f.pack(f.entries); assert.equal(audit(f.dist, f.policy).fileCount, 3);
  f.pack([['init.lua', '-- -----BEGIN PRIVATE KEY-----'], ...f.entries.slice(1)]);
  assert.throws(() => audit(f.dist, f.policy), /Possivel segredo/);
  for (const name of ['.env', 'config.otml', '../escape', 'private.key', 'dir\\escape', '.git/config', '.GIT/config']) {
    f.pack([...f.entries, [name, 'fake']]); assert.throws(() => audit(f.dist, f.policy), /proibido/);
  }
  f.pack(f.entries);
  fs.writeFileSync(path.join(f.dist, '.env'), 'fictitious');
  assert.throws(() => audit(f.dist, f.policy), /publico inesperado/);
});
test('explicit staging excludes new files and never modifies the source tree', t => {
  const f = fixture(t), source = path.join(f.root, 'source'), output = path.join(f.root, 'stage');
  fs.mkdirSync(source); fs.writeFileSync(path.join(source, 'init.lua'), 'return true');
  fs.writeFileSync(path.join(source, 'test-secret.invalid'), 'fake');
  fs.writeFileSync(path.join(source, 'Tibia.dat'), 'dat'); fs.writeFileSync(path.join(source, 'Tibia.spr'), 'spr');
  stage(source, f.policy, output, source);
  const old = new Date('2000-01-01T00:00:00Z');
  for (const file of ['preload.rsp', 'dependencies.cmake']) fs.utimesSync(path.join(output, file), old, old);
  stage(source, f.policy, output, source);
  for (const file of ['preload.rsp', 'dependencies.cmake'])
    assert.equal(fs.statSync(path.join(output, file)).mtimeMs, old.getTime(), 'unchanged staging must not force reconfigure');
  assert.equal(fs.existsSync(path.join(output, 'test-secret.invalid')), false);
  assert.equal(fs.readFileSync(path.join(source, 'test-secret.invalid'), 'utf8'), 'fake');
  assert.throws(() => stage(source, f.policy, path.join(source, 'stage'), source), /fora/);
  assert.throws(() => stage(source, { ...f.policy, files: ['test-secret.invalid'] }, output, source), /proibido/);
});
test('scanner reports only path, rule and line, never the matched token value', () => {
  const fake = 'ghp_' + 'a'.repeat(36);
  const findings = secretFindings('sample.lua', Buffer.from('local api_key = "fictitious-test-key"\n-- ' + fake));
  assert.equal(findings.length, 2);
  assert.doesNotMatch(JSON.stringify(findings), /fictitious-test-key|ghp_/);
  for (const file of ['login.otui', 'module.otmod', 'things.otfi', 'settings.ini', '.env'])
    assert.equal(secretFindings(file, Buffer.from('api_key = "fictitious-test-key"')).length, 1);
});

test('staging rejects source aliases and nonexistent paths below symlinked parents', t => {
  const f = fixture(t), source = path.join(f.root, 'source'), alias = path.join(f.root, 'checkout-link');
  fs.mkdirSync(source);
  fs.writeFileSync(path.join(source, 'init.lua'), 'return true');
  fs.writeFileSync(path.join(source, 'Tibia.dat'), 'dat');
  fs.writeFileSync(path.join(source, 'Tibia.spr'), 'spr');
  try { fs.symlinkSync(source, alias, process.platform === 'win32' ? 'junction' : 'dir'); }
  catch (error) {
    if (['EPERM', 'EACCES', 'ENOTSUP'].includes(error.code)) { t.skip('directory links unavailable'); return; }
    throw error;
  }
  assert.throws(() => stage(alias, f.policy, alias, source), /fora/);
  const nested = path.join(alias, 'not-created', 'stage');
  assert.throws(() => stage(alias, f.policy, nested, source), /fora/);
  assert.equal(fs.existsSync(path.join(source, 'not-created')), false);
  const external = path.join(f.root, 'outside', 'stage');
  stage(alias, f.policy, external, source);
  assert.equal(fs.readFileSync(path.join(external, 'init.lua'), 'utf8'), 'return true');
});

test('default CI builds inside the checkout still stage outside the original source', t => {
  const f = fixture(t);
  for (const binary of [f.root, path.join(f.root, 'build-wasm-release')]) {
    const output = stagingDirectory(f.root, binary);
    assert.equal(path.dirname(output), path.dirname(f.root));
    assert.equal(output, stagingDirectory(f.root, binary));
  }
  const external = path.join(path.dirname(f.root), 'outside-build');
  assert.equal(stagingDirectory(f.root, external), path.join(external, 'web-assets'));
});

test('client load-later dependencies are present or explicitly excluded for Web only', () => {
  const root = path.join(__dirname, '../..');
  const policy = JSON.parse(fs.readFileSync(path.join(root, 'browser/production-assets.json')));
  const client = fs.readFileSync(path.join(root, 'modules/client/client.otmod'), 'utf8');
  const list = name => {
    const block = client.match(new RegExp('^  ' + name + ':\\r?\\n((?:    - [^\\r\\n]+\\r?\\n)+)', 'm'));
    assert.ok(block, 'module list missing: ' + name);
    return block[1].split(/\r?\n/).filter(Boolean).map(line => line.trim().slice(2));
  };
  const excluded = list('browser-excluded-load-later');
  const modules = new Set(policy.files.filter(file => file.endsWith('.otmod')).map(file => {
    const text = fs.readFileSync(path.join(root, file), 'utf8');
    return text.match(/^\s+name:\s*([^\r\n]+)/m)[1].trim();
  }));
  assert.ok(list('load-later').includes('client_autoreloadmodule'), 'native dependency must remain');
  assert.ok(excluded.includes('client_autoreloadmodule'));
  assert.equal(modules.has('client_autoreloadmodule'), false);
  for (const name of list('load-later'))
    assert.ok(excluded.includes(name) || modules.has(name), 'missing Web dependency: ' + name);
});
