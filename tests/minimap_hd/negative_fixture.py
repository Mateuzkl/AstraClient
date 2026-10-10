"""Small isolated adversarial fixtures, never edits the installed satellite pack."""
import json
import struct
import sys
import zlib
from pathlib import Path
from PIL import Image

info = json.loads(Path(sys.argv[1]).read_text())
root = Path(sys.argv[2]) / 'negative'
root.mkdir()


def enc3(data: bytes, seed: int = 0) -> bytes:
    """Fixture encoder matching Crypt::bencrypt, including the unaligned tail."""
    payload = bytearray(zlib.compress(data))
    count = len(payload) // 4
    words = list(struct.unpack('<' + 'I' * count, payload[:count * 4]))
    key64, total = 0x1020304050607080, 0
    key = [key64 >> 32, key64 & 0xffffffff, 0xDEADDEAD, 0xB00BEEEF]
    if count >= 2:
        z = words[-1]
        for _ in range(6 + 52 // count):
            total = (total + 0x9e3779b9) & 0xffffffff
            e = (total >> 2) & 3
            for p in range(count):
                y = words[(p + 1) % count]
                mx = (((z >> 5 ^ y << 2) + (y >> 3 ^ z << 4)) ^
                      ((total ^ y) + (key[(p & 3) ^ e] ^ z)))
                words[p] = (words[p] + mx) & 0xffffffff
                z = words[p]
        payload[:count * 4] = struct.pack('<' + 'I' * count, *words)
    return b'ENC3' + struct.pack('<QIII', key64, len(payload), len(data), zlib.adler32(data) ^ seed) + payload


for kind in ('valid', 'encrypted', 'oversized', 'animated', 'truncated', 'enc3-bomb', 'missing', 'seeded', 'bad-seed', 'bad-signature', 'bad-index'):
    directory = root / kind
    directory.mkdir()
    signature = info['dat_signature'] + (kind == 'bad-signature')
    count = 2 if kind == 'bad-index' else 1
    (directory / 'index.txt').write_text(
        f"ASTRAHD 1 16 32 {signature} {info['spr_signature']} {count}\n"
        "1 96 96 7 satellite-1-96-96-7.png\n")
    path = directory / 'satellite-1-96-96-7.png'
    if kind == 'missing':
        continue
    image = Image.new('RGBA', (512, 512), 'red')
    image.save(path)
    if kind == 'oversized':
        path.write_bytes(path.read_bytes() + bytes(4 * 1024 * 1024 + 1))
    elif kind == 'animated':
        image.save(path, save_all=True, append_images=[Image.new('RGBA', image.size, 'blue')], duration=100, loop=0)
    elif kind == 'truncated':
        path.write_bytes(path.read_bytes()[:-10])
    elif kind == 'enc3-bomb':
        path.write_bytes(b'ENC3' + struct.pack('<QIII', 0, 1, 100 * 1024 * 1024, 0) + b'X')
    elif kind in ('encrypted', 'seeded', 'bad-seed'):
        seed = {'encrypted': 0, 'seeded': 0x1357BEEF, 'bad-seed': 0x2468CAFE}[kind]
        path.write_bytes(enc3(path.read_bytes(), seed))

# Header + one invalid compressed block + normal terminator.
description = b'OTMM 1.0'
header = struct.pack('<IHHIH', 0x4D4D544F, 14 + len(description), 1, 0, len(description)) + description
(root / 'corrupt.otmm').write_bytes(header + struct.pack('<HHBH', 96, 96, 7, 7) + b'invalid' + struct.pack('<HHB', 65535, 65535, 255))
print('Prepared isolated PNG/index/ENC3/OTMM rejection fixtures')
