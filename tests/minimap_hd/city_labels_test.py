"""Escaped OTBM town parsing, hash association, and no-overwrite guarantees."""
import hashlib
import importlib.util
import json
import struct
import tempfile
from pathlib import Path

spec = importlib.util.spec_from_file_location('cities', Path(__file__).parents[2] / 'tools/minimap_hd/city_labels.py')
cities = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cities)

def node(kind, props=b'', children=b''):
    escaped = bytearray()
    for b in props:
        if b in (253, 254, 255): escaped.append(253)
        escaped.append(b)
    return bytes((254, kind)) + escaped + children + bytes((255,))

def town(tid, name, x, y, z):
    return node(13, struct.pack('<IH', tid, len(name)) + name + struct.pack('<HHB', x, y, z))

with tempfile.TemporaryDirectory() as folder:
    root = Path(folder)
    world = root / 'world.otbm'
    data = b'OTBM' + node(0, children=node(2, children=node(12, children=
        town(1,b'City',1000,1000,7) + town(2,b'Escaped \xfd\xfe\xff',253,255,6) + town(3,b'Underground',5,5,8))))
    world.write_bytes(data)
    digest = hashlib.sha256(data).hexdigest()
    pack = root / 'pack'; pack.mkdir()
    (pack / 'source.json').write_text(json.dumps(dict(world_sha256=digest)))
    result = cities.export(world,pack)
    assert result['world_sha256']==digest and len(result['labels'])==2
    assert result['labels'][1]['name']=='Escaped ýþÿ' and result['labels'][1]['position']==dict(x=253,y=255,z=6)
    try: cities.export(world,pack)
    except ValueError: pass
    else: raise AssertionError('Exporter overwrote curated labels')
    (pack / 'source.json').write_text(json.dumps(dict(world_sha256='0'*64)))
    try: cities.export(world,pack)
    except ValueError: pass
    else: raise AssertionError('Accepted another world')
    for invalid in (data[:-1], b'FAIL'+data[4:], b'OTBM'+node(0,children=node(12,children=town(1,b'A',5,5,7)+town(1,b'B',6,6,7)))):
        world.write_bytes(invalid)
        try: cities.town_labels(world)
        except ValueError: pass
        else: raise AssertionError('Accepted invalid OTBM')
print('PASS: actual OTBM town anchors, escapes, underground filtering, world hash, malformed input, no overwrite')
