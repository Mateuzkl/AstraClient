import importlib.util
from pathlib import Path
import unittest
import sys

sys.dont_write_bytecode = True

spec = importlib.util.spec_from_file_location(
    'normalizer', Path(__file__).resolve().parents[2] / 'tools/normalize_browser_text_assets.py')
normalizer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(normalizer)


class TextAssetTests(unittest.TestCase):
    def test_legacy_strings_retain_font_bytes(self):
        raw = b'local value="caf\xe91"; local icon="\xfe" -- caf\xe9\n'
        self.assertEqual(normalizer.decode_asset(raw, lua=True),
                         'local value="caf\\2331"; local icon="\\254" -- café\n')

    def test_comments_and_escaped_quotes_are_not_confused_with_strings(self):
        raw = b'-- "caf\xe9"\n--[[ "\xfe" ]]\nlocal value="say \\"caf\xe9\\""'
        self.assertEqual(normalizer.decode_asset(raw, lua=True),
                         '-- "café"\n--[[ "þ" ]]\nlocal value="say \\"caf\\233\\""')

    def test_existing_utf8_and_bom_removal_do_not_change_string_contents(self):
        text = 'local value="café"'
        self.assertEqual(normalizer.decode_asset(text.encode(), lua=True), text)
        self.assertEqual(normalizer.decode_asset(b'\xef\xbb\xbf' + text.encode(), lua=True), text)
        normalized = normalizer.decode_asset(b'local value="caf\xe9"', lua=True)
        self.assertEqual(normalizer.decode_asset(normalized.encode(), lua=True), normalized)

    def test_legacy_long_strings_require_explicit_handling(self):
        with self.assertRaises(ValueError):
            normalizer.decode_asset(b'local value=[=[caf\xe9]=]', lua=True)


if __name__ == '__main__':
    unittest.main()
