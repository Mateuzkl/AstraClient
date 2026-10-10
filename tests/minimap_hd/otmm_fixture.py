"""Make a sparse user OTMM overlay to ensure it cannot erase revealed cells."""
import json
import struct
import sys
import zlib
from pathlib import Path

source, target = map(Path, sys.argv[1:3])
data = source.read_bytes()
offset = struct.unpack_from('<H', data, 4)[0]
while offset < len(data):
    x, y, z = struct.unpack_from('<HHB', data, offset)
    offset += 5
    if z == 255:
        raise ValueError('Revealed map contains no occupied test block')
    length = struct.unpack_from('<H', data, offset)[0]
    offset += 2
    tiles = zlib.decompress(data[offset:offset + length])
    offset += length
    known = [i for i in range(4096) if tiles[i * 3 + 1] != 255]
    if len(known) < 2:
        continue
    changed, preserved = known[:2]
    color = 77 if tiles[changed * 3 + 1] != 77 else 78
    sparse = bytearray(b'\0\xff\x0a' * 4096)
    sparse[changed * 3:changed * 3 + 3] = bytes((1, color, 10))
    compressed = zlib.compress(sparse)
    header = struct.pack('<IHHIH', 0x4D4D544F, 22, 1, 0, 8) + b'OTMM 1.0'
    block = struct.pack('<HHBH', x, y, z, len(compressed)) + compressed
    (target / 'classic-overlay.otmm').write_bytes(header + block + struct.pack('<HHB', 65535, 65535, 255))
    def position(index):
        return {'x': x + index % 64, 'y': y + index // 64, 'z': z}
    fixture = {'changed': position(changed), 'preserved': position(preserved),
               'color': color, 'preserved_color': tiles[preserved * 3 + 1]}
    (target / 'classic-overlay.json').write_text(json.dumps(fixture))
    break
