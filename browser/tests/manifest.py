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
            self.assertEqual(result['chunks'][0]['sha256'], hashlib.sha256(data).hexdigest())
            # The real Release linker removes quotes from JS property names.
            (dist / 'astraclient.js').write_text('var PACKAGE_NAME="dist/astraclient.data"; loadPackage({files:[{filename:"/data/things/a,start:1.dat",start:0,end:12}],remote_package_size:12,package_uuid:"' + metadata['package_uuid'] + '"});')
            self.assertEqual(module.create_manifest(dist)['groups'], {'things': len(data)})
            (dist / 'astraclient.data').write_bytes(b'corrupt')
            with self.assertRaisesRegex(ValueError, 'does not match'):
                module.create_manifest(dist)


if __name__ == '__main__':
    unittest.main()
