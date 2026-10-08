import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('manifest', Path(__file__).parents[2] / 'tools/browser_manifest.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ManifestTest(unittest.TestCase):
    def test_actual_package_metadata_and_identity(self):
        with tempfile.TemporaryDirectory() as temp:
            dist = Path(temp)
            data = b'Astra assets'
            metadata = {'files': [{'filename': '/data/things/860/Tibia.dat', 'start': 0, 'end': len(data)}],
                        'remote_package_size': len(data), 'package_uuid': 'sha256-' + hashlib.sha256(data).hexdigest()}
            (dist / 'astraclient.data').write_bytes(data)
            (dist / 'astraclient.js').write_text('var PACKAGE_NAME = "dist/astraclient.data"; loadPackage(' + json.dumps(metadata) + ');')
            result = module.create_manifest(dist)
            self.assertEqual(result['groups'], {'things': len(data)})
            self.assertEqual(result['bootPackageBytes'], len(data))
            self.assertEqual(result['deferredPackageBytes'], 0)
            self.assertEqual(result['largestFiles'][0], {'file': 'data/things/860/Tibia.dat', 'size': len(data)})
            self.assertEqual(result['chunks'][0]['sha256'], hashlib.sha256(data).hexdigest())
            # The real Release linker removes quotes from JS property names.
            (dist / 'astraclient.js').write_text('var PACKAGE_NAME="dist/astraclient.data"; loadPackage({files:[{filename:"/data/things/a,start:1.dat",start:0,end:12}],remote_package_size:12,package_uuid:"' + metadata['package_uuid'] + '"});')
            self.assertEqual(module.create_manifest(dist)['groups'], {'things': len(data)})
            # The pinned SDK omits UUID when its own preload cache is disabled.
            del metadata['package_uuid']
            (dist / 'astraclient.js').write_text('var PACKAGE_NAME="dist/astraclient.data"; loadPackage(' + json.dumps(metadata) + ');')
            self.assertEqual(module.create_manifest(dist)['uuid'], 'sha256-' + hashlib.sha256(data).hexdigest())
            for wrong_uuid in [None, '', 'sha256-wrong']:
                metadata['package_uuid'] = wrong_uuid
                (dist / 'astraclient.js').write_text('var PACKAGE_NAME="dist/astraclient.data"; loadPackage(' + json.dumps(metadata) + ');')
                with self.assertRaisesRegex(ValueError, 'does not match'):
                    module.create_manifest(dist)
            del metadata['package_uuid']
            (dist / 'astraclient.js').write_text('var PACKAGE_NAME="dist/astraclient.data"; loadPackage(' + json.dumps(metadata) + ');')
            (dist / 'astraclient.data').write_bytes(b'corrupt')
            with self.assertRaisesRegex(ValueError, 'does not match'):
                module.create_manifest(dist)

    def test_group_report_keeps_images_and_minimap_separate(self):
        with tempfile.TemporaryDirectory() as temp:
            dist = Path(temp)
            names = ['data/images/a.png', 'data/default.otmm', 'data/fonts/a.png',
                     'data/json/a.json', 'data/sounds/a.ogg', 'data/styles/a.otui',
                     'modules/a.lua', 'mods/a.lua', 'layouts/a.otui']
            files = [{'filename': '/' + name, 'start': index, 'end': index + 1}
                     for index, name in enumerate(names)]
            (dist / 'astraclient.data').write_bytes(b'x' * len(files))
            (dist / 'astraclient.js').write_text('var PACKAGE_NAME="dist/astraclient.data"; loadPackage(' +
                                               json.dumps({'files': files, 'remote_package_size': len(files)}) + ');')
            result = module.create_manifest(dist)
            self.assertEqual(result['groups'], dict.fromkeys(
                ['images', 'minimap', 'fonts', 'json', 'sounds', 'styles', 'modules', 'mods', 'layouts'], 1))


if __name__ == '__main__':
    unittest.main()
