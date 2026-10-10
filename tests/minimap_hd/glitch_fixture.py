"""Opaque indexed LODs over deliberately contrasting classic OTMM terrain."""
import json
import struct
import sys
import zlib
from pathlib import Path
from PIL import Image


def color(level, x, y, floor):
    return (20 + (x // (16 * level) % 4) * 8,
            80 + (y // (16 * level) % 4) * 8 + (floor - 7) * 32,
            150 + level)


if __name__ == '__main__':
    info = json.loads(Path(sys.argv[1]).read_text())
    root = Path(sys.argv[2]) / 'glitch-pack'
    root.mkdir()
    entries = []
    for floor in (7, 8):
        for level in (1, 2, 4, 8, 16):
            size = 16 * level
            for y in range(4096, 4224, size):
                for x in range(4096, 4224, size):
                    name = f'satellite-{level}-{x}-{y}-{floor}.png'
                    Image.new('RGBA', (512, 512), (*color(level, x, y, floor), 255)).save(root / name)
                    entries.append(f'{level} {x} {y} {floor} {name}')
    header = f"ASTRAHD 1 16 32 {info['dat_signature']} {info['spr_signature']} {len(entries)}"
    (root / 'index.txt').write_text(header + '\n' + '\n'.join(entries) + '\n')
    # Known bright classic color cannot be confused with an HD chunk.
    otmm = bytearray(struct.pack('<IHHIH', 0x4D4D544F, 22, 1, 0, 8) + b'OTMM 1.0')
    compressed = zlib.compress(bytes((1, 192, 10)) * 4096)
    for floor in (7, 8):
        for y in range(4096, 4352, 64):
            for x in range(4096, 4352, 64):
                otmm += struct.pack('<HHBH', x, y, floor, len(compressed)) + compressed
    otmm += struct.pack('<HHB', 65535, 65535, 255)
    (root / 'minimap.otmm').write_bytes(otmm)
    print('Prepared isolated contrasting-OTMM / coherent-LOD fixtures')
