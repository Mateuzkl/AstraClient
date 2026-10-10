"""Build a persistent PNG/LOD pack from the client's offline native export.

No map geometry or image data is fetched from a server. Requires Pillow only
for this one-time build; the game uses its existing PNG loader.
"""
import argparse
import hashlib
import json
import shutil
from collections import defaultdict
from pathlib import Path
from PIL import Image


def build(source: Path, destination: Path, world: Path | None = None,
          items: Path | None = None) -> dict:
    if destination.exists():
        raise ValueError("Destination already exists; use a new directory")
    lines = (source / "index.base.txt").read_text(encoding="utf-8").splitlines()
    magic, version, tile_size, sprite_size, dat_sig, spr_sig, count = lines[0].split()
    if (magic, version, tile_size) != ("ASTRAHDBASE", "1", "16"):
        raise ValueError("Invalid native export header")
    sprite_size, count = int(sprite_size), int(count)
    if not 1 <= count <= 100000 or len(lines) != count + 1:
        raise ValueError("Invalid native export count")
    entries = {}
    destination.mkdir(parents=True)
    for line in lines[1:]:
        level, x, y, z, name = line.split()
        key = tuple(map(int, (level, x, y, z)))
        if key[0] != 1 or name != "satellite-%d-%d-%d-%d.png" % key or key in entries:
            raise ValueError("Invalid/duplicate base chunk")
        with Image.open(source / name) as image:
            if image.size != (16 * sprite_size, 16 * sprite_size):
                raise ValueError(f"Invalid dimensions: {name}")
            image = image.convert("RGBA")
            if image.size != (512, 512):
                image = image.resize((512, 512), Image.Resampling.LANCZOS)
            image.save(destination / name)
        entries[key] = name
    previous = entries.copy()
    for level in (2, 4, 8, 16, 32, 64, 128, 256, 512, 1024):
        groups = defaultdict(list)
        size = 16 * level
        for key, name in previous.items():
            _, x, y, z = key
            groups[(level, x // size * size, y // size * size, z)].append((x, y, name))
        previous = {}
        for key, children in groups.items():
            _, x, y, _ = key
            canvas = Image.new("RGBA", (1024, 1024))
            for child_x, child_y, name in children:
                with Image.open(destination / name) as image:
                    canvas.paste(image, ((child_x - x) // (size // 2) * 512,
                                         (child_y - y) // (size // 2) * 512))
            name = "satellite-%d-%d-%d-%d.png" % key
            canvas.resize((512, 512), Image.Resampling.LANCZOS).save(destination / name)
            previous[key] = name
        entries.update(previous)
        print(f"[HD EXPORT] LOD {level}: {len(previous)} chunks", flush=True)
    # Publish the index only after the entire PNG pyramid was produced.
    manifest = [f"ASTRAHD 1 16 32 {dat_sig} {spr_sig} {len(entries)}"]
    manifest.extend("%d %d %d %d %s" % (*key, name)
                    for key, name in sorted(entries.items()))
    (destination / "index.txt").write_text("\n".join(manifest) + "\n", encoding="utf-8")
    def digest(path):
        if path is None:
            return None
        with path.open("rb") as stream:
            return hashlib.file_digest(stream, "sha256").hexdigest()
    info = {"format": 1, "base_chunks": count, "total_chunks": len(entries),
            "world": world.name if world else None, "world_sha256": digest(world),
            "items_sha256": digest(items), "dat_signature": int(dat_sig),
            "spr_signature": int(spr_sig), "floors": sorted({key[3] for key in entries}),
            "levels": sorted({key[0] for key in entries})}
    (destination / "source.json").write_text(json.dumps(info, indent=2) + "\n", encoding="utf-8")
    if (source / 'minimap.otmm').is_file():
        shutil.copyfile(source / 'minimap.otmm', destination / 'minimap.otmm')
    return info


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--world", type=Path)
    parser.add_argument("--items", type=Path)
    args = parser.parse_args()
    print(json.dumps(build(args.source, args.destination, args.world, args.items), indent=2))
