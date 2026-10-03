#!/usr/bin/env python3
"""Normalize known browser-loaded text assets without changing Lua string bytes.

The browser build preloads these files and rejects a Lua source BOM. This
script intentionally operates on an explicit list so it cannot rewrite other
project assets accidentally. Legacy bitmap fonts index bytes, not Unicode;
CP1252 short-string contents must retain their original bytes via Lua escapes.
"""

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ASSETS = (
    "data/locales/de.lua",
    "data/locales/es.lua",
    "data/locales/pt.lua",
    "data/locales/sv.lua",
    "data/shaders/text_golden_shadow_bold_fragment.frag",
    "data/shaders/text_golden_shadow_solid_fragment.frag",
    "mods/game_announcement/announce.lua",
    "mods/game_wheel/classes/bonus.lua",
    "mods/game_wheel/classes/icons.lua",
    "mods/game_analyser/classes/MiscAnalyzer.lua",
    "modules/client_videoplayer/video_player.lua",
    "modules/corelib/const.lua",
    "modules/corelib/networkmessage.lua",
    "modules/game_shaders/shaders/item/item_mirror_fragment.frag",
    "modules/game_shaders/shaders/item/item_rotate_fragment.frag",
    "modules/corelib/ui/video_tooltip.lua",
    "mods/game_proficiency/const.lua",
    "mods/game_proficiency/proficiency.lua",
    "mods/game_proficiency/proficiency_data.lua",
    "modules/client_terminal/commands.lua",
)


LUA_TOKENS = re.compile(
    r'(?P<comment>--(?:\[(?P<ce>=*)\[.*?\](?P=ce)\]|[^\n]*))'
    r'|(?P<long>\[(?P<le>=*)\[.*?\](?P=le)\])'
    r'''|(?P<short>"(?:\\[\s\S]|[^"\\])*"|'(?:\\[\s\S]|[^'\\])*')''',
    re.DOTALL,
)


def preserve_lua_string_bytes(text: str) -> str:
    def replace(match: re.Match[str]) -> str:
        value = match.group()
        if match.group('long') and any(ord(character) > 127 for character in value):
            raise ValueError('Non-ASCII legacy long string needs explicit conversion')
        if not match.group('short'):
            return value
        return ''.join(
            character if ord(character) < 128 else f'\\{character.encode("windows-1252")[0]:03d}'
            for character in value
        )
    return LUA_TOKENS.sub(replace, text)


def decode_asset(raw: bytes, lua: bool = False) -> str:
    if raw.startswith(b"\xef\xbb\xbf"):
        return raw[3:].decode("utf-8")
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError:
        text = raw.decode("windows-1252")
        return preserve_lua_string_bytes(text) if lua else text


def main() -> None:
    changed = 0
    for relative in ASSETS:
        path = ROOT / relative
        raw = path.read_bytes()
        normalized = decode_asset(raw, path.suffix == '.lua').encode("utf-8")
        if normalized != raw:
            path.write_bytes(normalized)
            changed += 1
            print(f"normalized {relative}")
    print(f"normalized {changed} asset(s)")


if __name__ == "__main__":
    main()
