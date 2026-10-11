import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('policy', Path(__file__).resolve().parents[2] / 'tools/check_cpp23.py')
policy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(policy)


class PolicyTests(unittest.TestCase):
    def test_exactly_one_supported_flag(self):
        for command in ['cl /std:c++23preview /c x.cpp', 'c++ -std=c++23 x.cpp', 'cl -std:c++23preview x.cpp']:
            policy.check_command(command, 'test')
        for command in ['cl /std:c++latest x.cpp', 'c++ -std=c++20 x.cpp', 'cl x.cpp', 'c++ -std=c++17 -std=c++23 x.cpp', 'c++ -std=gnu++23 x.cpp', 'c++ -std=gnu++23 -std=c++23 x.cpp']:
            with self.assertRaises(ValueError):
                policy.check_command(command, 'test')

    def test_real_command_db_and_vendor_exclusion(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'compile_commands.json'
            entries = [{'file': '/app/src/main.cpp', 'command': 'c++ -std=c++23 x.cpp'},
                       {'file': '/app/build/_deps/vendor/x.cpp', 'command': 'c++ -std=c++17 x.cpp'},
                       {'file': '/app/src/qrcode.c', 'command': 'cc -std=gnu99 x.c'}]
            path.write_text(json.dumps(entries), encoding='utf-8')
            policy.check_compile_commands(path)
            entries[0]['command'] = 'c++ -std=c++17 x.cpp'
            path.write_text(json.dumps(entries), encoding='utf-8')
            with self.assertRaises(ValueError):
                policy.check_compile_commands(path)

    def test_real_msbuild_commands(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'CL.command.1.tlog'
            path.write_text('^C:\\MAIN.CPP\n/c /std:c++23preview /TP C:\\MAIN.CPP\n^C:\\QRCODE.C\n/c /TC C:\\QRCODE.C\n', encoding='utf-16')
            policy.check_tlog(path)
            path.write_text('^C:\\MAIN.CPP\n/c /std:c++latest /TP C:\\MAIN.CPP\n', encoding='utf-16')
            with self.assertRaises(ValueError):
                policy.check_tlog(path)


if __name__ == '__main__':
    unittest.main()
