"""Export town anchors from the actual OTBM, tied to its HD pack's world hash.

Town temple positions are truthful initial anchors, not guessed visual city
centers. Review/move labels in cities.json for a custom map if desired.
This reads the server map without changing it or any PNG/OTMM.
"""
import argparse
import hashlib
import json
import struct
from pathlib import Path


def town_labels(world: Path) -> list:
    if not 4 < world.stat().st_size <= 512 * 1024 * 1024:
        raise ValueError('Invalid/over-budget OTBM size')
    data = world.read_bytes()
    if data[:4] not in (b'OTBM', bytes(4)):
        raise ValueError('Invalid OTBM identifier')
    stack, towns, ids = [], [], set()
    escaped = False
    for byte in data[4:]:
        if escaped:
            if not stack: raise ValueError('Escape outside node')
            if stack[-1][1] == 13: stack[-1][2].append(byte)
            escaped = False
        elif byte == 253:
            escaped = True
        elif byte == 254:
            if len(stack) >= 64: raise ValueError('Excessive OTBM nesting')
            stack.append([stack[-1][1] if stack else None, None, bytearray()])
        elif byte == 255:
            if not stack: raise ValueError('Unexpected node end')
            parent, kind, props = stack.pop()
            if kind == 13 and parent == 12:
                if len(props) < 11: raise ValueError('Truncated town')
                tid, length = struct.unpack_from('<IH', props)
                if len(props) != 11 + length or tid in ids: raise ValueError('Invalid/duplicate town')
                ids.add(tid)
                raw = props[6:6 + length]
                try: name = raw.decode('utf-8')
                except UnicodeDecodeError: name = raw.decode('latin-1')
                x, y, z = struct.unpack_from('<HHB', props, 6 + length)
                if tid and name and x and y and z <= 7:
                    towns.append(dict(id=f'town-{tid}', name=name, position=dict(x=x, y=y, z=z),
                                      minZoom=-8, priority=100, anchor='otbm-temple'))
        elif not stack:
            raise ValueError('Data outside node')
        elif stack[-1][1] is None:
            stack[-1][1] = byte
        elif stack[-1][1] == 13:
            stack[-1][2].append(byte)
    if stack or escaped: raise ValueError('Incomplete OTBM tree')
    return sorted(towns, key=lambda town: town['id'])


def export(world: Path, pack: Path) -> dict:
    source = json.loads((pack / 'source.json').read_text(encoding='utf-8'))
    with world.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    if digest != source.get('world_sha256'):
        raise ValueError('OTBM does not match the installed HD pack; refusing wrong-world labels')
    result = dict(format=1, world_sha256=digest, labels=town_labels(world))
    target = pack / 'cities.json'
    if target.exists(): raise ValueError('cities.json already exists; preserve/review it before exporting again')
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('world', type=Path)
    parser.add_argument('pack', type=Path)
    args = parser.parse_args()
    print(json.dumps(export(args.world, args.pack), ensure_ascii=False, indent=2))
