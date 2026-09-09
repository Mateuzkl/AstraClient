#!/usr/bin/env python3
"""Validate and summarize an AstraClient source tree or data.zip package."""

from __future__ import annotations

import argparse
import hashlib
import sys
import zipfile
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Callable, Iterable


PACKAGE_ROOTS = ("data", "modules", "mods", "layouts")
SUSPICIOUS_ROOTS = tuple(f"{root}/{root}/" for root in PACKAGE_ROOTS)
LARGE_DUPLICATE_THRESHOLD = 1024 * 1024


@dataclass(frozen=True)
class Entry:
    name: str
    size: int
    read: Callable[[], bytes]


def normalize_name(name: str) -> str:
    return PurePosixPath(name.replace("\\", "/").lstrip("./")).as_posix()


def source_entries(root: Path) -> Iterable[Entry]:
    candidates = [root / "init.lua", *(root / name for name in PACKAGE_ROOTS)]
    for candidate in candidates:
        if candidate.is_file():
            relative = normalize_name(candidate.relative_to(root).as_posix())
            yield Entry(relative, candidate.stat().st_size, candidate.read_bytes)
        elif candidate.is_dir():
            for path in sorted(candidate.rglob("*")):
                if path.is_file():
                    relative = normalize_name(path.relative_to(root).as_posix())
                    yield Entry(relative, path.stat().st_size, path.read_bytes)


def zip_entries(path: Path) -> list[Entry]:
    archive = zipfile.ZipFile(path)
    entries: list[Entry] = []
    for info in sorted(archive.infolist(), key=lambda value: value.filename):
        if info.is_dir():
            continue
        name = normalize_name(info.filename)
        entries.append(Entry(name, info.file_size, lambda item=info: archive.read(item)))
    return entries


def find_duplicate_payloads(entries: list[Entry]) -> list[list[Entry]]:
    by_size: dict[int, list[Entry]] = defaultdict(list)
    for entry in entries:
        if entry.size >= LARGE_DUPLICATE_THRESHOLD:
            by_size[entry.size].append(entry)

    duplicates: list[list[Entry]] = []
    for same_size in by_size.values():
        if len(same_size) < 2:
            continue
        by_hash: dict[str, list[Entry]] = defaultdict(list)
        for entry in same_size:
            by_hash[hashlib.sha256(entry.read()).hexdigest()].append(entry)
        duplicates.extend(group for group in by_hash.values() if len(group) > 1)
    return sorted(duplicates, key=lambda group: group[0].name)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("target", type=Path, help="repository root or data.zip")
    args = parser.parse_args()

    target = args.target.resolve()
    if target.is_dir():
        entries = list(source_entries(target))
        compressed_size = None
    elif target.is_file() and zipfile.is_zipfile(target):
        entries = zip_entries(target)
        compressed_size = target.stat().st_size
    else:
        parser.error("target must be a repository directory or a ZIP archive")

    names = {entry.name for entry in entries}
    duplicate_names = len(entries) - len(names)
    nested_roots = sorted({
        suspicious.rstrip("/")
        for entry in entries
        for suspicious in SUSPICIOUS_ROOTS
        if entry.name.startswith(suspicious)
    })
    duplicates = find_duplicate_payloads(entries)

    print(f"files: {len(entries)}")
    print(f"uncompressed bytes: {sum(entry.size for entry in entries)}")
    if compressed_size is not None:
        print(f"compressed bytes: {compressed_size}")
    print("largest files:")
    for entry in sorted(entries, key=lambda value: (-value.size, value.name))[:20]:
        print(f"  {entry.size:>12}  {entry.name}")

    print(f"large duplicate payload groups: {len(duplicates)}")
    for group in duplicates:
        print(f"  {group[0].size} bytes: {', '.join(entry.name for entry in group)}")

    errors = []
    if duplicate_names:
        errors.append(f"archive contains {duplicate_names} duplicate file name(s)")
    if nested_roots:
        errors.append(f"suspicious nested roots: {', '.join(nested_roots)}")
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1

    print("package validation: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
