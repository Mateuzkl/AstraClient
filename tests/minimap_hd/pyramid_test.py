"""Regression checks for geometry, floor separation and persistent pack output."""
import importlib.util
import tempfile
from unittest.mock import patch
from pathlib import Path
from PIL import Image

spec = importlib.util.spec_from_file_location('pyramid', Path(__file__).resolve().parents[2] / 'tools/minimap_hd/build_pyramid.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
with tempfile.TemporaryDirectory(prefix='astra-pyramid-test-') as task:
    root = Path(task)
    source, destination = root / 'source', root / 'pack'
    source.mkdir()
    fixtures = [(0, 0, 7, 'red'), (16, 0, 7, 'green'),
                (0, 16, 7, 'blue'), (16, 16, 7, 'yellow'), (0, 0, 8, 'white')]
    rows = ['ASTRAHDBASE 1 16 32 123 456 5']
    for x, y, z, color in fixtures:
        name = f'satellite-1-{x}-{y}-{z}.png'
        Image.new('RGBA', (512, 512), color).save(source / name)
        rows.append(f'1 {x} {y} {z} {name}')
    (source / 'index.base.txt').write_text('\n'.join(rows) + '\n')
    (source / 'minimap.otmm').write_bytes(b'fixture-otmm')
    result = module.build(source, destination)
    assert result['base_chunks'] == 5 and result['floors'] == [7, 8]
    assert result['levels'] == [1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024]
    with Image.open(destination / 'satellite-2-0-0-7.png') as image:
        for point, expected in [((100, 100), (255, 0, 0, 255)), ((400, 100), (0, 128, 0, 255)),
                                ((100, 400), (0, 0, 255, 255)), ((400, 400), (255, 255, 0, 255))]:
            assert image.getpixel(point) == expected, 'LOD child placement changed'
    with Image.open(destination / 'satellite-2-0-0-8.png') as image:
        assert image.getpixel((100, 100)) == (255, 255, 255, 255)
        assert image.getpixel((400, 400))[3] == 0, 'Unknown regions must stay transparent'
    assert (destination / 'minimap.otmm').read_bytes() == b'fixture-otmm'
    rows = (destination / 'index.txt').read_text().splitlines()
    assert int(rows[0].split()[-1]) == len(rows) - 1 == result['total_chunks']
    try:
        module.build(source, destination)
    except ValueError:
        pass
    else:
        raise AssertionError('Existing packs must not be silently overwritten')
    for name, limit, copy_failure in [('overflow', 6, False), ('copy-failure', 100000, True)]:
        failed = root / name
        with patch.object(module, 'MAX_PACK_CHUNKS', limit):
            try:
                if copy_failure:
                    with patch.object(module.shutil, 'copyfile', side_effect=OSError('fixture copy failed')):
                        module.build(source, failed)
                else:
                    module.build(source, failed)
            except (ValueError, OSError):
                pass
            else:
                raise AssertionError('Invalid/incomplete packs must fail')
        assert not (failed / 'index.txt').exists(), 'Failed output must not be published'
    # Optional town metadata must not make a valid PNG/OTMM pack unpublished.
    # This synthetic base already exists; only its town metadata is malformed.
    world = root / 'metadata-world.otbm'
    world.write_bytes(b'OTBM' + bytes((254,0,254,12,254,13,1,255,255,255)))
    optional = root / 'optional-labels'
    module.build(source, optional, world=world)
    assert (optional / 'index.txt').exists() and not (optional / 'cities.json').exists()
    (source / 'minimap.otmm').unlink()
    missing = root / 'missing-otmm'
    try:
        module.build(source, missing)
    except ValueError as error:
        assert 'minimap.otmm' in str(error)
    else:
        raise AssertionError('OTMM must be required')
    assert not (missing / 'index.txt').exists()
print('PASS: LOD geometry, floors, OTMM preservation, manifest, no overwrite, overflow/missing/copy-failure rejection')
