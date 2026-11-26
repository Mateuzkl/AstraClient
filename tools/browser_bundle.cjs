'use strict';
// Lista explicita e auditoria dos bytes efetivamente incluidos; nunca avalia JS do pacote.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { spawnSync } = require('node:child_process');
const forbidden = /(?:^|\/)(?:\.git|\.env(?:\.[^/]*)?|config\.otml|test-secret\.invalid|.*\.(?:pem|key|pfx|p12|sql|dump|bak|backup|log|tmp|old|psd|pdb|exe|dll|obj))$/i;
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
function writeIfChanged(file, contents) {
  if (fs.existsSync(file) && fs.readFileSync(file, 'utf8') === contents) return;
  fs.writeFileSync(file, contents);
}
const textAsset = name => /\.(?:lua|js|cjs|json|otml|otui|otmod|otfi|cfg|html|txt|cpp|h|yml|yaml|xml|ini|toml|cmake|ps1|sh|md|pem|key|sql)$/.test(name) ||
  /(?:^|\/)\.env(?:\.[^/]*)?$/.test(name);
function stagingDirectory(root, binary) {
  const source = path.resolve(root), build = path.resolve(binary);
  const relative = path.relative(source, build);
  if (relative && (relative === '..' || relative.startsWith('..' + path.sep) || path.isAbsolute(relative)))
    return path.join(build, 'web-assets');
  // O diretorio de build padrao/CI fica dentro do checkout. O staging nao pode ficar ali.
  return path.join(path.dirname(source), '.astra-web-assets-' + hash(Buffer.from(build)).slice(0, 12));
}
function copyAsset(original, destination) {
  const source = fs.statSync(original);
  const old = fs.existsSync(destination) ? fs.statSync(destination) : null;
  if (old && old.size === source.size && Math.abs(old.mtimeMs - source.mtimeMs) < 1) return false;
  fs.copyFileSync(original, destination);
  fs.utimesSync(destination, source.atime, source.mtime);
  return true;
}
function validName(name) {
  if (typeof name !== 'string' || /[\\:\x00-\x1f]/.test(name) ||
      name.startsWith('/') || name.split('/').some(x => !x || x === '.' || x === '..' || x.toLowerCase() === '.git') || forbidden.test(name))
    throw new Error('Caminho proibido no pacote: ' + String(name));
  return name;
}
function metadata(source) {
  const match = /loadPackage\(\s*(\{\s*"?files"?\s*:)/.exec(source);
  if (!match) throw new Error('Indice de preload Emscripten ausente');
  const start = match.index + match[0].indexOf('{');
  let quoted = false, escaped = false, depth = 0;
  for (let end = start; end < source.length; ++end) {
    const c = source[end];
    if (quoted) { if (escaped) escaped = false; else if (c === '\\') escaped = true; else if (c === '"') quoted = false; }
    else if (c === '"') quoted = true;
    else if (c === '{') depth++;
    else if (c === '}' && --depth === 0) {
      return JSON.parse(source.slice(start, end + 1).replace(/"(?:[^"\\]|\\.)*"|[A-Za-z_]\w*(?=\s*:)/g,
        token => token.startsWith('"') ? token : JSON.stringify(token)));
    }
  }
  throw new Error('Indice truncado');
}
function secretFindings(name, bytes) {
  if (!textAsset(name)) return [];
  const lines = bytes.toString('utf8').split(/\r?\n/);
  const findings = [];
  for (let i = 0; i < lines.length; ++i) {
    if (/-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|\bAKIA[0-9A-Z]{16}\b|\bgh[pousr]_[A-Za-z0-9]{30,}\b/.test(lines[i]))
      findings.push({ file: name, line: i + 1, rule: 'private-key-or-token' });
    // Somente valores literais, nao nomes de variavel/comentarios. Nunca imprime o valor.
    if (!/^\s*(?:--|\/\/)/.test(lines[i]) &&
        /\b(?:db_password|api_secret|api_key|access_token|refresh_token)\b["']?\s*[:=]\s*["'][^"']{8,}["']/i.test(lines[i]))
      findings.push({ file: name, line: i + 1, rule: 'literal-sensitive-value' });
    if (!/^\s*(?:--|\/\/|#)/.test(lines[i]) && /https?:\/\/[^\s"'\/]+:[^\s"'\/@]+@/.test(lines[i]))
      findings.push({ file: name, line: i + 1, rule: 'url-credentials' });
  }
  return findings;
}
function inventory(root, policy) {
  const names = policy.files.map(validName);
  if (new Set(names).size !== names.length) throw new Error('Entradas duplicadas na lista');
  return names;
}
function canonicalOutput(target) {
  const remaining = [];
  let existing = path.resolve(target);
  while (!fs.existsSync(existing)) {
    const parent = path.dirname(existing);
    if (parent === existing) throw new Error('Diretorio de staging sem origem existente');
    remaining.unshift(path.basename(existing));
    existing = parent;
  }
  return path.join(fs.realpathSync(existing), ...remaining);
}
const SPR_PAGE_SIZE = 262144; // 256 KiB demand-paged SPR blocks.

function extractSprIndex(sprFilePath) {
  const fd = fs.openSync(sprFilePath, 'r');
  try {
    const stat = fs.fstatSync(fd);
    if (stat.size < 8) throw new Error('Tibia.spr truncado (< 8 bytes)');
    const header = Buffer.allocUnsafe(8);
    if (fs.readSync(fd, header, 0, 8, 0) !== 8) throw new Error('Falha ao ler cabecalho do Tibia.spr');
    const spriteCount = header.readUInt32LE(4);
    const tableBytes = spriteCount * 4;
    if (spriteCount <= 0 || 8 + tableBytes > stat.size) throw new Error('Tabela de sprites invalida em Tibia.spr');
    const out = Buffer.allocUnsafe(8 + tableBytes + 4);
    header.copy(out, 0);
    let readTotal = 0;
    while (readTotal < tableBytes) {
      const n = fs.readSync(fd, out, 8 + readTotal, tableBytes - readTotal, 8 + readTotal);
      if (n <= 0) throw new Error('Leitura incompleta da tabela de sprites');
      readTotal += n;
    }
    out.writeUInt32LE(stat.size >>> 0, 8 + tableBytes);
    return out;
  } finally {
    fs.closeSync(fd);
  }
}

function writeSprIndexIfChanged(sprFilePath, destIdxPath) {
  const idxBytes = extractSprIndex(sprFilePath);
  if (fs.existsSync(destIdxPath)) {
    const existing = fs.readFileSync(destIdxPath);
    if (existing.equals(idxBytes)) return idxBytes;
  }
  fs.mkdirSync(path.dirname(destIdxPath), { recursive: true });
  fs.writeFileSync(destIdxPath, idxBytes);
  return idxBytes;
}

function buildSprManifest(sprFilePath, pageSize = SPR_PAGE_SIZE) {
  const fd = fs.openSync(sprFilePath, 'r');
  try {
    const stat = fs.fstatSync(fd);
    if (stat.size < 8) throw new Error('Tibia.spr truncado (< 8 bytes)');
    const header = Buffer.allocUnsafe(8);
    if (fs.readSync(fd, header, 0, 8, 0) !== 8) throw new Error('Falha ao ler cabecalho do Tibia.spr');
    const spriteCount = header.readUInt32LE(4);
    const indexBytes = 8 + spriteCount * 4;
    if (spriteCount <= 0 || indexBytes > stat.size) throw new Error('Tabela de sprites invalida em Tibia.spr');

    const totalDigest = crypto.createHash('sha256');
    const hashes = [];
    const buf = Buffer.allocUnsafe(pageSize);
    let offset = 0;
    while (offset < stat.size) {
      const toRead = Math.min(pageSize, stat.size - offset);
      let got = 0;
      while (got < toRead) {
        const n = fs.readSync(fd, buf, got, toRead - got, offset + got);
        if (n <= 0) throw new Error('Leitura incompleta de Tibia.spr ao gerar spr-manifest.json');
        got += n;
      }
      const slice = buf.subarray(0, toRead);
      totalDigest.update(slice);
      hashes.push(crypto.createHash('sha256').update(slice).digest('hex'));
      offset += toRead;
    }
    return {
      schema: 1,
      version: '8.60',
      file: 'Tibia.spr',
      size: stat.size,
      pageSize,
      spriteCount,
      indexBytes,
      uuid: 'sha256-' + totalDigest.digest('hex'),
      hashes,
    };
  } finally {
    fs.closeSync(fd);
  }
}

function preparePagedSpr(thingsRoot, profileDist) {
  const srcSpr = path.join(thingsRoot, 'Tibia.spr');
  if (!fs.existsSync(srcSpr)) throw new Error('Asset obrigatorio ausente: Tibia.spr');
  fs.mkdirSync(profileDist, { recursive: true });
  const dstSpr = path.join(profileDist, 'Tibia.spr');
  const sprReplaced = copyAsset(srcSpr, dstSpr);
  const manifestPath = path.join(profileDist, 'spr-manifest.json');
  const sprStat = fs.statSync(srcSpr);
  if (!sprReplaced && fs.existsSync(manifestPath)) {
    try {
      const existing = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
      const mStat = fs.statSync(manifestPath);
      if (existing && existing.schema === 1 && existing.size === sprStat.size &&
          existing.pageSize === SPR_PAGE_SIZE && mStat.mtimeMs >= sprStat.mtimeMs) {
        return existing;
      }
    } catch (_) {}
  }
  const sprManifest = buildSprManifest(srcSpr);
  fs.writeFileSync(manifestPath, JSON.stringify(sprManifest, null, 2) + '\n');
  return sprManifest;
}

function stage(root, policy, target, things) {
  const names = inventory(root, policy);
  const realRoot = fs.realpathSync(root) + path.sep;
  const output = canonicalOutput(target);
  const relative = path.relative(realRoot, output);
  if (relative !== '..' && !relative.startsWith('..' + path.sep) && !path.isAbsolute(relative))
    throw new Error('Staging deve ficar fora da arvore original');
  // Nao apaga diretorios arbitrarios: sobrescreve apenas arquivos explicitamente permitidos.
  fs.mkdirSync(output, { recursive: true });
  for (const name of names) {
    const original = path.join(root, name);
    if (!fs.realpathSync(original).startsWith(realRoot) || fs.lstatSync(original).isSymbolicLink())
      throw new Error('Arquivo fora da origem permitida: ' + name);
    const findings = textAsset(name) ? secretFindings(name, fs.readFileSync(original)) : [];
    if (findings.length) throw new Error('Possivel segredo: ' + JSON.stringify(findings));
    const destination = path.join(output, name);
    fs.mkdirSync(path.dirname(destination), { recursive: true });
    copyAsset(original, destination);
  }
  const pagedSpr = policy.sprMode === 'paged';
  const stagedThings = [];
  for (const name of policy.things) {
    if (!['Tibia.dat', 'Tibia.spr', 'Tibia.otfi', 'Tibia.otml'].includes(name)) throw new Error('Pack inesperado');
    const original = path.join(things, name);
    if (!fs.existsSync(original)) {
      if (name === 'Tibia.dat' || name === 'Tibia.spr') throw new Error('Asset obrigatorio ausente: ' + name);
      continue;
    }
    if (pagedSpr && name === 'Tibia.spr') {
      const idxName = 'data/things/860/Tibia.spr.idx';
      writeSprIndexIfChanged(original, path.join(output, idxName));
      stagedThings.push(idxName);
      continue;
    }
    const destination = path.join(output, 'data/things/860', name);
    fs.mkdirSync(path.dirname(destination), { recursive: true });
    copyAsset(original, destination);
    stagedThings.push('data/things/860/' + name);
  }
  // Sem glob no linker: cada arquivo listado recebe seu proprio caminho virtual.
  const virtual = [...names, ...stagedThings];
  writeIfChanged(path.join(output, 'preload.rsp'), virtual.map(n => '--preload-file="' + path.join(output, n).replaceAll('\\', '/') + '@/' + n + '"').join('\n'));
  writeIfChanged(path.join(output, 'dependencies.cmake'), 'set(ASTRA_WASM_ASSET_FILES\n' +
    [...names.map(n => path.join(root, n)), ...policy.things.map(n => path.join(things, n)).filter(n => fs.existsSync(n))]
      .map(n => '  "' + n.replaceAll('\\', '/') + '"').join('\n') + '\n)\n');
  return virtual;
}
function audit(dist, policy, sourceRoot, thingsRoot) {
  const pagedSpr = policy.sprMode === 'paged';
  const publicFiles = new Set(['astraclient.html', 'astraclient.js', 'astraclient.wasm', 'astraclient.data',
    'asset-manifest.json', 'browser-bundle-audit.json', 'config.js', 'platform.js', 'runtime.js', 'security.js',
    'spr-pager.js', 'bootstrap.js', 'asset-cache.js', 'launcher.js', 'launcher.css', 'launcher-background.png',
    'astra-client-emblem.png', 'profiles.json']);
  if (pagedSpr) {
    publicFiles.add('Tibia.spr');
    publicFiles.add('spr-manifest.json');
  }
  for (const file of fs.readdirSync(dist)) {
    const full = path.join(dist, file);
    if (!publicFiles.has(file) || !fs.lstatSync(full).isFile())
      throw new Error('Arquivo publico inesperado: ' + file);
    if (textAsset(file)) {
      const findings = secretFindings(file, fs.readFileSync(full));
      if (findings.length) throw new Error('Possivel segredo publico: ' + JSON.stringify(findings));
    }
  }
  const meta = metadata(fs.readFileSync(path.join(dist, 'astraclient.js'), 'utf8'));
  const bytes = fs.readFileSync(path.join(dist, 'astraclient.data'));
  if (meta.remote_package_size !== bytes.length) throw new Error('Tamanho do pacote divergente');
  const allowedThings = policy.things.map(n => (pagedSpr && n === 'Tibia.spr') ? 'data/things/860/Tibia.spr.idx' : 'data/things/860/' + n);
  const allowed = new Set([...policy.files, ...allowedThings]);
  const seen = new Set(), report = [];
  let offset = 0;
  for (const entry of meta.files) {
    const name = validName(entry.filename.replace(/^\//, ''));
    if (!allowed.has(name) || seen.has(name)) throw new Error('Arquivo inesperado ou duplicado: ' + name);
    if (!Number.isSafeInteger(entry.start) || !Number.isSafeInteger(entry.end) ||
        entry.start !== offset || entry.end < entry.start || entry.end > bytes.length) throw new Error('Offsets invalidos: ' + name);
    const body = bytes.subarray(entry.start, entry.end);
    const secrets = secretFindings(name, body);
    if (secrets.length) throw new Error('Possivel segredo no pacote: ' + JSON.stringify(secrets));
    if (sourceRoot) {
      if (pagedSpr && name === 'data/things/860/Tibia.spr.idx') {
        const expectedIdx = extractSprIndex(path.join(thingsRoot, 'Tibia.spr'));
        if (hash(expectedIdx) !== hash(body)) throw new Error('Conteudo divergente da origem: ' + name);
      } else {
        const original = name.startsWith('data/things/860/')
          ? path.join(thingsRoot, path.basename(name)) : path.join(sourceRoot, name);
        if (hash(fs.readFileSync(original)) !== hash(body)) throw new Error('Conteudo divergente da origem: ' + name);
      }
    }
    report.push({ file: name, size: body.length, sha256: hash(body) });
    seen.add(name); offset = entry.end;
  }
  if (offset !== bytes.length) throw new Error('Bytes nao descritos pelo indice');
  const requiredSpr = pagedSpr ? 'data/things/860/Tibia.spr.idx' : 'data/things/860/Tibia.spr';
  for (const name of [...policy.files, 'data/things/860/Tibia.dat', requiredSpr])
    if (!seen.has(name)) throw new Error('Arquivo permitido obrigatorio ausente: ' + name);
  if (pagedSpr) {
    const sprManifestFile = path.join(dist, 'spr-manifest.json');
    const sprFile = path.join(dist, 'Tibia.spr');
    if (!fs.existsSync(sprManifestFile) || !fs.existsSync(sprFile))
      throw new Error('Perfil paged SPR requer Tibia.spr e spr-manifest.json no dist');
    const sprManifest = JSON.parse(fs.readFileSync(sprManifestFile, 'utf8'));
    if (sprManifest.schema !== 1 || sprManifest.version !== '8.60' || sprManifest.file !== 'Tibia.spr' ||
        sprManifest.size !== fs.statSync(sprFile).size ||
        !Array.isArray(sprManifest.hashes) ||
        sprManifest.hashes.length !== Math.ceil(sprManifest.size / sprManifest.pageSize))
      throw new Error('spr-manifest.json invalido');
  }
  return { schema: 1, sprMode: pagedSpr ? 'paged' : 'bundled', packageBytes: bytes.length, packageSha256: hash(bytes), fileCount: report.length, files: report };
}
function scan(root) {
  const listed = spawnSync('git', ['ls-files', '--cached', '--others', '--exclude-standard', '-z'], { cwd: root, encoding: 'utf8' });
  if (listed.status !== 0) throw new Error('Falha ao inventariar o repositorio');
  const findings = [];
  for (const file of listed.stdout.split('\0').filter(Boolean)) {
    // Fixtures ficticias de seguranca sao deliberadas; nao se publicam no .data.
    if (file.startsWith('.github/tests/') || file.startsWith('browser/tests/')) continue;
    if (textAsset(file)) findings.push(...secretFindings(file, fs.readFileSync(path.join(root, file))));
  }
  return findings;
}
module.exports = { metadata, stage, audit, validName, secretFindings, scan, stagingDirectory, extractSprIndex, buildSprManifest, preparePagedSpr };
if (require.main === module) {
  try {
    const [mode, root, policyFile, target, things] = process.argv.slice(2);
    if (mode === 'stage-path') { console.log(stagingDirectory(root, policyFile)); process.exit(0); }
    if (mode === 'prepare-spr') {
      const sprManifest = preparePagedSpr(path.resolve(root), path.resolve(policyFile));
      console.log('SPR paginado pronto: ' + sprManifest.hashes.length + ' paginas de ' + sprManifest.pageSize + ' bytes (' + sprManifest.size + ' bytes)');
      process.exit(0);
    }
    const policy = mode === 'scan' ? null : JSON.parse(fs.readFileSync(policyFile));
    if (mode === 'scan') {
      const findings = scan(path.resolve(root));
      console.log(JSON.stringify({ findings }, null, 2));
      if (findings.length) process.exitCode = 1;
    } else if (mode === 'stage') console.log('Arquivos web permitidos: ' + stage(path.resolve(root), policy, target, things).length);
    else if (mode === 'audit') {
      const report = audit(target, policy, root, things);
      fs.writeFileSync(path.join(target, 'browser-bundle-audit.json'), JSON.stringify(report, null, 2) + '\n');
      console.log('Auditoria do pacote: PASS, ' + report.fileCount + ' arquivos, ' + report.packageBytes + ' bytes');
    } else throw new Error('Modo deve ser stage, audit, scan, stage-path ou prepare-spr');
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
