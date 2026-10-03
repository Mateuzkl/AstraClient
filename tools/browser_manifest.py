"""Describe the actual pinned-SDK preload package for the browser launcher.

Uses the existing Emscripten cache format, not a second asset store. Generated
files belong in dist, never in the repository. Optional compression reporting
is a measurement, not a production compression/deployment policy.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path

CHUNK_SIZE = 64 * 1024 * 1024  # Emscripten 6.0.8 EM_PRELOAD_CACHE chunk size.


def create_manifest(dist):
    source = (dist / 'astraclient.js').read_text(encoding='utf-8')
    match = re.search(r'var PACKAGE_NAME\s*=\s*("[^"\n]+")', source)
    package = re.search(r'loadPackage\(\s*(\{\s*"?files"?\s*:)', source)
    if not match or not package:
        raise ValueError('Unsupported SDK preload format; expected Emscripten 6.0.8 cache metadata')
    # Release minification removes quotes from property names. Tokenize quoted
    # strings first so filenames containing punctuation are never rewritten.
    literal = re.sub(r'"(?:[^"\\]|\\.)*"|[A-Za-z_]\w*(?=\s*:)',
                     lambda token: token.group() if token.group().startswith('"') else json.dumps(token.group()),
                     source[package.start(1):])
    metadata, _ = json.JSONDecoder().raw_decode(literal)
    groups = {}
    for entry in metadata['files']:
        name = entry['filename'].lstrip('/')
        group = 'things' if name.startswith('data/things/') else name.split('/')[0]
        groups[group] = groups.get(group, 0) + entry['end'] - entry['start']
    digest = hashlib.sha256()
    chunks = []
    with (dist / 'astraclient.data').open('rb') as stream:
        while data := stream.read(CHUNK_SIZE):
            digest.update(data)
            chunks.append({'size': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
    size = (dist / 'astraclient.data').stat().st_size
    uuid = 'sha256-' + digest.hexdigest()
    if ('package_uuid' in metadata and uuid != metadata['package_uuid']) or size != metadata['remote_package_size']:
        raise ValueError('The generated .data does not match the SDK preload identity')
    return {
        'schema': 1, 'version': '8.60', 'packageName': json.loads(match.group(1)),
        'uuid': uuid, 'file': 'astraclient.data', 'size': size, 'chunks': chunks,
        'groups': groups,
        'artifacts': {p.name: p.stat().st_size for p in sorted(dist.iterdir())
                      if p.suffix in ('.js', '.wasm', '.data', '.png', '.css', '.html')}
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('dist', type=Path)
    parser.add_argument('--compression-report', action='store_true')
    args = parser.parse_args()
    manifest = create_manifest(args.dist)
    (args.dist / 'asset-manifest.json').write_text(
        json.dumps(manifest, sort_keys=True, indent=2) + '\n', encoding='utf-8')
    print(f"Browser bundle: {manifest['size'] / 1048576:.2f} MiB, {len(manifest['chunks'])} cache chunks")
    if args.compression_report:
        import zlib
        compressor = zlib.compressobj(6, zlib.DEFLATED, 31)
        compressed = 0
        with (args.dist / manifest['file']).open('rb') as stream:
            while block := stream.read(1024 * 1024):
                compressed += len(compressor.compress(block))
        compressed += len(compressor.flush())
        print(json.dumps({'raw_bytes': manifest['size'], 'gzip_level6_bytes': compressed,
                          'groups': manifest['groups'], 'artifacts': manifest['artifacts']}, indent=2))


if __name__ == '__main__':
    main()
