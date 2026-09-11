#!/usr/bin/env python3
"""Reject text BOMs and asset references that only work on case-insensitive hosts."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TEXT_SUFFIXES = {".lua", ".otui", ".otmod", ".otml", ".frag", ".vert", ".glsl"}
SCAN_ROOTS = ("data", "layouts", "mods", "modules")
VIRTUAL_ROOTS = {"images", "fonts", "shaders", "sounds", "things", "locales"}
REFERENCE_PATTERN = re.compile(
    r"(?P<path>/?(?:images|fonts|shaders|sounds|things|locales|layouts|mods|modules)/"
    r"[A-Za-z0-9_./@+() -]+)"
)


def indexed_files() -> tuple[set[str], dict[str, str]]:
    exact: set[str] = set()
    folded: dict[str, str] = {}
    for root_name in SCAN_ROOTS:
        root = ROOT / root_name
        for path in root.rglob("*"):
            if not path.is_file():
                continue
            relative = path.relative_to(ROOT).as_posix()
            exact.add(relative)
            folded.setdefault(relative.casefold(), relative)
    return exact, folded


def candidate_paths(reference: str) -> list[str]:
    clean = reference.strip().lstrip("/")
    if not clean or any(marker in clean for marker in ("${", "..", "*", "%")):
        return []
    first = clean.split("/", 1)[0]
    if first in VIRTUAL_ROOTS:
        clean = f"data/{clean}"
    candidates = [clean]
    if Path(clean).suffix == "":
        candidates.extend(f"{clean}{suffix}" for suffix in (".png", ".otui", ".lua", ".frag", ".ttf"))
    return candidates


def main() -> int:
    exact, folded = indexed_files()
    errors: list[str] = []
    checked_references = 0
    checked_text_files = 0

    for root_name in SCAN_ROOTS:
        for path in (ROOT / root_name).rglob("*"):
            if not path.is_file() or path.suffix.lower() not in TEXT_SUFFIXES:
                continue
            checked_text_files += 1
            raw = path.read_bytes()
            relative_source = path.relative_to(ROOT).as_posix()
            if raw.startswith(b"\xef\xbb\xbf"):
                errors.append(f"BOM: {relative_source}")
            try:
                text = raw.decode("utf-8-sig")
            except UnicodeDecodeError as error:
                errors.append(f"UTF-8: {relative_source}: {error}")
                continue

            for line_number, line in enumerate(text.splitlines(), 1):
                code = line.split("--", 1)[0]
                for match in REFERENCE_PATTERN.finditer(code):
                    reference = match.group("path").rstrip()
                    candidates = candidate_paths(reference)
                    if not candidates:
                        continue
                    checked_references += 1
                    if any(candidate in exact for candidate in candidates):
                        continue
                    case_match = next((folded[candidate.casefold()] for candidate in candidates if candidate.casefold() in folded), None)
                    if case_match:
                        errors.append(
                            f"CASE: {relative_source}:{line_number}: {reference!r} resolves only as {case_match!r}"
                        )

    print(f"Checked {checked_text_files} text assets and {checked_references} static path references.")
    if errors:
        print("Browser asset validation failed:")
        for error in errors:
            print(f"  {error}")
        return 1
    print("Browser asset validation passed: UTF-8/BOM and exact-case checks are clean.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
