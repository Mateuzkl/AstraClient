"""Audit owned build routes and actual compiler commands; never audit vendor flags."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
LEGACY_ANDROID = 'android/otclientv8_lib/otclientv8_lib.vcxproj'
BUILD_SUFFIXES = {'.cmake', '.vcxproj', '.props', '.targets', '.sh', '.ps1', '.bat', '.cmd', '.mk', '.mak', '.yml', '.yaml'}
BUILD_NAMES = {'CMakeLists.txt', 'Makefile', 'makefile', 'GNUmakefile', 'CMakePresets.json', 'CMakeUserPresets.json'}
INVENTORY = re.compile(r'CXX_STANDARD|CXX_EXTENSIONS|cxx_std_|stdcpp\w+|CppLanguageStandard|LanguageStandard|c\+\+1z|/std:|-std=|Clang_5_0')
OLD = re.compile(r'(?:/std:c\+\+|-std=(?:c\+\+|gnu\+\+))(?:98|03|11|14|17|20|1z|2a|latest)\b|stdcpp(?:14|17|20|latest)\b|cxx_std_(?:11|14|17|20)\b|(?:CMAKE_)?CXX_STANDARD\s+(?:11|14|17|20)\b')
STANDARD_FLAGS = re.compile(r'(?:/|-)(?:std:|std=)((?:c|gnu)\+\+[\w]+)', re.I)


def check_command(command, source):
    flags = STANDARD_FLAGS.findall(command)
    if len(flags) != 1 or flags[0].lower() not in {'c++23', 'c++23preview'}:
        raise ValueError(f'{source}: expected exactly one C++23 flag, got {flags}')


def check_compile_commands(path):
    count = 0
    for entry in json.loads(path.read_text(encoding='utf-8')):
        source = Path(entry['file'])
        # Exclude fetched dependencies, but check every application C++ TU.
        if source.suffix.lower() not in {'.cpp', '.cxx', '.cc'} or '_deps' in source.parts:
            continue
        check_command(entry.get('command') or ' '.join(entry['arguments']), source)
        count += 1
    if not count:
        raise ValueError(f'{path}: no application C++ commands were checked')
    print(f'PASS: {path}: {count} actual C++23 compile commands')


def check_tlog(path):
    lines = path.read_text(encoding='utf-16').splitlines()
    count = 0
    for line in lines:
        if not line.startswith('^') and re.search(r'\.(?:cpp|cxx|cc)\b', line, re.I):
            check_command(line, path)
            count += 1
    if not count:
        raise ValueError(f'{path}: no MSBuild C++ commands were checked')
    print(f'PASS: {path}: {count} actual MSBuild C++23 commands')


def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument('--inventory', action='store_true')
    parser.add_argument('--ref', help='Inventory a baseline git ref without changing the checkout')
    parser.add_argument('--compile-commands', type=Path, action='append', default=[])
    parser.add_argument('--tlog', type=Path, action='append', default=[])
    args = parser.parse_args()
    if args.ref and not args.inventory:
        parser.error('--ref is for inventory only')
    listing = ['git', 'ls-tree', '-r', '--name-only', args.ref] if args.ref else ['git', 'ls-files', '--cached', '--others', '--exclude-standard']
    paths = subprocess.check_output(listing, cwd=ROOT, text=True).splitlines()
    errors = []
    for name in sorted(set(paths)):
        if Path(name).suffix == '.md':
            category = 'documentation'
        elif name == LEGACY_ANDROID:
            category = 'blocked Android legacy (not certified C++23)'
        elif Path(name).name in BUILD_NAMES or Path(name).suffix in BUILD_SUFFIXES:
            category = 'test' if '/tests/' in name or name.startswith('tests/') or name.startswith('.github/') else 'build'
        elif name == 'src/framework/util/BS_thread_pool.hpp':
            category = 'vendor'
        else:
            continue
        content = subprocess.check_output(['git', 'show', f'{args.ref}:{name}'], cwd=ROOT).decode('utf-8', 'replace') if args.ref else (ROOT / name).read_text(encoding='utf-8', errors='replace')
        for line_no, line in enumerate(content.splitlines(), 1):
            if INVENTORY.search(line) and args.inventory:
                print(f'{category}\t{name}:{line_no}\t{line.strip()}')
            if category in {'build', 'test'} and OLD.search(line):
                errors.append(f'{name}:{line_no}: stale C++ mode: {line.strip()}')
    if not args.inventory:
        project = ET.parse(ROOT / 'vc23/otclient.vcxproj')
        ns = {'ms': 'http://schemas.microsoft.com/developer/msbuild/2003'}
        modes = project.findall('.//ms:ItemDefinitionGroup/ms:ClCompile/ms:LanguageStandard', ns)
        if len(modes) != 6 or any(node.text != 'stdcpp23' for node in modes):
            errors.append('All six vc23 configurations must select validated stdcpp23')
        for path in args.compile_commands:
            check_compile_commands(path)
        for path in args.tlog:
            check_tlog(path)
        if errors:
            raise ValueError('\n'.join(errors))
        print('PASS: owned C++ build/test routes; Android explicitly legacy/blocked, C and vendors unchanged')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, ET.ParseError) as error:
        sys.exit(str(error))
