#!/usr/bin/env python3
"""Normalize known browser-loaded text assets to BOM-free UTF-8.

The browser build preloads these files and Lua decodes source as UTF-8. This
script intentionally operates on an explicit list so it cannot rewrite other
project assets accidentally.
"""

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


def decode_asset(raw: bytes) -> str:
    if raw.startswith(b"\xef\xbb\xbf"):
        return raw[3:].decode("utf-8")
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError:
        return raw.decode("windows-1252")


def main() -> None:
    changed = 0
    for relative in ASSETS:
        path = ROOT / relative
        raw = path.read_bytes()
        normalized = decode_asset(raw).encode("utf-8")
        if normalized != raw:
            path.write_bytes(normalized)
            changed += 1
            print(f"normalized {relative}")
    print(f"normalized {changed} asset(s)")


if __name__ == "__main__":
    main()
